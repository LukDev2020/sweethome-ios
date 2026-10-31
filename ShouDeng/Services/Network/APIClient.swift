import Foundation

// MARK: - API Client
//
// URLSession-based HTTP client with:
//   - Bearer token auth (+ one refresh-and-retry on 401)
//   - One retry on 5xx / transport error — for idempotent methods only. A POST
//     whose response we failed to read may already have been applied (SOS!).
//   - JSON encode/decode with iso8601 dates
//   - Typed errors for UI consumption
//   - Persist-first offline queue for requests that must eventually arrive

final class APIClient {

    // MARK: - Configuration

    struct Config {
        var baseURL: String
        var timeoutInterval: TimeInterval = 30
        var maxRetries: Int = 1
        /// SOS requests fail over to the queue fast instead of waiting ~61 s.
        var sosTimeoutInterval: TimeInterval = 8
    }

    private let config: Config
    private let session: URLSession
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    private let tokenLock = NSLock()
    private var _accessToken: String?
    private var accessToken: String? {
        get { tokenLock.withLock { _accessToken } }
        set { tokenLock.withLock { _accessToken = newValue } }
    }
    let offlineQueue: OfflineQueue

    /// Called when a 401 is received. The closure should attempt a token refresh
    /// and return true if the token was refreshed successfully.
    var onUnauthorized: (() async -> Bool)?

    /// Id of the signed-in user; queued items are tagged with it and only replayed
    /// for that same user.
    var currentOwnerId: (() -> String?)?

    /// Called after a flush with the queued items that reached the server.
    var onQueuedItemsDelivered: (([OfflineQueue.Item]) -> Void)?

    private let flushLock = NSLock()
    private var isFlushing = false

    /// Which requests may use carrier satellite data, and how often periodic ones go.
    let satellitePolicy = SatelliteDataPolicy()

    /// - Parameter sessionConfiguration: inject a configuration with custom
    ///   `protocolClasses` (Explore Mode's DemoURLProtocol, tests).
    init(config: Config, offlineQueue: OfflineQueue, sessionConfiguration: URLSessionConfiguration = .default) {
        self.config = config
        self.offlineQueue = offlineQueue

        let sessionConfig = sessionConfiguration
        sessionConfig.timeoutIntervalForRequest = config.timeoutInterval
        if #available(iOS 26.1, *) {
            // Each request opts in or out below (SatelliteDataPolicy); the session must allow it.
            sessionConfig.allowsUltraConstrainedNetworkAccess = true
        }
        self.session = URLSession(configuration: sessionConfig)

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            // Fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
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

    /// POST that must not trigger the 401 → refresh path (the refresh call itself:
    /// a 401 there awaiting a refresh would wait on itself forever).
    func postWithoutRefresh<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let request = try buildRequest(path: path, method: "POST", body: body)
        return try await execute(request, allowRefresh: false)
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
    /// The item is enqueued to disk FIRST so it survives app termination, then sent
    /// immediately if possible.
    func postQueued<B: Encodable>(_ path: String, body: B, onResult: ((Bool) -> Void)?) {
        // On satellite, periodic heartbeats / location reports are thinned: a skipped
        // one is neither sent nor queued (a stale heartbeat has no value later).
        if satellitePolicy.shouldSkip(path: path) {
            onResult?(false)
            return
        }
        guard let bodyData = try? encoder.encode(body) else {
            onResult?(false)
            return
        }
        let itemId = offlineQueue.enqueue(OfflineQueue.Item(
            method: "POST", path: path, body: bodyData, ownerId: currentOwnerId?()
        ))

        Task {
            let delivered = await self.sendQueuedNow(itemId: itemId, path: path, body: bodyData, timeout: nil)
            await MainActor.run { onResult?(delivered != nil) }
        }
    }

    /// SOS delivery: persist first, then try immediately with a short timeout.
    /// Returns the decoded response if the server answered in time; otherwise the
    /// request stays queued for the next flush (connectivity change, foreground).
    func postSOS<B: Encodable, T: Decodable>(_ path: String, body: B) async -> T? {
        guard let bodyData = try? encoder.encode(body) else { return nil }
        let itemId = offlineQueue.enqueue(OfflineQueue.Item(
            method: "POST", path: path, body: bodyData, ownerId: currentOwnerId?()
        ))
        guard let data = await sendQueuedNow(itemId: itemId, path: path, body: bodyData, timeout: config.sosTimeoutInterval)
        else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// Sends one queued item. Removes it from the queue when the server accepted
    /// it or permanently rejected it; returns the response body on 2xx.
    private func sendQueuedNow(itemId: String, path: String, body: Data, timeout: TimeInterval?) async -> Data? {
        do {
            var request = try buildRawRequest(path: path, method: "POST")
            request.httpBody = body
            if let timeout { request.timeoutInterval = timeout }
            var (data, response) = try await session.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 401, let refresh = onUnauthorized, await refresh() {
                var retry = try buildRawRequest(path: path, method: "POST")
                retry.httpBody = body
                if let timeout { retry.timeoutInterval = timeout }
                (data, response) = try await session.data(for: retry)
            }
            guard let http = response as? HTTPURLResponse else { return nil }
            switch Self.disposition(for: http.statusCode) {
            case .delivered:
                offlineQueue.removeItems(withIds: [itemId])
                return data
            case .drop:
                offlineQueue.removeItems(withIds: [itemId])
                return nil
            case .keep, .stopFlush:
                return nil
            }
        } catch {
            // Network error — already in queue, will be flushed later
            return nil
        }
    }

    // MARK: - Flush Offline Queue

    enum Disposition: Equatable { case delivered, drop, keep, stopFlush }

    /// What to do with a queued item after the server answered `status`.
    static func disposition(for status: Int) -> Disposition {
        switch status {
        case 200...399: return .delivered
        case 401: return .keep        // token problem — try again after refresh / next login
        case 408: return .keep        // request timeout
        case 429: return .stopFlush   // rate limited — keep everything, back off
        case 400...499: return .drop  // permanent client error (validation, forbidden, gone)
        default: return .keep         // 5xx — retry later
        }
    }

    func flushOfflineQueue() async {
        let started: Bool = flushLock.withLock {
            if isFlushing { return false }
            isFlushing = true
            return true
        }
        guard started else { return }
        defer { flushLock.withLock { isFlushing = false } }

        let owner = currentOwnerId?()
        // Only replay items queued by the signed-in user (or legacy untagged items).
        let items = offlineQueue.peekAll().filter { $0.ownerId == nil || $0.ownerId == owner }
        guard !items.isEmpty, owner != nil else { return }

        var done = Set<String>()
        var delivered: [OfflineQueue.Item] = []
        var didRefreshToken = false

        // SOS first: a flush right after connectivity returns must deliver it before telemetry
        let ordered = items.filter(\.isSOS) + items.filter { !$0.isSOS }

        itemLoop: for item in ordered {
            do {
                var request = try buildRawRequest(path: item.path, method: item.method)
                request.httpBody = item.body
                var (_, response) = try await session.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 401, !didRefreshToken, let refresh = onUnauthorized {
                    didRefreshToken = true
                    if await refresh() {
                        var retry = try buildRawRequest(path: item.path, method: item.method)
                        retry.httpBody = item.body
                        (_, response) = try await session.data(for: retry)
                    }
                }
                guard let http = response as? HTTPURLResponse else { continue }
                switch Self.disposition(for: http.statusCode) {
                case .delivered:
                    done.insert(item.id)
                    delivered.append(item)
                case .drop:
                    done.insert(item.id)
                case .keep:
                    break
                case .stopFlush:
                    break itemLoop
                }
            } catch {
                // Offline again: stop, keep the rest for next time
                break itemLoop
            }
        }
        offlineQueue.removeItems(withIds: done)
        if !delivered.isEmpty {
            let callback = onQueuedItemsDelivered
            let deliveredItems = delivered
            await MainActor.run { callback?(deliveredItems) }
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

    /// Test hook: sees every request any APIClient builds (Explore Mode isolation tests).
    nonisolated(unsafe) static var requestObserver: ((URLRequest) -> Void)?

    func buildRawRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: config.baseURL + path) else {
            throw APIError.invalidURL
        }
        defer { if let observer = Self.requestObserver { observer(URLRequest(url: url)) } }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if #available(iOS 26.1, *) {
            request.allowsUltraConstrainedNetworkAccess = SatelliteDataPolicy.allowsSatellite(path: path)
        }
        return request
    }

    private static func isIdempotent(_ request: URLRequest) -> Bool {
        ["GET", "PUT", "DELETE", "HEAD"].contains(request.httpMethod ?? "GET")
    }

    private func execute<T: Decodable>(_ request: URLRequest, attempt: Int = 0, allowRefresh: Bool = true) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Transport error: the server may or may not have applied a POST.
            if Self.isIdempotent(request), attempt < config.maxRetries {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return try await execute(request, attempt: attempt + 1, allowRefresh: allowRefresh)
            }
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        switch http.statusCode {
        case 200...299:
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            if T.self == RawResponse.self {
                return RawResponse(data: data) as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                // Never retry on a decode error: the request already succeeded.
                throw APIError.decoding(error)
            }
        case 401:
            // Attempt token refresh on first 401
            if allowRefresh, attempt == 0, let refresh = onUnauthorized {
                let refreshed = await refresh()
                if refreshed {
                    // Rebuild request with new token
                    var retryRequest = request
                    if let token = self.accessToken {
                        retryRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    return try await execute(retryRequest, attempt: attempt + 1, allowRefresh: false)
                }
            }
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            throw APIError.conflict
        case 422:
            let detail = try? decoder.decode(ValidationError.self, from: data)
            throw APIError.validation(detail?.message ?? "请求参数有误")
        case 429:
            throw APIError.rateLimited
        case 500...599:
            if Self.isIdempotent(request), attempt < config.maxRetries {
                try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * (attempt + 1)))
                return try await execute(request, attempt: attempt + 1, allowRefresh: allowRefresh)
            }
            throw APIError.serverError(http.statusCode)
        default:
            throw APIError.serverError(http.statusCode)
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
    case conflict
    case validation(String)
    case rateLimited
    case serverError(Int)
    case networkError(Error)
    case decoding(Error)
    case unknown

    /// A failure that says nothing about whether the session is valid
    /// (offline, timeout, server trouble, rate limit).
    var isTransient: Bool {
        switch self {
        case .networkError, .serverError, .rateLimited, .unknown: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "无效的请求地址"
        case .unauthorized:         return "登录已过期，请重新登录"
        case .forbidden:            return "无权执行此操作"
        case .notFound:             return "请求的资源不存在"
        case .conflict:             return "状态已变更，请刷新"
        case .validation(let msg):  return msg
        case .rateLimited:          return "请求过于频繁，请稍后再试"
        case .serverError(let c):   return "服务器错误（\(c)）"
        case .networkError:         return "网络连接失败，请检查网络设置"
        case .decoding:             return "服务器返回的数据无法读取"
        case .unknown:              return "未知错误"
        }
    }
}

// MARK: - Server Validation Error

struct ValidationError: Codable {
    let message: String
}

/// The response body as-is (e.g. the account data export, saved to a file).
struct RawResponse: Decodable {
    let data: Data
    init(data: Data) { self.data = data }
    init(from decoder: Decoder) throws {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "RawResponse is not decoded"))
    }
}
