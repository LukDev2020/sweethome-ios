import Foundation

// MARK: - Satellite Data Policy
//
// Carrier-provided satellite data (iOS 26.1+, e.g. T-Mobile T-Satellite, One NZ,
// Spark, KDDI au Starlink Direct) shows up as an "ultra-constrained" path. Only
// requests that keep someone safe may use it, and periodic ones are thinned so a
// few hundred bytes every ten minutes is all we send:
//   - SOS, check-in, home timer, arrival report: always allowed, never thinned
//   - heartbeat, single location report: allowed, at most once per `minInterval`
//   - everything else (feed, media, trips upload, profile…): not allowed — it waits
//     for a normal connection
// Requires the `com.apple.developer.networking.carrier-constrained.appcategory`
// entitlement (category `hiking-adventure-8003`).

final class SatelliteDataPolicy {

    /// Requests allowed over a satellite path.
    static let essentialPrefixes = [
        "/v1/sos/",
        "/v1/checkin",
        "/v1/home-timer",
        "/v1/arrival-report",
        "/v1/ble-separation",
        "/v1/heartbeat",
        "/v1/location/report",
    ]

    /// Essential but periodic: thinned while on satellite.
    static let throttledPaths: Set<String> = ["/v1/heartbeat", "/v1/location/report"]

    let minInterval: TimeInterval
    private let lock = NSLock()
    private var _isOnSatellite = false
    private var lastSent: [String: Date] = [:]

    init(minInterval: TimeInterval = 600) {
        self.minInterval = minInterval
    }

    var isOnSatellite: Bool {
        get { lock.withLock { _isOnSatellite } }
        set { lock.withLock { _isOnSatellite = newValue } }
    }

    /// Whether this request may travel over a satellite (ultra-constrained) path.
    static func allowsSatellite(path: String) -> Bool {
        essentialPrefixes.contains { path.hasPrefix($0) }
    }

    /// True when a periodic request should be skipped (not sent, not queued)
    /// because one went out over satellite less than `minInterval` ago.
    /// Records the send otherwise.
    func shouldSkip(path: String, now: Date = Date()) -> Bool {
        guard Self.throttledPaths.contains(path) else { return false }
        return lock.withLock {
            guard _isOnSatellite else { return false }
            if let last = lastSent[path], now.timeIntervalSince(last) < minInterval {
                return true
            }
            lastSent[path] = now
            return false
        }
    }
}
