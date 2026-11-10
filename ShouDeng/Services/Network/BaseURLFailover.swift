import Foundation

// MARK: - Base URL failover: primary (Google) ↔ Hong Kong relay
//
// Mainland-China networks block cloudfunctions.net. The relay (docs/ops/CHINA-RELAY.md)
// forwards https://api.<domain>/… to the same backend. Info.plist API_RELAY_URL
// turns it on (empty = off, everything as before).
//
// - A request whose primary attempt fails in transit (DNS, connect, TLS, timeout —
//   never an HTTP error) is tried on the other base. If that one answers, it becomes
//   the preferred base: the relay for 24 h, re-armed while the primary stays blocked.
// - While on the relay the primary is re-checked in the background (at most hourly)
//   and used again as soon as it answers.
// - Being offline is not a reason to switch: the preference only changes when the
//   other base actually answered.

final class BaseURLFailover {

    /// What a transport failure says about whether the request reached the server.
    enum Failure: Equatable {
        /// No network at all: the other base won't work either.
        case offline
        /// The request never left (DNS, connect, TLS handshake): safe to resend anywhere.
        case neverSent
        /// It may have reached the server (timeout, connection dropped mid-way):
        /// resend only what is idempotent or deduped by the server.
        case ambiguous
        /// Cancelled, or not a transport problem.
        case other
    }

    static func classify(_ error: Error) -> Failure {
        guard let e = error as? URLError else { return .other }
        switch e.code {
        case .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed, .callIsActive:
            return .offline
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed,
             .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            return .neverSent
        case .timedOut, .networkConnectionLost, .badServerResponse, .cannotParseResponse:
            return .ambiguous
        default:
            return .other
        }
    }

    static let relayStickyInterval: TimeInterval = 24 * 3600
    static let primaryRecheckInterval: TimeInterval = 3600
    /// Minimum gap between route checks triggered by a failure (not the hourly one).
    static let eventCheckInterval: TimeInterval = 60
    static let defaultsKey = "api.relayPreferredUntil"

    let primary: String
    /// nil = no relay configured.
    let relay: String?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let lock = NSLock()
    private var lastCheck: Date?

    init(primary: String, relay: String?, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.primary = Self.trimmed(primary)
        let r = relay.map(Self.trimmed)
        self.relay = (r?.isEmpty ?? true) || r == self.primary ? nil : r
        self.defaults = defaults
        self.now = now
    }

    private static func trimmed(_ s: String) -> String {
        var v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while v.hasSuffix("/") { v.removeLast() }
        return v
    }

    // MARK: - Which base

    var relayPreferredUntil: Date? {
        lock.withLock { defaults.object(forKey: Self.defaultsKey) as? Date }
    }

    /// True while requests go to the relay first.
    var isUsingRelay: Bool {
        guard relay != nil, let until = relayPreferredUntil else { return false }
        return until > now()
    }

    /// Where new requests go.
    var current: String { isUsingRelay ? relay! : primary }

    /// The other base, if there is one.
    func alternate(to base: String) -> String? {
        guard let relay else { return nil }
        if base == primary { return relay }
        if base == relay { return primary }
        return nil
    }

    /// Which of our bases `url` belongs to.
    func base(of url: URL?) -> String? {
        guard let s = url?.absoluteString else { return nil }
        // Longest first: one base could be a prefix of the other
        return [primary, relay].compactMap { $0 }
            .sorted { $0.count > $1.count }
            .first { s.hasPrefix($0) }
    }

    /// The same request sent to `target` instead of the base it was built for.
    func rebased(_ request: URLRequest, to target: String) -> URLRequest? {
        guard let from = base(of: request.url), from != target,
              let s = request.url?.absoluteString,
              let url = URL(string: target + s.dropFirst(from.count)) else { return nil }
        var copy = request
        copy.url = url
        return copy
    }

    // MARK: - Learning

    /// A request failed in transit on `base` and `other` answered (any HTTP status).
    func failedInTransit(on base: String, thenAnswered other: String) {
        if other == relay, base == primary {
            preferRelay()
        } else if other == primary {
            preferPrimary()
        }
    }

    /// Result of a route check (GET /health on each base).
    func recordCheck(primaryAnswered: Bool, relayAnswered: Bool) {
        if primaryAnswered {
            preferPrimary()
        } else if relayAnswered {
            preferRelay()
        }
    }

    private func preferRelay() {
        guard relay != nil else { return }
        lock.withLock { defaults.set(now().addingTimeInterval(Self.relayStickyInterval), forKey: Self.defaultsKey) }
    }

    private func preferPrimary() {
        lock.withLock { defaults.removeObject(forKey: Self.defaultsKey) }
    }

    /// Claims the next route check. `afterFailure`: a request just failed in transit
    /// (checked at most once a minute); otherwise the hourly re-check of the primary
    /// while on the relay.
    func claimCheck(afterFailure: Bool) -> Bool {
        guard relay != nil else { return false }
        if !afterFailure && !isUsingRelay { return false }
        let interval = afterFailure ? Self.eventCheckInterval : Self.primaryRecheckInterval
        return lock.withLock {
            let t = now()
            if let last = lastCheck, t.timeIntervalSince(last) < interval { return false }
            lastCheck = t
            return true
        }
    }
}
