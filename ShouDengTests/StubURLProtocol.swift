import Foundation

/// Test transport: every request is answered by `handler` (or fails), and is
/// recorded. Nothing reaches the network.
final class StubURLProtocol: URLProtocol {
    struct Recorded {
        let method: String
        let host: String
        let path: String
        let body: Data?
        let timeout: TimeInterval
        let authorization: String?
    }

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var requests: [Recorded] = []
    /// Seconds before the answer (or failure) arrives; nil/0 = at once. A cancelled
    /// request never gets its late answer.
    nonisolated(unsafe) static var delay: ((URLRequest) -> TimeInterval)?
    private static let lock = NSLock()
    private let stateLock = NSLock()
    private var stopped = false

    static func reset() {
        lock.withLock {
            handler = nil
            delay = nil
            requests = []
        }
    }

    static var recorded: [Recorded] { lock.withLock { requests } }

    static func session() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            body = data
        }
        let path = request.url?.path ?? ""
        Self.lock.withLock {
            Self.requests.append(Recorded(
                method: request.httpMethod ?? "GET",
                host: request.url?.host ?? "",
                path: path,
                body: body,
                timeout: request.timeoutInterval,
                authorization: request.value(forHTTPHeaderField: "Authorization")
            ))
        }
        let wait = Self.lock.withLock { Self.delay }?(request) ?? 0
        guard wait > 0 else { return answer(body: body) }
        DispatchQueue.global().asyncAfter(deadline: .now() + wait) { [self] in
            guard !stateLock.withLock({ stopped }) else { return }
            answer(body: body)
        }
    }

    private func answer(body: Data?) {
        guard let handler = Self.lock.withLock({ Self.handler }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            var req = request
            req.httpBody = body
            let (status, data) = try handler(req)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        stateLock.withLock { stopped = true }
    }
}
