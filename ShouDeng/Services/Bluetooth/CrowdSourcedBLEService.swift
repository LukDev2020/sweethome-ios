import UIKit
import CoreBluetooth
import CoreLocation
import CryptoKit

// MARK: - Crowd-Sourced BLE Sighting Network
//
// Extends our existing BLE sighting infrastructure to participate in a
// crowd-sourced tracker network. Any ShouDeng user's phone can detect and
// report sightings of other users' paired BLE tags — enabling tracking
// even when the tag is out of range of the owner's phone.
//
// Architecture inspired by OpenHaystack / Apple Find My network:
// 1. Each paired tag broadcasts a rotating public key (or fixed UUID for iBeacons)
// 2. Any ShouDeng phone that sees the broadcast records: tag UUID + encrypted location + timestamp
// 3. Sightings are uploaded to /v1/device/ble-sightings
// 4. Tag owner can query their tag's last sighting from the server
//
// Privacy: location is encrypted with the tag owner's public key before upload.
// Sighting reporters never know whose tag they saw or where they are.

final class CrowdSourcedBLEService: NSObject, ObservableObject {
    static let shared = CrowdSourcedBLEService()

    @Published var isParticipating = false
    @Published var sightingsReportedCount = 0

    // Known tag UUIDs from all ShouDeng users (fetched from server periodically)
    private var knownTagUUIDs: Set<String> = []
    private var tagOwnerPublicKeys: [String: Data] = [:]

    private var centralManager: CBCentralManager?
    private var locationManager: CLLocationManager?
    private var pendingSightings: [CrowdSighting] = []
    private let maxBatchSize = 20
    private let flushInterval: TimeInterval = 60
    private var flushTimer: Timer?

    private let queue = DispatchQueue(label: "com.shoudeng.crowd-ble", qos: .utility)

    // Injected API client (set via configure())
    private weak var apiClient: APIClient?
    private var encryption: E2ELocationEncryption?

    struct CrowdSighting: Codable {
        let tagUUID: String
        let encryptedLocation: String
        let rssi: Int
        let timestamp: Date
        let reporterDeviceId: String
    }

    private override init() {
        super.init()
    }

    // MARK: - Configuration

    func configure(apiClient: APIClient, encryption: E2ELocationEncryption) {
        self.apiClient = apiClient
        self.encryption = encryption
    }

    // MARK: - Public API

    func startParticipating() {
        guard !isParticipating else { return }

        centralManager = CBCentralManager(
            delegate: self,
            queue: queue,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "com.shoudeng.crowd-sighting",
                CBCentralManagerOptionShowPowerAlertKey: false
            ]
        )

        locationManager = CLLocationManager()
        locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager?.allowsBackgroundLocationUpdates = true
        locationManager?.startUpdatingLocation()

        startFlushTimer()
        DispatchQueue.main.async { self.isParticipating = true }

        Task { await refreshKnownTags() }
    }

    func stopParticipating() {
        centralManager?.stopScan()
        centralManager = nil
        flushTimer?.invalidate()
        flushTimer = nil
        isParticipating = false
    }

    func refreshKnownTags() async {
        guard let apiClient else { return }

        do {
            struct TagListResponse: Decodable {
                let tags: [TagEntry]
            }
            struct TagEntry: Decodable {
                let uuid: String
                let publicKey: String
            }

            let response: TagListResponse = try await apiClient.get("/v1/device/crowd-tags")
            var uuids = Set<String>()
            var keys: [String: Data] = [:]
            for tag in response.tags {
                uuids.insert(tag.uuid.uppercased())
                if let keyData = Data(base64Encoded: tag.publicKey) {
                    keys[tag.uuid.uppercased()] = keyData
                }
            }
            await MainActor.run {
                self.knownTagUUIDs = uuids
                self.tagOwnerPublicKeys = keys
            }
        } catch {
            #if DEBUG
            print("[CrowdBLE] Failed to refresh known tags: \(error)")
            #endif
        }
    }

    // MARK: - Sighting Processing

    private func processSighting(peripheralUUID: String, rssi: Int) {
        let upperUUID = peripheralUUID.uppercased()
        guard knownTagUUIDs.contains(upperUUID) else { return }

        guard let location = locationManager?.location else { return }
        guard let encryption, let publicKey = tagOwnerPublicKeys[upperUUID] else { return }

        let encryptedLocation: String
        do {
            let payload = E2ELocationEncryption.LocationPayload(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy,
                altitude: location.altitude,
                speed: location.speed,
                timestamp: Date(),
                activityType: nil
            )
            let encrypted = try encryption.encrypt(location: payload, forRecipientPublicKey: publicKey)
            encryptedLocation = encrypted.ciphertext
        } catch {
            return
        }

        // Rotating daily hash — prevents cross-session reporter correlation
        let rawId = (UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
        let daySalt = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let input = Data((rawId + String(daySalt)).utf8)
        let hash = SHA256.hash(data: input)
        let deviceId = hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        let sighting = CrowdSighting(
            tagUUID: upperUUID,
            encryptedLocation: encryptedLocation,
            rssi: rssi,
            timestamp: Date(),
            reporterDeviceId: deviceId
        )

        queue.async { [weak self] in
            self?.pendingSightings.append(sighting)
            if (self?.pendingSightings.count ?? 0) >= (self?.maxBatchSize ?? 20) {
                self?.flushSightings()
            }
        }
    }

    private func flushSightings() {
        guard !pendingSightings.isEmpty, let apiClient else { return }

        let batch = Array(pendingSightings.prefix(maxBatchSize))
        pendingSightings.removeFirst(min(maxBatchSize, pendingSightings.count))

        Task {
            do {
                struct BatchRequest: Encodable {
                    let sightings: [CrowdSighting]
                }
                struct EmptyResponse: Decodable {}
                let _: EmptyResponse = try await apiClient.post("/v1/device/ble-sightings", body: BatchRequest(sightings: batch))
                await MainActor.run {
                    self.sightingsReportedCount += batch.count
                }
            } catch {
                queue.async { [weak self] in
                    self?.pendingSightings.append(contentsOf: batch)
                }
            }
        }
    }

    private func startFlushTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.flushTimer = Timer.scheduledTimer(withTimeInterval: self?.flushInterval ?? 60, repeats: true) { [weak self] _ in
                self?.queue.async { self?.flushSightings() }
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension CrowdSourcedBLEService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }

        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let uuid = peripheral.identifier.uuidString
        processSighting(peripheralUUID: uuid, rssi: RSSI.intValue)

        if let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           mfgData.count >= 23,
           mfgData[0] == 0x4C, mfgData[1] == 0x00 {
            let beaconUUID = extractBeaconUUID(from: mfgData)
            if let beaconUUID {
                processSighting(peripheralUUID: beaconUUID, rssi: RSSI.intValue)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                processSighting(peripheralUUID: peripheral.identifier.uuidString, rssi: -70)
            }
        }
    }

    private func extractBeaconUUID(from mfgData: Data) -> String? {
        guard mfgData.count >= 23 else { return nil }
        guard mfgData[2] == 0x02, mfgData[3] == 0x15 else { return nil }
        let uuidBytes = mfgData.subdata(in: 4..<20)
        let uuid = NSUUID(uuidBytes: [UInt8](uuidBytes)) as UUID
        return uuid.uuidString
    }
}
