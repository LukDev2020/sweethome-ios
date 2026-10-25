import Foundation
import CoreBluetooth
import CoreLocation
import Combine

// MARK: - BLE Tracker Service
//
// Three-layer Bluetooth tracker integration:
//
// Layer 1 — Panic Button: Scan for BLE devices with known service UUID.
//   When button press characteristic changes → trigger SOS(.bluetoothButton).
//
// Layer 2 — Beacon Proximity: Register iBeacon region (UUID/Major/Minor).
//   didExitRegion → "tag out of range" alert to guardian.
//   didEnterRegion → "reunited" timeline entry.
//   Works even when app is terminated (iOS wakes app for region events).
//
// Layer 3 — Last-Seen Tracker: Log every BLE sighting with location + timestamp.
//   Guardian sees "last seen at X, Y minutes ago" on map.

final class BLETrackerService: NSObject, ObservableObject {

    static let shared = BLETrackerService()

    // MARK: - Published State

    @Published var pairedTags: [TrackerTag] = {
        if let data = UserDefaults.standard.data(forKey: "ble_paired_tags"),
           let tags = try? JSONDecoder().decode([TrackerTag].self, from: data) {
            return tags
        }
        return []
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(pairedTags) {
                UserDefaults.standard.set(data, forKey: "ble_paired_tags")
            }
        }
    }

    @Published var isScanning = false
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var connectedTagId: String?
    @Published var lastSeenLocations: [String: TagSighting] = [:]  // tagId → sighting

    // MARK: - Types

    struct TrackerTag: Codable, Identifiable, Equatable {
        let id: String          // UUID or MAC-derived identifier
        var name: String        // User-given name ("妈妈的手环", "书包")
        var type: TagType
        var serviceUUID: String // BLE service UUID to scan for
        var beaconUUID: String? // iBeacon UUID for proximity monitoring
        var beaconMajor: Int?
        var beaconMinor: Int?
        var pairedAt: Date
        var isActive: Bool

        enum TagType: String, Codable {
            case panicButton     // Has SOS button — triggers SOS on press
            case beacon          // Passive proximity tag — alerts on separation
            case dual            // Both button + proximity
        }
    }

    struct DiscoveredDevice: Identifiable {
        let id: String           // peripheral identifier
        let name: String?
        let rssi: Int
        let serviceUUIDs: [String]
        var peripheral: CBPeripheral?
    }

    struct TagSighting: Codable {
        let tagId: String
        let latitude: Double
        let longitude: Double
        let timestamp: Date
        let rssi: Int
    }

    // MARK: - Well-Known UUIDs

    // Standard BLE panic button services (configurable per device)
    static let defaultPanicServiceUUID = "FFF0"
    static let panicButtonCharacteristicUUID = "FFF1"
    // iBeacon default (Blue Charm BC011 / KKM B2 compatible)
    static let defaultBeaconUUID = "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0"

    // MARK: - Private

    private var centralManager: CBCentralManager?
    private var locationManager: CLLocationManager?
    private var connectedPeripherals: [String: CBPeripheral] = [:]
    private var apiClient: APIClient?
    private var onSOSTrigger: (() -> Void)?
    private var onSeparationAlert: ((TrackerTag) -> Void)?
    private var onReunion: ((TrackerTag) -> Void)?
    private var sightingBuffer: [TagSighting] = []

    private override init() {
        super.init()
    }

    // MARK: - Configuration

    func configure(
        apiClient: APIClient,
        onSOSTrigger: @escaping () -> Void,
        onSeparationAlert: @escaping (TrackerTag) -> Void,
        onReunion: @escaping (TrackerTag) -> Void
    ) {
        self.apiClient = apiClient
        self.onSOSTrigger = onSOSTrigger
        self.onSeparationAlert = onSeparationAlert
        self.onReunion = onReunion

        #if !targetEnvironment(simulator)
        centralManager = CBCentralManager(delegate: self, queue: .global(qos: .utility), options: [
            CBCentralManagerOptionRestoreIdentifierKey: "com.shoudeng.ble-tracker"
        ])

        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.allowsBackgroundLocationUpdates = true

        // Start monitoring for already-paired beacon tags
        for tag in pairedTags where tag.isActive {
            if let beaconUUID = tag.beaconUUID {
                startBeaconMonitoring(uuid: beaconUUID, major: tag.beaconMajor, minor: tag.beaconMinor, tagId: tag.id)
            }
        }
        #endif
    }

    // MARK: - Scanning for New Devices

    func startDiscovery() {
        guard let central = centralManager, central.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        isScanning = true

        // Scan for all BLE devices (or filter by known service UUIDs)
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Auto-stop after 15 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.stopDiscovery()
        }
    }

    func stopDiscovery() {
        centralManager?.stopScan()
        isScanning = false
    }

    // MARK: - Pair / Unpair

    func pairTag(_ device: DiscoveredDevice, name: String, type: TrackerTag.TagType, beaconUUID: String? = nil, beaconMajor: Int? = nil, beaconMinor: Int? = nil) {
        let tag = TrackerTag(
            id: device.id,
            name: name,
            type: type,
            serviceUUID: device.serviceUUIDs.first ?? Self.defaultPanicServiceUUID,
            beaconUUID: beaconUUID,
            beaconMajor: beaconMajor,
            beaconMinor: beaconMinor,
            pairedAt: Date(),
            isActive: true
        )
        pairedTags.append(tag)

        // Connect if it's a panic button type
        if type == .panicButton || type == .dual, let peripheral = device.peripheral {
            centralManager?.connect(peripheral, options: nil)
        }

        // Start beacon monitoring if configured
        if let uuid = beaconUUID {
            startBeaconMonitoring(uuid: uuid, major: beaconMajor, minor: beaconMinor, tagId: tag.id)
        }

        // Sync to server
        Task { await syncTagToServer(tag, action: "paired") }
    }

    func unpairTag(_ tagId: String) {
        guard let tag = pairedTags.first(where: { $0.id == tagId }) else { return }

        // Stop beacon monitoring
        if let uuid = tag.beaconUUID {
            stopBeaconMonitoring(uuid: uuid, major: tag.beaconMajor, minor: tag.beaconMinor)
        }

        // Disconnect peripheral
        if let peripheral = connectedPeripherals[tagId] {
            centralManager?.cancelPeripheralConnection(peripheral)
            connectedPeripherals.removeValue(forKey: tagId)
        }

        pairedTags.removeAll { $0.id == tagId }

        Task { await syncTagToServer(tag, action: "unpaired") }
    }

    // MARK: - Background Scanning for Paired Panic Buttons

    func startBackgroundScanning() {
        guard let central = centralManager, central.state == .poweredOn else { return }

        let serviceUUIDs = pairedTags
            .filter { ($0.type == .panicButton || $0.type == .dual) && $0.isActive }
            .compactMap { CBUUID(string: $0.serviceUUID) }

        guard !serviceUUIDs.isEmpty else { return }

        // Background scanning requires specific service UUIDs
        central.scanForPeripherals(withServices: serviceUUIDs, options: nil)
    }

    // MARK: - iBeacon Region Monitoring

    private func startBeaconMonitoring(uuid: String, major: Int?, minor: Int?, tagId: String) {
        guard let beaconUUID = UUID(uuidString: uuid) else { return }

        let constraint: CLBeaconIdentityConstraint
        if let major = major, let minor = minor {
            constraint = CLBeaconIdentityConstraint(uuid: beaconUUID, major: UInt16(major), minor: UInt16(minor))
        } else if let major = major {
            constraint = CLBeaconIdentityConstraint(uuid: beaconUUID, major: UInt16(major))
        } else {
            constraint = CLBeaconIdentityConstraint(uuid: beaconUUID)
        }

        let region = CLBeaconRegion(beaconIdentityConstraint: constraint, identifier: "shoudeng-tag-\(tagId)")
        region.notifyOnEntry = true
        region.notifyOnExit = true
        region.notifyEntryStateOnDisplay = true

        locationManager?.startMonitoring(for: region)
    }

    private func stopBeaconMonitoring(uuid: String, major: Int?, minor: Int?) {
        guard let regions = locationManager?.monitoredRegions else { return }
        for region in regions {
            if let beaconRegion = region as? CLBeaconRegion,
               beaconRegion.identifier.hasPrefix("shoudeng-tag-") {
                if beaconRegion.beaconIdentityConstraint.uuid.uuidString == uuid {
                    locationManager?.stopMonitoring(for: beaconRegion)
                }
            }
        }
    }

    // MARK: - Last-Seen Sighting

    private func recordSighting(tagId: String, rssi: Int) {
        // Use the app's current location
        guard let location = locationManager?.location else { return }

        let sighting = TagSighting(
            tagId: tagId,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: Date(),
            rssi: rssi
        )

        lastSeenLocations[tagId] = sighting
        sightingBuffer.append(sighting)

        // Flush buffer when it reaches 10 entries
        if sightingBuffer.count >= 10 {
            let batch = sightingBuffer
            sightingBuffer.removeAll()
            Task { await uploadSightings(batch) }
        }
    }

    // MARK: - Server Sync

    private func syncTagToServer(_ tag: TrackerTag, action: String) async {
        guard let apiClient else { return }
        struct TagSyncRequest: Codable {
            let tagId: String
            let name: String
            let type: String
            let action: String
        }
        do {
            let _: SuccessResponse = try await apiClient.post(
                "/v1/device/ble-tag",
                body: TagSyncRequest(tagId: tag.id, name: tag.name, type: tag.type.rawValue, action: action)
            )
        } catch {
            #if DEBUG
            print("[BLETracker] sync error: \(error)")
            #endif
        }
    }

    private func uploadSightings(_ sightings: [TagSighting]) async {
        guard let apiClient else { return }
        struct SightingBatch: Codable {
            let sightings: [TagSighting]
        }
        do {
            let _: SuccessResponse = try await apiClient.post(
                "/v1/device/ble-sightings",
                body: SightingBatch(sightings: sightings)
            )
        } catch {
            #if DEBUG
            print("[BLETracker] sighting upload error: \(error)")
            #endif
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLETrackerService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startBackgroundScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // State restoration for background — reconnect to known peripherals
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                let id = peripheral.identifier.uuidString
                if pairedTags.contains(where: { $0.id == id }) {
                    connectedPeripherals[id] = peripheral
                    peripheral.delegate = self
                }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier.uuidString
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString } ?? []

        // Check if this is a paired panic button
        if let tag = pairedTags.first(where: { $0.id == id }), tag.isActive {
            recordSighting(tagId: id, rssi: RSSI.intValue)

            // If not connected, reconnect
            if connectedPeripherals[id] == nil && (tag.type == .panicButton || tag.type == .dual) {
                peripheral.delegate = self
                central.connect(peripheral, options: nil)
            }
            return
        }

        // Discovery mode — add to discovered list
        if isScanning {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.discoveredDevices.contains(where: { $0.id == id }) {
                    self.discoveredDevices.append(DiscoveredDevice(
                        id: id,
                        name: name,
                        rssi: RSSI.intValue,
                        serviceUUIDs: serviceUUIDs,
                        peripheral: peripheral
                    ))
                }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier.uuidString
        connectedPeripherals[id] = peripheral
        peripheral.delegate = self

        DispatchQueue.main.async { [weak self] in
            self?.connectedTagId = id
        }

        // Discover services to find the button characteristic
        if let tag = pairedTags.first(where: { $0.id == id }) {
            peripheral.discoverServices([CBUUID(string: tag.serviceUUID)])
        }

        #if DEBUG
        print("[BLETracker] Connected to \(peripheral.name ?? id)")
        #endif
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier.uuidString
        connectedPeripherals.removeValue(forKey: id)

        // Auto-reconnect for paired tags
        if pairedTags.contains(where: { $0.id == id && $0.isActive }) {
            central.connect(peripheral, options: nil)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLETrackerService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(
                [CBUUID(string: Self.panicButtonCharacteristicUUID)],
                for: service
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            // Subscribe to button press notifications
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
                #if DEBUG
                print("[BLETracker] Subscribed to button notifications on \(characteristic.uuid)")
                #endif
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }

        // Button press detected!
        let id = peripheral.identifier.uuidString
        guard let tag = pairedTags.first(where: { $0.id == id }) else { return }

        #if DEBUG
        print("[BLETracker] BUTTON PRESS from \(tag.name) (\(id))")
        #endif

        // Record sighting at press time
        recordSighting(tagId: id, rssi: 0)

        // Trigger SOS on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onSOSTrigger?()
        }
    }
}

// MARK: - CLLocationManagerDelegate (iBeacon Region Monitoring)

extension BLETrackerService: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let beaconRegion = region as? CLBeaconRegion,
              beaconRegion.identifier.hasPrefix("shoudeng-tag-") else { return }

        let tagId = String(beaconRegion.identifier.dropFirst("shoudeng-tag-".count))
        guard let tag = pairedTags.first(where: { $0.id == tagId }) else { return }

        #if DEBUG
        print("[BLETracker] Tag entered range: \(tag.name)")
        #endif

        DispatchQueue.main.async { [weak self] in
            self?.onReunion?(tag)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let beaconRegion = region as? CLBeaconRegion,
              beaconRegion.identifier.hasPrefix("shoudeng-tag-") else { return }

        let tagId = String(beaconRegion.identifier.dropFirst("shoudeng-tag-".count))
        guard let tag = pairedTags.first(where: { $0.id == tagId }) else { return }

        #if DEBUG
        print("[BLETracker] Tag left range: \(tag.name) — SEPARATION ALERT")
        #endif

        DispatchQueue.main.async { [weak self] in
            self?.onSeparationAlert?(tag)
        }
    }
}
