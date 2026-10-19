import Foundation
import CoreLocation
import Combine

/// Reactive location data hub for SwiftUI map views.
/// Bridges AdaptiveLocationManager (non-reactive) → @Published properties.
/// Also tracks member locations and provides follow-mode control.
final class ReactiveLocationService: ObservableObject {

    // MARK: - Published State

    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var currentHeading: CLLocationDirection = 0
    @Published var currentAccuracy: Double = 0
    @Published var memberLocations: [String: MemberLocation] = [:]
    @Published var followMode: FollowMode = .followMe
    @Published var lastUpdateTime: Date?

    // MARK: - Types

    enum FollowMode: Equatable {
        case free
        case followMe
        case followPerson(id: String)
    }

    struct MemberLocation: Equatable {
        let userId: String
        let coordinate: CLLocationCoordinate2D
        let accuracy: Double
        let timestamp: Date
        let battery: Double?
        let isOnline: Bool

        static func == (lhs: MemberLocation, rhs: MemberLocation) -> Bool {
            lhs.userId == rhs.userId
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.timestamp == rhs.timestamp
        }
    }

    // MARK: - Dependencies

    private weak var locationManager: AdaptiveLocationManager?
    private var updateTimer: Timer?

    init() {}

    /// Bind to AdaptiveLocationManager's callbacks to feed @Published state.
    func bind(to manager: AdaptiveLocationManager) {
        self.locationManager = manager

        // Wire location report callback
        let existingCallback = manager.onLocationReport
        manager.onLocationReport = { [weak self, existingCallback] location in
            existingCallback?(location)
            DispatchQueue.main.async { [weak self] in
                self?.currentLocation = CLLocationCoordinate2D(
                    latitude: location.latitude,
                    longitude: location.longitude
                )
                self?.currentAccuracy = location.accuracy
                self?.lastUpdateTime = location.timestamp
            }
        }

        // Seed with best available location
        if let loc = manager.bestAvailableLocation {
            currentLocation = loc.coordinate
            currentAccuracy = loc.horizontalAccuracy
            lastUpdateTime = loc.timestamp
        }

        // Poll for location updates that bypass the report callback
        // (e.g. deduplication filters, or cached CLLocationManager updates)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self, weak manager] _ in
            guard let self, let manager else { return }
            if let loc = manager.bestAvailableLocation {
                let coord = loc.coordinate
                // Only update if meaningfully different
                DispatchQueue.main.async {
                    if self.currentLocation == nil
                        || self.distance(from: self.currentLocation!, to: coord) > 5 {
                        self.currentLocation = coord
                        self.currentAccuracy = loc.horizontalAccuracy
                        self.lastUpdateTime = loc.timestamp
                    }
                }
            }
        }
    }

    /// Update member location from server data (ProtectedPerson or Guardian).
    func updateMember(
        userId: String,
        coordinate: CLLocationCoordinate2D,
        accuracy: Double = 0,
        timestamp: Date = Date(),
        battery: Double? = nil,
        isOnline: Bool = true
    ) {
        memberLocations[userId] = MemberLocation(
            userId: userId,
            coordinate: coordinate,
            accuracy: accuracy,
            timestamp: timestamp,
            battery: battery,
            isOnline: isOnline
        )
    }

    /// Remove member who left the group.
    func removeMember(userId: String) {
        memberLocations.removeValue(forKey: userId)
    }

    /// Clear all member locations.
    func clearMembers() {
        memberLocations.removeAll()
    }

    /// Request a fresh location fix.
    func requestLocation() {
        locationManager?.requestSingleLocation()
    }

    /// Minutes since last location update, or nil if no update yet.
    var lastUpdateMinutes: Int? {
        guard let t = lastUpdateTime else { return nil }
        return max(0, Int(Date().timeIntervalSince(t) / 60))
    }

    // MARK: - Helpers

    private func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    deinit {
        updateTimer?.invalidate()
    }
}
