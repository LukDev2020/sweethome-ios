import Foundation
import CoreLocation

// MARK: - Adaptive Location Manager
//
// Algorithm 4: Location & Battery Optimization
//
// Four sampling modes that switch automatically based on state:
//   - Safe:    In known safe zone → significant changes only (~0% battery)
//   - Unknown: Stationary in unknown area → every 10 min
//   - Moving:  In transit → every 60 sec
//   - SOS:     Emergency → every 5 sec, best accuracy
//
// Also handles:
//   - iOS 20-region geofence limit via dynamic swap scheduling
//   - Dwell-point clustering to auto-discover safe zones
//   - Deduplication to avoid flooding the server

final class AdaptiveLocationManager: NSObject {

    // MARK: - Location Modes

    enum LocationMode: String {
        case safe           // In known safe zone
        case unknown        // Stationary but not in safe zone
        case moving         // In transit
        case sos            // Emergency — max accuracy

        var desiredAccuracy: CLLocationAccuracy {
            switch self {
            case .safe: return kCLLocationAccuracyHundredMeters
            case .unknown: return kCLLocationAccuracyHundredMeters
            case .moving: return kCLLocationAccuracyNearestTenMeters
            case .sos: return kCLLocationAccuracyBest
            }
        }

        var distanceFilter: CLLocationDistance {
            switch self {
            case .safe: return kCLDistanceFilterNone  // Using significant changes instead
            case .unknown: return 50
            case .moving: return 30
            case .sos: return kCLDistanceFilterNone
            }
        }

        var reportIntervalSec: TimeInterval {
            switch self {
            case .safe: return .infinity     // Only on significant change
            case .unknown: return 600        // 10 minutes
            case .moving: return 60          // 1 minute
            case .sos: return 5              // 5 seconds
            }
        }
    }

    // MARK: - Configuration

    struct Config {
        var movingSpeedThreshold: Double = 1.5         // m/s — walking speed
        var stationarySpeedThreshold: Double = 0.5     // m/s
        var deduplicationDistanceMeters: Double = 50    // Don't report if moved < 50m
        var deduplicationTimeSec: TimeInterval = 120    // Don't report more than once per 2 min (except SOS)
        var maxGeofenceRegions: Int = 18                // Reserve 2 of iOS's 20 for system use
        var dwellPointRadiusMeters: Double = 200
        var dwellPointMinDurationSec: TimeInterval = 1200  // 20 minutes
    }

    // MARK: - Properties

    private lazy var locationManager = CLLocationManager()
    private let config: Config
    private(set) var currentMode: LocationMode = .safe
    private var safeZones: [SafeZone] = []
    private var monitoredRegionIds: Set<String> = []

    // Reporting
    private var lastReportedLocation: CLLocation?
    private var lastReportTime: Date?

    // Dwell-point tracking
    private var dwellCandidates: [DwellCandidate] = []
    private var locationHistory: [CLLocation] = []
    private let historyLimit = 500

    // Callbacks
    var onLocationReport: ((Location) -> Void)?
    var onModeChange: ((LocationMode, LocationMode) -> Void)?
    var onSafeZoneEnter: ((SafeZone) -> Void)?
    var onSafeZoneExit: ((SafeZone) -> Void)?
    var onDwellPointDiscovered: ((DwellPoint) -> Void)?

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config
        super.init()
    }

    // MARK: - Start / Stop

    func start() {
        // Set delegate here (not in init) to avoid triggering
        // the location authorization dialog before onboarding completes.
        locationManager.delegate = self

        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            locationManager.requestAlwaysAuthorization()
            return
        }

        // Configure after authorization
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = false

        // Always monitor significant location changes (survives app termination)
        locationManager.startMonitoringSignificantLocationChanges()

        // Start in safe mode
        switchMode(.safe)
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()

        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
    }

    // MARK: - Mode Switching

    func switchMode(_ newMode: LocationMode) {
        let oldMode = currentMode
        guard newMode != oldMode else { return }

        // Stop current tracking
        locationManager.stopUpdatingLocation()

        switch newMode {
        case .safe:
            // Rely on significant location changes + geofence exit events
            // Near-zero battery impact
            locationManager.startMonitoringSignificantLocationChanges()
            locationManager.showsBackgroundLocationIndicator = false

        case .unknown:
            locationManager.desiredAccuracy = newMode.desiredAccuracy
            locationManager.distanceFilter = newMode.distanceFilter
            locationManager.showsBackgroundLocationIndicator = false
            locationManager.startUpdatingLocation()

        case .moving:
            locationManager.desiredAccuracy = newMode.desiredAccuracy
            locationManager.distanceFilter = newMode.distanceFilter
            locationManager.showsBackgroundLocationIndicator = false
            locationManager.startUpdatingLocation()

        case .sos:
            locationManager.desiredAccuracy = newMode.desiredAccuracy
            locationManager.distanceFilter = newMode.distanceFilter
            locationManager.showsBackgroundLocationIndicator = true  // Blue bar — user should see this
            locationManager.startUpdatingLocation()
        }

        currentMode = newMode
        onModeChange?(oldMode, newMode)
    }

    /// Enter SOS mode — maximum accuracy, maximum frequency
    func enterSOSMode() {
        switchMode(.sos)
    }

    /// Exit SOS mode — return to automatic mode selection
    func exitSOSMode() {
        // Re-evaluate based on current position
        if let lastLocation = lastReportedLocation {
            autoSelectMode(for: lastLocation)
        } else {
            switchMode(.unknown)
        }
    }

    // MARK: - Auto Mode Selection

    private func autoSelectMode(for location: CLLocation) {
        // Don't downgrade during SOS
        if currentMode == .sos { return }

        let speed = location.speed
        let inSafeZone = isInAnySafeZone(location: location)

        if inSafeZone && speed < config.stationarySpeedThreshold {
            switchMode(.safe)
        } else if speed > config.movingSpeedThreshold {
            switchMode(.moving)
        } else if !inSafeZone {
            switchMode(.unknown)
        }
    }

    // MARK: - Safe Zone Management

    func updateSafeZones(_ zones: [SafeZone]) {
        self.safeZones = zones
        rebalanceGeofences(currentLocation: lastReportedLocation)
    }

    private func isInAnySafeZone(location: CLLocation) -> Bool {
        safeZones.contains { zone in
            let center = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
            return location.distance(from: center) <= zone.radius
        }
    }

    private func safeZoneContaining(location: CLLocation) -> SafeZone? {
        safeZones.first { zone in
            let center = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
            return location.distance(from: center) <= zone.radius
        }
    }

    // MARK: - iOS 20-Region Geofence Scheduling

    /// Dynamic swap: keep the N closest safe zones monitored,
    /// swap in/out as the user moves.
    func rebalanceGeofences(currentLocation: CLLocation?) {
        guard let current = currentLocation else { return }

        // Sort all safe zones by distance from current location
        let sorted = safeZones.sorted { a, b in
            let distA = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: current)
            let distB = CLLocation(latitude: b.latitude, longitude: b.longitude)
                .distance(from: current)
            return distA < distB
        }

        // Take the closest N zones (reserve 2 slots for system use)
        let toMonitor = Array(sorted.prefix(config.maxGeofenceRegions))
        let targetIds = Set(toMonitor.map { $0.id })

        // Remove regions no longer needed
        for region in locationManager.monitoredRegions {
            if !targetIds.contains(region.identifier) {
                locationManager.stopMonitoring(for: region)
            }
        }

        let currentlyMonitored = Set(locationManager.monitoredRegions.map { $0.identifier })

        // Add new regions
        for zone in toMonitor where !currentlyMonitored.contains(zone.id) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: zone.latitude, longitude: zone.longitude),
                radius: zone.radius,
                identifier: zone.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            locationManager.startMonitoring(for: region)
        }

        monitoredRegionIds = targetIds
    }

    // MARK: - Location Reporting with Deduplication

    private func reportIfNeeded(_ location: CLLocation) {
        let now = Date()

        // In SOS mode, always report
        if currentMode == .sos {
            report(location)
            return
        }

        // Deduplication: skip if too close in space or time
        if let lastLocation = lastReportedLocation,
           let lastTime = lastReportTime {

            let distanceMoved = location.distance(from: lastLocation)
            let timeSinceLastReport = now.timeIntervalSince(lastTime)

            if distanceMoved < config.deduplicationDistanceMeters
                && timeSinceLastReport < config.deduplicationTimeSec {
                return
            }
        }

        // Check if enough time has passed for current mode's interval
        if let lastTime = lastReportTime {
            let interval = now.timeIntervalSince(lastTime)
            if interval < currentMode.reportIntervalSec {
                return
            }
        }

        report(location)
    }

    private func report(_ clLocation: CLLocation) {
        let location = Location(
            latitude: clLocation.coordinate.latitude,
            longitude: clLocation.coordinate.longitude,
            accuracy: clLocation.horizontalAccuracy,
            altitude: clLocation.altitude,
            speed: clLocation.speed >= 0 ? clLocation.speed : nil,
            timestamp: clLocation.timestamp,
            address: nil,
            isInSafeZone: isInAnySafeZone(location: clLocation),
            safeZoneName: safeZoneContaining(location: clLocation)?.name
        )

        lastReportedLocation = clLocation
        lastReportTime = Date()

        onLocationReport?(location)

        // Feed to dwell-point tracker
        trackDwellPoint(clLocation)
    }
}

// MARK: - CLLocationManagerDelegate

extension AdaptiveLocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Store in history
        locationHistory.append(location)
        if locationHistory.count > historyLimit {
            locationHistory.removeFirst(locationHistory.count - historyLimit)
        }

        // Auto mode selection
        autoSelectMode(for: location)

        // Report with deduplication
        reportIfNeeded(location)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        if let zone = safeZones.first(where: { $0.id == circularRegion.identifier }) {
            onSafeZoneEnter?(zone)
            // Entering safe zone — can downgrade to safe mode
            switchMode(.safe)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        if let zone = safeZones.first(where: { $0.id == circularRegion.identifier }) {
            onSafeZoneExit?(zone)
            // Left safe zone — upgrade to unknown or moving
            switchMode(.unknown)
        }

        // Rebalance geofences based on new position
        if let lastLocation = lastReportedLocation {
            rebalanceGeofences(currentLocation: lastLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // In SOS mode, failures are critical — switch to significant changes as fallback
        if currentMode == .sos {
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            start()
        }
    }
}

// MARK: - Dwell-Point Clustering (Auto-discovers safe zones from history)

extension AdaptiveLocationManager {

    struct DwellCandidate {
        var center: CLLocation
        var firstSeen: Date
        var lastSeen: Date
        var pointCount: Int

        var durationSec: TimeInterval {
            lastSeen.timeIntervalSince(firstSeen)
        }
    }

    struct DwellPoint {
        let latitude: Double
        let longitude: Double
        let totalVisits: Int
        let averageDurationMin: Double
        let suggestedName: String?       // "Home", "Work", etc. based on time patterns
        let typicalHours: [Int]          // Hours of day when visits occur
    }

    private func trackDwellPoint(_ location: CLLocation) {
        let now = Date()

        // Check if location matches an existing candidate
        if let idx = dwellCandidates.firstIndex(where: {
            location.distance(from: $0.center) < config.dwellPointRadiusMeters
        }) {
            // Update existing candidate
            dwellCandidates[idx].lastSeen = now
            dwellCandidates[idx].pointCount += 1

            // Check if this candidate qualifies as a dwell point
            if dwellCandidates[idx].durationSec >= config.dwellPointMinDurationSec
                && dwellCandidates[idx].pointCount >= 3 {
                promoteToDwellPoint(dwellCandidates[idx])
            }
        } else {
            // New candidate
            dwellCandidates.append(DwellCandidate(
                center: location,
                firstSeen: now,
                lastSeen: now,
                pointCount: 1
            ))
        }

        // Clean up old candidates (> 1 hour old and never promoted)
        dwellCandidates.removeAll {
            now.timeIntervalSince($0.lastSeen) > 3600 && $0.durationSec < config.dwellPointMinDurationSec
        }
    }

    private func promoteToDwellPoint(_ candidate: DwellCandidate) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: candidate.firstSeen)

        // Suggest a name based on time patterns
        let suggestedName: String?
        switch hour {
        case 22...23, 0...6:
            suggestedName = "住所"       // Home — nighttime dwell
        case 9...17:
            suggestedName = "工作/学校"   // Work/School — business hours
        default:
            suggestedName = nil
        }

        let dwellPoint = DwellPoint(
            latitude: candidate.center.coordinate.latitude,
            longitude: candidate.center.coordinate.longitude,
            totalVisits: candidate.pointCount,
            averageDurationMin: candidate.durationSec / 60.0,
            suggestedName: suggestedName,
            typicalHours: [hour]
        )

        onDwellPointDiscovered?(dwellPoint)
    }

    /// Run full clustering on historical data — called periodically (e.g., daily)
    func clusterDwellPoints() -> [DwellPoint] {
        guard locationHistory.count > 20 else { return [] }

        // Simple density-based clustering
        var clusters: [(center: CLLocation, points: [CLLocation], times: [Date])] = []

        for location in locationHistory {
            var merged = false
            for i in clusters.indices {
                if location.distance(from: clusters[i].center) < config.dwellPointRadiusMeters {
                    clusters[i].points.append(location)
                    clusters[i].times.append(location.timestamp)
                    // Recompute center
                    let avgLat = clusters[i].points.reduce(0) { $0 + $1.coordinate.latitude } / Double(clusters[i].points.count)
                    let avgLng = clusters[i].points.reduce(0) { $0 + $1.coordinate.longitude } / Double(clusters[i].points.count)
                    clusters[i].center = CLLocation(latitude: avgLat, longitude: avgLng)
                    merged = true
                    break
                }
            }

            if !merged {
                clusters.append((center: location, points: [location], times: [location.timestamp]))
            }
        }

        // Filter to significant clusters (≥ 3 visits, ≥ 20 min total dwell)
        let calendar = Calendar.current
        return clusters
            .filter { $0.points.count >= 3 }
            .compactMap { cluster -> DwellPoint? in
                guard let first = cluster.times.min(),
                      let last = cluster.times.max() else { return nil }

                let duration = last.timeIntervalSince(first)
                guard duration >= config.dwellPointMinDurationSec else { return nil }

                let hours = cluster.times.map { calendar.component(.hour, from: $0) }
                let mostCommonHour = hours.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
                    .max(by: { $0.value < $1.value })?.key

                let suggestedName: String?
                if let h = mostCommonHour {
                    switch h {
                    case 22...23, 0...6: suggestedName = "住所"
                    case 9...17: suggestedName = "工作/学校"
                    default: suggestedName = nil
                    }
                } else {
                    suggestedName = nil
                }

                return DwellPoint(
                    latitude: cluster.center.coordinate.latitude,
                    longitude: cluster.center.coordinate.longitude,
                    totalVisits: cluster.points.count,
                    averageDurationMin: duration / 60.0,
                    suggestedName: suggestedName,
                    typicalHours: Array(Set(hours)).sorted()
                )
            }
            .sorted { $0.totalVisits > $1.totalVisits }
    }
}
