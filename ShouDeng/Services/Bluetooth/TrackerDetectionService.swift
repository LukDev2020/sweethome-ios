import CoreBluetooth
import CoreLocation
import Foundation

// MARK: - TrackerDetectionService
//
// Anti-stalker Bluetooth tracker detection service.
//
// Scans ALL BLE advertisements (not just known UUIDs) and builds a threat model
// for each peripheral. A threat score (0–100) is computed from:
//   - Number of distinct locations where the device was sighted (>100m apart)
//   - Time-window spread (sightings across 3+ windows >30 min apart)
//   - Following pattern (appears at >50% of the user's location changes)
//   - Known tracker manufacturer (AirTag, SmartTag, Tile)
//   - Persistent close proximity (RSSI < -60 dBm consistently)
//
// Alert thresholds:
//   score >= 40  →  .warning
//   score >= 70  →  .critical
//
// Uses CBCentralManager restoration key "com.shoudeng.tracker-detection",
// distinct from BLETrackerService ("com.shoudeng.ble-tracker").
//
// Sighting history is persisted to UserDefaults (max 500 entries, max 7 days).
// Ignored (whitelisted) peripheral IDs are also persisted to UserDefaults.

// MARK: - Supporting Types

/// A single observation of an unknown BLE peripheral.
struct TrackerSighting: Codable, Equatable {
    let peripheralId: UUID
    let rssi: Int
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(peripheralId: UUID, rssi: Int, location: CLLocationCoordinate2D, timestamp: Date) {
        self.peripheralId = peripheralId
        self.rssi = rssi
        self.latitude = location.latitude
        self.longitude = location.longitude
        self.timestamp = timestamp
    }
}

/// The inferred hardware type of a detected tracker.
enum TrackerType: String, Codable {
    case airTag       = "AirTag"
    case smartTag     = "SmartTag"
    case tile         = "Tile"
    case beacon       = "Beacon"
    case unknown      = "Unknown"
}

/// Alert severity level derived from threat score.
enum ThreatLevel: String, Codable {
    case low
    case warning
    case critical
}

/// A persistent model for a single unknown device that has been observed over time.
struct DetectedTracker: Codable, Identifiable, Equatable {
    let peripheralId: UUID

    var id: UUID { peripheralId }

    var firstSeen: Date
    var lastSeen: Date
    var sightings: [TrackerSighting]
    var name: String?            // from CBAdvertisementDataLocalNameKey
    var type: TrackerType
    var threatScore: Int         // 0–100

    var threatLevel: ThreatLevel {
        switch threatScore {
        case 70...: return .critical
        case 40...: return .warning
        default:    return .low
        }
    }

    static func == (lhs: DetectedTracker, rhs: DetectedTracker) -> Bool {
        lhs.peripheralId == rhs.peripheralId
    }
}

/// An active alert surfaced to the UI.
struct TrackerAlert: Identifiable, Equatable {
    let id: UUID
    let tracker: DetectedTracker
    let level: ThreatLevel
    let triggeredAt: Date

    init(tracker: DetectedTracker) {
        self.id = UUID()
        self.tracker = tracker
        self.level = tracker.threatLevel
        self.triggeredAt = Date()
    }
}

// MARK: - TrackerDetectionService

final class TrackerDetectionService: NSObject, ObservableObject {

    static let shared = TrackerDetectionService()

    // MARK: - Published State

    @Published private(set) var detectedTrackers: [DetectedTracker] = []
    @Published private(set) var alerts: [TrackerAlert] = []
    @Published private(set) var isScanning = false

    // MARK: - Constants

    private enum Keys {
        static let sightingHistory  = "tds_sighting_history_v1"
        static let ignoredTrackers  = "tds_ignored_trackers_v1"
        static let restorationKey   = "com.shoudeng.tracker-detection"
        static let scanInterval: TimeInterval   = 30
        static let retentionWindow: TimeInterval = 7 * 24 * 3600   // 7 days
        static let maxSightings = 500
        // Distance (metres) at which two sightings count as "distinct locations"
        static let distinctLocationThreshold: CLLocationDistance = 100
        // Time gap (seconds) that separates two "time windows"
        static let distinctTimeWindowGap: TimeInterval = 30 * 60    // 30 minutes
        // RSSI threshold for "consistently close" (-60 dBm or stronger)
        static let closeProximityRSSI = -60
        // Minimum fraction of user location changes at which tracker must also appear
        static let followingFraction: Double = 0.5
    }

    // Manufacturer-specific data company identifiers (little-endian UInt16)
    private enum ManufacturerId: UInt16 {
        case apple   = 0x004C
        case samsung = 0x0075
    }

    // MARK: - Private State

    private var centralManager: CBCentralManager?
    private var locationManager: CLLocationManager?

    /// Raw sighting log — persisted, pruned on every scan cycle.
    private var allSightings: [TrackerSighting] = [] {
        didSet { persistSightings() }
    }

    /// Peripheral IDs the user has chosen to ignore.
    private(set) var ignoredTrackers: Set<UUID> = [] {
        didSet { persistIgnoredTrackers() }
    }

    /// User's recent location history, used for "following" pattern detection.
    private var userLocationHistory: [CLLocation] = []

    private var scanTimer: Timer?

    // MARK: - Init

    private override init() {
        super.init()
        loadIgnoredTrackers()
        loadSightings()
    }

    // MARK: - Public API

    /// Start the detection service. Safe to call multiple times.
    func start() {
        #if !targetEnvironment(simulator)
        if centralManager == nil {
            centralManager = CBCentralManager(
                delegate: self,
                queue: .global(qos: .utility),
                options: [CBCentralManagerOptionRestoreIdentifierKey: Keys.restorationKey]
            )
        }
        if locationManager == nil {
            locationManager = CLLocationManager()
            locationManager?.delegate = self
            locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager?.distanceFilter = 50
            locationManager?.allowsBackgroundLocationUpdates = true
            locationManager?.pausesLocationUpdatesAutomatically = false
        }
        locationManager?.startUpdatingLocation()
        #endif
    }

    /// Stop all scanning and the repeating timer.
    func stop() {
        cancelScanTimer()
        centralManager?.stopScan()
        locationManager?.stopUpdatingLocation()
        DispatchQueue.main.async { self.isScanning = false }
    }

    /// Permanently ignore a tracker — removes it from detectedTrackers and alerts,
    /// and suppresses future alerts for this peripheral.
    func ignoreTracker(peripheralId: UUID) {
        ignoredTrackers.insert(peripheralId)
        DispatchQueue.main.async {
            self.detectedTrackers.removeAll { $0.peripheralId == peripheralId }
            self.alerts.removeAll { $0.tracker.peripheralId == peripheralId }
        }
    }

    /// Remove a peripheral from the ignore list so it can be re-evaluated.
    func unignoreTracker(peripheralId: UUID) {
        ignoredTrackers.remove(peripheralId)
    }

    // MARK: - Scanning

    private func scheduleScanCycle() {
        cancelScanTimer()
        // Fire immediately, then every scanInterval seconds.
        performScanCycle()
        scanTimer = Timer.scheduledTimer(
            withTimeInterval: Keys.scanInterval,
            repeats: true
        ) { [weak self] _ in
            self?.performScanCycle()
        }
    }

    private func cancelScanTimer() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    private func performScanCycle() {
        guard let central = centralManager, central.state == .poweredOn else { return }

        // Stop any ongoing scan, prune old data, then restart.
        central.stopScan()
        pruneOldSightings()

        // Scan ALL BLE advertisements with duplicates allowed (we want RSSI updates).
        // Note: CBCentralManagerScanOptionAllowDuplicatesKey is ignored in background.
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])

        DispatchQueue.main.async { self.isScanning = true }

        // Stop after 25 seconds (5 s buffer before next 30-s cycle).
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self else { return }
            self.centralManager?.stopScan()
            DispatchQueue.main.async { self.isScanning = false }
            // Recompute threat scores across all known trackers.
            self.recomputeAllThreatScores()
        }
    }

    // MARK: - Sighting Recording

    private func recordSighting(
        peripheralId: UUID,
        rssi: Int,
        advertisementData: [String: Any]
    ) {
        guard !ignoredTrackers.contains(peripheralId) else { return }
        guard let location = locationManager?.location?.coordinate else { return }

        let sighting = TrackerSighting(
            peripheralId: peripheralId,
            rssi: rssi,
            location: location,
            timestamp: Date()
        )

        allSightings.append(sighting)

        // Cap total stored entries.
        if allSightings.count > Keys.maxSightings {
            allSightings.removeFirst(allSightings.count - Keys.maxSightings)
        }

        // Eagerly update or insert the DetectedTracker model on main thread.
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let type = inferTrackerType(advertisementData: advertisementData)

        DispatchQueue.main.async { [weak self] in
            self?.updateDetectedTracker(
                peripheralId: peripheralId,
                newSighting: sighting,
                name: name,
                type: type
            )
        }
    }

    private func updateDetectedTracker(
        peripheralId: UUID,
        newSighting: TrackerSighting,
        name: String?,
        type: TrackerType
    ) {
        if let idx = detectedTrackers.firstIndex(where: { $0.peripheralId == peripheralId }) {
            detectedTrackers[idx].sightings.append(newSighting)
            detectedTrackers[idx].lastSeen = newSighting.timestamp
            if let name { detectedTrackers[idx].name = name }
            // Upgrade type if we now have a better match.
            if type != .unknown { detectedTrackers[idx].type = type }
            recomputeThreatScore(for: &detectedTrackers[idx])
            evaluateAlerts(for: detectedTrackers[idx])
        } else {
            var tracker = DetectedTracker(
                peripheralId: peripheralId,
                firstSeen: newSighting.timestamp,
                lastSeen: newSighting.timestamp,
                sightings: [newSighting],
                name: name,
                type: type,
                threatScore: 0
            )
            recomputeThreatScore(for: &tracker)
            detectedTrackers.append(tracker)
            evaluateAlerts(for: tracker)
        }
    }

    // MARK: - Threat Scoring

    private func recomputeAllThreatScores() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for idx in self.detectedTrackers.indices {
                // Refresh sightings from persisted log.
                self.detectedTrackers[idx].sightings = self.allSightings.filter {
                    $0.peripheralId == self.detectedTrackers[idx].peripheralId
                }
                self.recomputeThreatScore(for: &self.detectedTrackers[idx])
                self.evaluateAlerts(for: self.detectedTrackers[idx])
            }
        }
    }

    /// Mutates `tracker.threatScore` in-place according to the scoring algorithm.
    private func recomputeThreatScore(for tracker: inout DetectedTracker) {
        let sightings = tracker.sightings
        guard !sightings.isEmpty else {
            tracker.threatScore = 0
            return
        }

        var score = 0

        // 1. +10 per distinct location (> 100m apart)
        let distinctLocations = countDistinctLocations(sightings)
        score += min(distinctLocations, 5) * 10   // cap contribution at 50

        // 2. +15 if seen across 3+ distinct time windows (>30 min apart)
        let timeWindows = countDistinctTimeWindows(sightings)
        if timeWindows >= 3 {
            score += 15
        }

        // 3. +20 if following movement pattern
        if isFollowingUser(sightings: sightings) {
            score += 20
        }

        // 4. +25 if known tracker type
        if tracker.type != .unknown && tracker.type != .beacon {
            score += 25
        } else if tracker.type == .beacon {
            score += 10
        }

        // 5. +10 if RSSI is consistently strong (< -60 dBm, i.e., physically close)
        if isConsistentlyClose(sightings: sightings) {
            score += 10
        }

        tracker.threatScore = min(score, 100)
    }

    /// Counts how many sightings are > 100m from all previously counted ones.
    private func countDistinctLocations(_ sightings: [TrackerSighting]) -> Int {
        var anchors: [CLLocation] = []
        for sighting in sightings {
            let loc = CLLocation(latitude: sighting.latitude, longitude: sighting.longitude)
            let isDistinct = anchors.allSatisfy {
                $0.distance(from: loc) > Keys.distinctLocationThreshold
            }
            if isDistinct {
                anchors.append(loc)
            }
        }
        return anchors.count
    }

    /// Counts time windows separated by > 30 minutes.
    private func countDistinctTimeWindows(_ sightings: [TrackerSighting]) -> Int {
        let sorted = sightings.sorted { $0.timestamp < $1.timestamp }
        var windowCount = sorted.isEmpty ? 0 : 1
        var windowStart = sorted.first!.timestamp
        for sighting in sorted.dropFirst() {
            if sighting.timestamp.timeIntervalSince(windowStart) > Keys.distinctTimeWindowGap {
                windowCount += 1
                windowStart = sighting.timestamp
            }
        }
        return windowCount
    }

    /// Returns true if the tracker appears at > 50% of the user's location changes.
    private func isFollowingUser(sightings: [TrackerSighting]) -> Bool {
        guard userLocationHistory.count >= 4 else { return false }

        var matchCount = 0
        for userLoc in userLocationHistory {
            let userTimestamp = userLoc.timestamp
            // Check if there is a tracker sighting within ±5 minutes of this user location.
            let nearInTime = sightings.contains {
                abs($0.timestamp.timeIntervalSince(userTimestamp)) < 5 * 60
            }
            if nearInTime { matchCount += 1 }
        }

        let fraction = Double(matchCount) / Double(userLocationHistory.count)
        return fraction >= Keys.followingFraction
    }

    /// Returns true if the majority of RSSI readings are stronger than the threshold.
    private func isConsistentlyClose(sightings: [TrackerSighting]) -> Bool {
        guard sightings.count >= 3 else { return false }
        let closeCount = sightings.filter { $0.rssi > Keys.closeProximityRSSI }.count
        return Double(closeCount) / Double(sightings.count) >= 0.6
    }

    // MARK: - Alert Evaluation

    private func evaluateAlerts(for tracker: DetectedTracker) {
        guard !ignoredTrackers.contains(tracker.peripheralId) else { return }
        guard tracker.threatLevel != .low else { return }

        // Only raise a new alert if we don't already have a current one for this tracker
        // at the same or higher severity.
        let existing = alerts.first(where: { $0.tracker.peripheralId == tracker.peripheralId })
        if let existing {
            // Upgrade to critical if needed.
            if tracker.threatLevel == .critical && existing.level != .critical {
                alerts.removeAll { $0.tracker.peripheralId == tracker.peripheralId }
                alerts.append(TrackerAlert(tracker: tracker))
            } else {
                // Refresh tracker snapshot in existing alert (score may have changed).
                if let idx = alerts.firstIndex(where: { $0.tracker.peripheralId == tracker.peripheralId }) {
                    alerts[idx] = TrackerAlert(tracker: tracker)
                }
            }
        } else {
            alerts.append(TrackerAlert(tracker: tracker))
        }
    }

    // MARK: - Tracker Type Identification

    private func inferTrackerType(advertisementData: [String: Any]) -> TrackerType {
        guard let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              mfgData.count >= 2 else {
            // Check for iBeacon pattern in service UUIDs
            if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                let iBeaconServiceUUID = CBUUID(string: "FE9A") // Apple iBeacon
                if serviceUUIDs.contains(iBeaconServiceUUID) {
                    return .beacon
                }
            }
            return .unknown
        }

        // Company identifier is the first two bytes, little-endian.
        let companyId = UInt16(mfgData[0]) | (UInt16(mfgData[1]) << 8)

        switch companyId {
        case ManufacturerId.apple.rawValue:
            return inferAppleDeviceType(mfgData: mfgData)
        case ManufacturerId.samsung.rawValue:
            return .smartTag
        default:
            return inferTileOrBeacon(advertisementData: advertisementData, mfgData: mfgData)
        }
    }

    /// Distinguish AirTag from other Apple devices by manufacturer payload patterns.
    ///
    /// AirTag payload (post-company-id bytes):
    ///   Byte 2 = 0x12 (type), Byte 3 = 0x19 (length byte for nearby action)
    /// This heuristic matches Apple's FindMy "Nearby Interaction" advertisement format.
    private func inferAppleDeviceType(mfgData: Data) -> TrackerType {
        guard mfgData.count >= 4 else { return .unknown }
        let type = mfgData[2]
        let length = mfgData[3]
        // AirTag uses type 0x12 (Nearby Action) with length 0x19 (25 bytes payload)
        if type == 0x12 && length == 0x19 {
            return .airTag
        }
        // FindMy network participant (lost mode) uses type 0x12 with other lengths
        if type == 0x12 {
            return .airTag
        }
        // iBeacon pattern in Apple data
        if type == 0x02 && length == 0x15 {
            return .beacon
        }
        return .unknown
    }

    /// Tile devices advertise a proprietary service UUID: 0xFEED.
    private func inferTileOrBeacon(
        advertisementData: [String: Any],
        mfgData: Data
    ) -> TrackerType {
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            let tileServiceUUID = CBUUID(string: "FEED")
            if serviceUUIDs.contains(tileServiceUUID) {
                return .tile
            }
            // Generic iBeacon FE9A service
            let iBeaconServiceUUID = CBUUID(string: "FE9A")
            if serviceUUIDs.contains(iBeaconServiceUUID) {
                return .beacon
            }
        }
        return .unknown
    }

    // MARK: - Persistence: Sightings

    private func persistSightings() {
        guard let data = try? JSONEncoder().encode(allSightings) else { return }
        UserDefaults.standard.set(data, forKey: Keys.sightingHistory)
    }

    private func loadSightings() {
        guard
            let data = UserDefaults.standard.data(forKey: Keys.sightingHistory),
            let decoded = try? JSONDecoder().decode([TrackerSighting].self, from: data)
        else { return }
        allSightings = decoded
    }

    private func pruneOldSightings() {
        let cutoff = Date().addingTimeInterval(-Keys.retentionWindow)
        let before = allSightings.count
        allSightings.removeAll { $0.timestamp < cutoff }
        // Also prune detectedTrackers that no longer have any sightings.
        let activeIds = Set(allSightings.map { $0.peripheralId })
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.detectedTrackers.removeAll {
                !activeIds.contains($0.peripheralId) && !self.ignoredTrackers.contains($0.peripheralId)
            }
        }
        #if DEBUG
        let removed = before - allSightings.count
        if removed > 0 {
            print("[TrackerDetection] Pruned \(removed) sightings older than 7 days")
        }
        #endif
    }

    // MARK: - Persistence: Ignored Trackers

    private func persistIgnoredTrackers() {
        let strings = ignoredTrackers.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: Keys.ignoredTrackers)
    }

    private func loadIgnoredTrackers() {
        guard let strings = UserDefaults.standard.stringArray(forKey: Keys.ignoredTrackers) else { return }
        ignoredTrackers = Set(strings.compactMap { UUID(uuidString: $0) })
    }
}

// MARK: - CBCentralManagerDelegate

extension TrackerDetectionService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            scheduleScanCycle()
        case .poweredOff, .resetting, .unauthorized, .unsupported, .unknown:
            DispatchQueue.main.async { self.isScanning = false }
            cancelScanTimer()
        @unknown default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        // State restoration — resume detection without user interaction.
        // The scanning cycle will be started when centralManagerDidUpdateState fires.
        #if DEBUG
        print("[TrackerDetection] State restored from background")
        #endif
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let peripheralId = peripheral.identifier
        guard !ignoredTrackers.contains(peripheralId) else { return }

        // Skip devices with no discernible data (RSSI of 127 means unreadable).
        let rssiValue = RSSI.intValue
        guard rssiValue != 127 else { return }

        recordSighting(
            peripheralId: peripheralId,
            rssi: rssiValue,
            advertisementData: advertisementData
        )
    }
}

// MARK: - CLLocationManagerDelegate

extension TrackerDetectionService: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            userLocationHistory.append(location)
        }
        // Keep the last 50 user location records for following-pattern analysis.
        if userLocationHistory.count > 50 {
            userLocationHistory.removeFirst(userLocationHistory.count - 50)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}
