import Foundation
import CoreLocation
import UIKit

// MARK: - Adaptive Location Manager
//
// Algorithm from PDF section 6: 位置采集与自适应采样
//
// Five sampling modes that switch automatically based on state:
//   - Safe:       In known safe zone → significant changes only (~0% battery)
//   - Unknown:    Stationary in unknown area → every 10 min
//   - Moving:     In transit → every 60 sec
//   - SOS:        Emergency → every 5 sec, best accuracy
//   - LowBattery: Battery < 15% → halve frequency, reduce accuracy
//
// Also handles:
//   - iOS 20-region geofence limit via dynamic swap scheduling (section 9)
//   - Dwell-point clustering to auto-discover safe zones (section 8)
//   - Deduplication to avoid flooding the server
//   - Hysteresis zone to avoid border flickering

final class AdaptiveLocationManager: NSObject {

    // MARK: - Location Modes

    enum LocationMode: String {
        case safe           // In known safe zone
        case unknown        // Stationary but not in safe zone
        case moving         // In transit
        case sos            // Emergency — max accuracy
        case lowBattery     // Battery < 15% — halve frequency, reduce accuracy

        var desiredAccuracy: CLLocationAccuracy {
            switch self {
            case .safe: return kCLLocationAccuracyHundredMeters
            case .unknown: return kCLLocationAccuracyHundredMeters
            case .moving: return kCLLocationAccuracyNearestTenMeters
            case .sos: return kCLLocationAccuracyBest
            case .lowBattery: return kCLLocationAccuracyHundredMeters
            }
        }

        var distanceFilter: CLLocationDistance {
            switch self {
            case .safe: return kCLDistanceFilterNone
            case .unknown: return 50
            case .moving: return 30
            case .sos: return kCLDistanceFilterNone
            case .lowBattery: return 100
            }
        }

        var reportIntervalSec: TimeInterval {
            switch self {
            case .safe: return .infinity     // Only on significant change
            case .unknown: return 600        // 10 minutes
            case .moving: return 60          // 1 minute
            case .sos: return 5              // 5 seconds
            case .lowBattery: return 1200    // 20 minutes (double unknown)
            }
        }
    }

    // MARK: - Configuration

    struct Config {
        var movingSpeedThreshold: Double = 1.5         // m/s — walking speed
        var stationarySpeedThreshold: Double = 0.5     // m/s
        var deduplicationDistanceMeters: Double = 50    // Don't report if moved < 50m
        var deduplicationTimeSec: TimeInterval = 120    // Don't report more than once per 2 min (except SOS)
        var maxGeofenceRegions: Int = 19                // Reserve 1 of iOS's 20 for buffer zone
        var dwellPointRadiusMeters: Double = 200
        var dwellPointMinDurationSec: TimeInterval = 1200  // 20 minutes
        var safeZoneHysteresisMeters: Double = 50      // Extra buffer to prevent border flickering
        var lowBatteryThreshold: Double = 0.15         // 15%
    }

    // MARK: - Properties

    private lazy var locationManager = CLLocationManager()
    private let config: Config
    private(set) var currentMode: LocationMode = .safe
    private var safeZones: [SafeZone] = []
    private var monitoredRegionIds: Set<String> = []

    // Buffer zone for geofence rebalancing
    private var bufferZoneCenter: CLLocation?
    private let bufferZoneRadius: CLLocationDistance = 2000  // 2km radius

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
            locationManager.startMonitoringSignificantLocationChanges()
            locationManager.showsBackgroundLocationIndicator = false

        case .unknown, .lowBattery:
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
            locationManager.showsBackgroundLocationIndicator = true
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

        // Check low battery first — overrides other modes except SOS
        let batteryLevel = Double(UIDevice.current.batteryLevel)
        if batteryLevel >= 0 && batteryLevel <= config.lowBatteryThreshold
            && UIDevice.current.batteryState != .charging {
            if currentMode != .lowBattery {
                switchMode(.lowBattery)
            }
            return
        }

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

    /// Uses hysteresis: enter at radius, exit at radius + hysteresis buffer
    private func isExitingSafeZone(location: CLLocation) -> Bool {
        !safeZones.contains { zone in
            let center = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
            return location.distance(from: center) <= (zone.radius + config.safeZoneHysteresisMeters)
        }
    }

    private func safeZoneContaining(location: CLLocation) -> SafeZone? {
        safeZones.first { zone in
            let center = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
            return location.distance(from: center) <= zone.radius
        }
    }

    // MARK: - iOS 20-Region Geofence Scheduling (PDF section 9)
    //
    // Algorithm:
    //   1. Sort all safe zones by distance from current position
    //   2. Take closest N (iOS: 19, reserve 1 for buffer zone)
    //   3. Register 1 extra large zone around current position as buffer
    //   4. Only rebalance when leaving the buffer zone

    func rebalanceGeofences(currentLocation: CLLocation?) {
        guard let current = currentLocation else { return }

        // Check if we're still inside the buffer zone — skip rebalancing if so
        if let bufferCenter = bufferZoneCenter,
           current.distance(from: bufferCenter) < bufferZoneRadius * 0.8 {
            return
        }

        // Sort all safe zones by distance from current location
        let sorted = safeZones.sorted { a, b in
            let distA = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: current)
            let distB = CLLocation(latitude: b.latitude, longitude: b.longitude)
                .distance(from: current)
            return distA < distB
        }

        // Take the closest N zones
        let toMonitor = Array(sorted.prefix(config.maxGeofenceRegions))
        let targetIds = Set(toMonitor.map { $0.id })

        // Remove regions no longer needed
        for region in locationManager.monitoredRegions {
            if region.identifier != "buffer_zone" && !targetIds.contains(region.identifier) {
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

        // Register buffer zone around current position
        locationManager.stopMonitoring(for: CLCircularRegion(
            center: current.coordinate,
            radius: bufferZoneRadius,
            identifier: "buffer_zone"
        ))
        let bufferRegion = CLCircularRegion(
            center: current.coordinate,
            radius: bufferZoneRadius,
            identifier: "buffer_zone"
        )
        bufferRegion.notifyOnEntry = false
        bufferRegion.notifyOnExit = true
        locationManager.startMonitoring(for: bufferRegion)
        bufferZoneCenter = current

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
            switchMode(.safe)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        // Buffer zone exit → rebalance geofences
        if circularRegion.identifier == "buffer_zone" {
            if let lastLocation = lastReportedLocation {
                rebalanceGeofences(currentLocation: lastLocation)
            }
            return
        }

        if let zone = safeZones.first(where: { $0.id == circularRegion.identifier }) {
            // Use hysteresis — only fire exit if truly outside the buffer
            if let lastLocation = lastReportedLocation, isExitingSafeZone(location: lastLocation) {
                onSafeZoneExit?(zone)
                switchMode(.unknown)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
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

// MARK: - Dwell-Point Clustering (PDF section 8)
//
// Classification rules:
//   住所:       nighttime (22:00-06:00) highest frequency
//   学校/工作地: weekday daytime highest, distance > 500m from home
//   常去地点:    ≥ 2 visits per week
//   陌生地点:    never seen or ≤ 1 visit

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
        let suggestedName: String?
        let typicalHours: [Int]
        let classification: DwellClassification
    }

    enum DwellClassification: String {
        case home = "住所"
        case workSchool = "学校/工作地"
        case frequent = "常去地点"
        case unfamiliar = "陌生地点"
    }

    private func trackDwellPoint(_ location: CLLocation) {
        let now = Date()

        if let idx = dwellCandidates.firstIndex(where: {
            location.distance(from: $0.center) < config.dwellPointRadiusMeters
        }) {
            dwellCandidates[idx].lastSeen = now
            dwellCandidates[idx].pointCount += 1

            if dwellCandidates[idx].durationSec >= config.dwellPointMinDurationSec
                && dwellCandidates[idx].pointCount >= 3 {
                promoteToDwellPoint(dwellCandidates[idx])
            }
        } else {
            dwellCandidates.append(DwellCandidate(
                center: location,
                firstSeen: now,
                lastSeen: now,
                pointCount: 1
            ))
        }

        dwellCandidates.removeAll {
            now.timeIntervalSince($0.lastSeen) > 3600 && $0.durationSec < config.dwellPointMinDurationSec
        }
    }

    private func promoteToDwellPoint(_ candidate: DwellCandidate) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: candidate.firstSeen)

        let classification = classifyDwellPoint(
            hour: hour,
            location: candidate.center,
            visitCount: candidate.pointCount
        )

        let dwellPoint = DwellPoint(
            latitude: candidate.center.coordinate.latitude,
            longitude: candidate.center.coordinate.longitude,
            totalVisits: candidate.pointCount,
            averageDurationMin: candidate.durationSec / 60.0,
            suggestedName: classification.rawValue,
            typicalHours: [hour],
            classification: classification
        )

        onDwellPointDiscovered?(dwellPoint)
    }

    private func classifyDwellPoint(
        hour: Int,
        location: CLLocation,
        visitCount: Int
    ) -> DwellClassification {
        // Nighttime dwell → home
        if hour >= 22 || hour <= 6 {
            return .home
        }

        // Check distance from home zones
        let homeSafeZones = safeZones.filter { $0.name == "住所" }
        let isFarFromHome = homeSafeZones.allSatisfy { zone in
            let center = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
            return location.distance(from: center) > 500
        }

        // Weekday business hours + far from home → work/school
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let isWeekday = weekday >= 2 && weekday <= 6
        if isWeekday && hour >= 9 && hour <= 17 && isFarFromHome {
            return .workSchool
        }

        // Frequent visitor
        if visitCount >= 2 {
            return .frequent
        }

        return .unfamiliar
    }

    /// Run full clustering on historical data — called periodically (e.g., daily)
    func clusterDwellPoints() -> [DwellPoint] {
        guard locationHistory.count > 20 else { return [] }

        var clusters: [(center: CLLocation, points: [CLLocation], times: [Date])] = []

        for location in locationHistory {
            var merged = false
            for i in clusters.indices {
                if location.distance(from: clusters[i].center) < config.dwellPointRadiusMeters {
                    clusters[i].points.append(location)
                    clusters[i].times.append(location.timestamp)
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
                    .max(by: { $0.value < $1.value })?.key ?? 12

                let classification = classifyDwellPoint(
                    hour: mostCommonHour,
                    location: cluster.center,
                    visitCount: cluster.points.count
                )

                return DwellPoint(
                    latitude: cluster.center.coordinate.latitude,
                    longitude: cluster.center.coordinate.longitude,
                    totalVisits: cluster.points.count,
                    averageDurationMin: duration / 60.0,
                    suggestedName: classification.rawValue,
                    typicalHours: Array(Set(hours)).sorted(),
                    classification: classification
                )
            }
            .sorted { $0.totalVisits > $1.totalVisits }
    }
}
