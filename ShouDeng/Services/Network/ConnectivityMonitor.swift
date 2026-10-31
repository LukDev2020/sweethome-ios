import Foundation
import Network

// MARK: - Connectivity Monitor
//
// Flushes the offline queue the moment the network comes back (an SOS queued in
// a lift or a tunnel must not wait for the next app foreground).

final class ConnectivityMonitor {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.shoudeng.connectivity", qos: .utility)
    private var wasSatisfied: Bool?

    /// Called on the main queue whenever the path goes from unsatisfied to satisfied.
    var onBecameReachable: (() -> Void)?

    /// Called on the main queue when the path switches to or from carrier satellite
    /// data ("ultra-constrained", iOS 26+).
    var onSatelliteChanged: ((Bool) -> Void)?

    private(set) var isReachable = true
    private(set) var isOnSatellite = false

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            var ultraConstrained = false
            if #available(iOS 26.0, *) {
                ultraConstrained = path.isUltraConstrained
            }
            self?.handle(satisfied: path.status == .satisfied, ultraConstrained: ultraConstrained)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    /// Exposed for tests.
    func handle(satisfied: Bool, ultraConstrained: Bool = false) {
        let previous = wasSatisfied
        wasSatisfied = satisfied
        isReachable = satisfied
        if satisfied, previous == false {
            DispatchQueue.main.async { [weak self] in self?.onBecameReachable?() }
        }
        let onSatellite = satisfied && ultraConstrained
        if onSatellite != isOnSatellite {
            isOnSatellite = onSatellite
            DispatchQueue.main.async { [weak self] in self?.onSatelliteChanged?(onSatellite) }
        }
    }
}
