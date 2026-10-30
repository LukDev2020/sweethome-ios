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

    private(set) var isReachable = true

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handle(satisfied: path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    /// Exposed for tests.
    func handle(satisfied: Bool) {
        let previous = wasSatisfied
        wasSatisfied = satisfied
        isReachable = satisfied
        if satisfied, previous == false {
            DispatchQueue.main.async { [weak self] in self?.onBecameReachable?() }
        }
    }
}
