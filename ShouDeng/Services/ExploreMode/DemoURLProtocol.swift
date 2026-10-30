import Foundation

// MARK: - Demo URL Protocol
//
// Installed ONLY on the Explore Mode APIClient's URLSession. Every request is
// answered on the device from DemoStore; a request for any other host, or one
// the demo doesn't implement, FAILS — nothing can reach a real server.

final class DemoURLProtocol: URLProtocol {

    static let host = "demo.lanterncare.invalid"
    static var baseURL: String { "https://\(host)/api" }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _store: DemoStore?
    nonisolated(unsafe) private static var _handled: [String] = []
    nonisolated(unsafe) private static var _violations: [String] = []

    static var store: DemoStore? {
        get { lock.withLock { _store } }
        set { lock.withLock { _store = newValue } }
    }

    /// Requests answered from the demo store ("GET /v1/user/me").
    static var handled: [String] { lock.withLock { _handled } }
    /// Requests aimed anywhere other than the demo host — must stay empty.
    static var violations: [String] { lock.withLock { _violations } }

    static func resetLog() {
        lock.withLock {
            _handled = []
            _violations = []
        }
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoURLProtocol.self]
        config.urlCache = nil
        config.httpCookieStorage = nil
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.host == Self.host else {
            Self.lock.withLock { Self._violations.append(request.url?.absoluteString ?? "?") }
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        var path = url.path
        if path.hasPrefix("/api") { path.removeFirst(4) }
        let method = request.httpMethod ?? "GET"
        var query: [String: String] = [:]
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.forEach { query[$0.name] = $0.value }
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)

        let key = "\(method) \(path)"
        Self.lock.withLock { Self._handled.append(key) }

        let response: (Int, Data)
        if let store = Self.store {
            if let r = store.respond(method: method, path: path, query: query, body: body) {
                response = r
            } else {
                store.noteUnhandled(key)
                response = (404, Data(#"{"error":"Not available in the demo"}"#.utf8))
            }
        } else {
            response = (503, Data(#"{"error":"Demo not running"}"#.utf8))
        }

        let http = HTTPURLResponse(url: url, statusCode: response.0, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
