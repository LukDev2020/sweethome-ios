import Foundation

// MARK: - API Client
//
// URLSession-based HTTP client with:
//   - Bearer token auth
//   - Automatic retry (1 retry on 5xx / network error)
//   - JSON encode/decode with iso8601 dates
//   - Typed errors for UI consumption

final class APIClient {

    // MARK: - Configuration

    struct Config {
        var baseURL: String
        var timeoutInterval: TimeInterval = 30
        var maxRetries: Int = 1
    }

    private let config: Config
    private let session: URLSession
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    private var accessToken: String?
    private let offlineQueue: OfflineQueue

    /// Called when a 401 is received. The closure should attempt a token refresh
    /// and return true if the token was refreshed successfully.
    var onUnauthorized: (() async -> Bool)?

    init(config: Config, offlineQueue: OfflineQueue) {
        self.config = config
        self.offlineQueue = offlineQueue

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeoutInterval
        self.session = URLSession(configuration: sessionConfig)

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Token

    func setAccessToken(_ token: String?) {
        self.accessToken = token
    }

    // MARK: - GET

    func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "GET", body: nil as Empty?)
        return try await execute(request)
    }

    // MARK: - POST

    func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let request = try buildRequest(path: path, method: "POST", body: body)
        return try await execute(request)
    }

    // MARK: - PUT

    func put<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let request = try buildRequest(path: path, method: "PUT", body: body)
        return try await execute(request)
    }

    // MARK: - DELETE

    func delete<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "DELETE", body: nil as Empty?)
        return try await execute(request)
    }

    // MARK: - Fire-and-Forget (queues offline if network fails)

    func postQueued<B: Encodable>(_ path: String, body: B) {
        postQueued(path, body: body, onResult: nil)
    }

    /// Fire-and-forget with optional result callback for critical operations (e.g. SOS).
    func postQueued<B: Encodable>(_ path: String, body: B, onResult: ((Bool) -> Void)?) {
        guard let bodyData = try? encoder.encode(body) else {
            onResult?(false)
            return
        }
        let item = OfflineQueue.Item(
            method: "POST",
            path: path,
            body: bodyData
        )

        Task {
            do {
                let request = try buildRequest(path: path, method: "POST", body: body)
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode >= 500 {
                    offlineQueue.enqueue(item)
                    await MainActor.run { onResult?(false) }
                } else {
                    await MainActor.run { onResult?(true) }
                }
            } catch {
                offlineQueue.enqueue(item)
                await MainActor.run { onResult?(false) }
            }
        }
    }

    // MARK: - Flush Offline Queue

    func flushOfflineQueue() async {
        let items = offlineQueue.dequeueAll()
        for item in items {
            do {
                var request = try buildRawRequest(path: item.path, method: item.method)
                request.httpBody = item.body
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode >= 500 {
                    offlineQueue.enqueue(item)
                }
            } catch {
                offlineQueue.enqueue(item)
            }
        }
    }

    // MARK: - Private

    private func buildRequest<B: Encodable>(path: String, method: String, body: B?) throws -> URLRequest {
        var request = try buildRawRequest(path: path, method: method)
        if let body, !(body is Empty) {
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    private func buildRawRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: config.baseURL + path) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest, attempt: Int = 0) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw APIError.unknown
            }

            switch http.statusCode {
            case 200...299:
                if T.self == EmptyResponse.self {
                    return EmptyResponse() as! T
                }
                return try decoder.decode(T.self, from: data)
            case 401:
                // Attempt token refresh on first 401
                if attempt == 0, let refresh = onUnauthorized {
                    let refreshed = await refresh()
                    if refreshed {
                        // Rebuild request with new token
                        var retryRequest = request
                        if let token = self.accessToken {
                            retryRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        }
                        return try await execute(retryRequest, attempt: attempt + 1)
                    }
                }
                throw APIError.unauthorized
            case 403:
                throw APIError.forbidden
            case 404:
                throw APIError.notFound
            case 422:
                let detail = try? decoder.decode(ValidationError.self, from: data)
                throw APIError.validation(detail?.message ?? "请求参数有误")
            case 429:
                throw APIError.rateLimited
            case 500...599:
                if attempt < config.maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * (attempt + 1)))
                    return try await execute(request, attempt: attempt + 1)
                }
                throw APIError.serverError(http.statusCode)
            default:
                throw APIError.serverError(http.statusCode)
            }
        } catch let error as APIError {
            throw error
        } catch {
            if attempt < config.maxRetries {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return try await execute(request, attempt: attempt + 1)
            }
            throw APIError.networkError(error)
        }
    }
}

// MARK: - Placeholder for nil body

private struct Empty: Encodable {}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case validation(String)
    case rateLimited
    case serverError(Int)
    case networkError(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "无效的请求地址"
        case .unauthorized:         return "登录已过期，请重新登录"
        case .forbidden:            return "无权执行此操作"
        case .notFound:             return "请求的资源不存在"
        case .validation(let msg):  return msg
        case .rateLimited:          return "请求过于频繁，请稍后再试"
        case .serverError(let c):   return "服务器错误（\(c)）"
        case .networkError:         return "网络连接失败，请检查网络设置"
        case .unknown:              return "未知错误"
        }
    }
}

// MARK: - Server Validation Error

struct ValidationError: Codable {
    let message: String
}
