import XCTest
import MapKit
@testable import ShouDeng

/// Carrier satellite data mode, the Apple Maps link and the trip preflight checklist.
final class OutdoorSatelliteTests: XCTestCase {

    private func makeClient() -> (APIClient, OfflineQueue) {
        let queue = OfflineQueue(fileURL: nil) // in-memory
        let client = APIClient(config: APIClient.Config(baseURL: "https://api.example.test"), offlineQueue: queue)
        return (client, queue)
    }

    // MARK: Which requests may use satellite

    func testSafetyRequestsMayUseSatellite() {
        for path in ["/v1/sos/trigger", "/v1/sos/resolve", "/v1/sos/acknowledge", "/v1/checkin",
                     "/v1/home-timer/dismiss", "/v1/arrival-report", "/v1/heartbeat", "/v1/location/report"] {
            XCTAssertTrue(SatelliteDataPolicy.allowsSatellite(path: path), path)
        }
    }

    func testEverythingElseWaitsForANormalConnection() {
        for path in ["/v1/family/posts", "/v1/trip/abc/points", "/v1/location/batch", "/v1/user/me",
                     "/v1/timeline", "/v1/guardian/protected-persons", "/v1/medical-card"] {
            XCTAssertFalse(SatelliteDataPolicy.allowsSatellite(path: path), path)
        }
    }

    func testRequestsCarryTheSatelliteFlag() throws {
        guard #available(iOS 26.1, *) else { throw XCTSkip("ultra-constrained networking needs iOS 26.1") }
        let (client, _) = makeClient()
        XCTAssertTrue(try client.buildRawRequest(path: "/v1/sos/trigger", method: "POST").allowsUltraConstrainedNetworkAccess)
        XCTAssertFalse(try client.buildRawRequest(path: "/v1/family/posts", method: "GET").allowsUltraConstrainedNetworkAccess)
    }

    // MARK: Thinning periodic reports

    func testPeriodicReportsAreThinnedOnlyOnSatellite() {
        let policy = SatelliteDataPolicy(minInterval: 600)
        let t0 = Date()
        // Normal connection: never skipped.
        XCTAssertFalse(policy.shouldSkip(path: "/v1/heartbeat", now: t0))
        XCTAssertFalse(policy.shouldSkip(path: "/v1/heartbeat", now: t0.addingTimeInterval(5)))

        policy.isOnSatellite = true
        XCTAssertFalse(policy.shouldSkip(path: "/v1/location/report", now: t0))
        XCTAssertTrue(policy.shouldSkip(path: "/v1/location/report", now: t0.addingTimeInterval(120)))
        XCTAssertFalse(policy.shouldSkip(path: "/v1/location/report", now: t0.addingTimeInterval(601)))
    }

    func testSOSIsNeverThinned() {
        let policy = SatelliteDataPolicy(minInterval: 600)
        policy.isOnSatellite = true
        let t0 = Date()
        for i in 0..<5 {
            XCTAssertFalse(policy.shouldSkip(path: "/v1/sos/trigger", now: t0.addingTimeInterval(Double(i))))
        }
    }

    func testThinnedHeartbeatIsNotQueued() {
        let (client, queue) = makeClient()
        client.satellitePolicy.isOnSatellite = true
        _ = client.satellitePolicy.shouldSkip(path: "/v1/heartbeat") // one just went out

        var result: Bool?
        client.postQueued("/v1/heartbeat", body: ["batteryLevel": 0.5]) { result = $0 }
        XCTAssertEqual(result, false, "skipped synchronously")
        XCTAssertEqual(queue.pendingCount, 0, "a stale heartbeat must not be replayed later")
    }

    // MARK: Connectivity

    func testConnectivityMonitorReportsSatelliteChanges() {
        let monitor = ConnectivityMonitor()
        var states: [Bool] = []
        let on = expectation(description: "on satellite")
        let off = expectation(description: "off satellite")
        monitor.onSatelliteChanged = { onSatellite in
            states.append(onSatellite)
            (onSatellite ? on : off).fulfill()
        }
        monitor.handle(satisfied: true, ultraConstrained: true)
        wait(for: [on], timeout: 1)
        monitor.handle(satisfied: true, ultraConstrained: false)
        wait(for: [off], timeout: 1)
        XCTAssertEqual(states, [true, false])
        XCTAssertFalse(monitor.isOnSatellite)
    }

    // MARK: Apple Maps link

    func testAppleMapsItemCarriesCoordinateAndName() {
        let coordinate = CLLocationCoordinate2D(latitude: 49.3255, longitude: -123.0636)
        let item = AppleMapsLink.mapItem(for: coordinate, name: "Mom")
        XCTAssertEqual(item.name, "Mom")
        let location: CLLocationCoordinate2D
        if #available(iOS 26.0, *) {
            location = item.location.coordinate
        } else {
            location = item.placemark.coordinate
        }
        XCTAssertEqual(location.latitude, coordinate.latitude, accuracy: 1e-6)
        XCTAssertEqual(location.longitude, coordinate.longitude, accuracy: 1e-6)

        let pin = AppleMapsLink.launchOptions(for: coordinate, walkingDirections: false)
        XCTAssertNotNil(pin[MKLaunchOptionsMapCenterKey])
        XCTAssertNil(pin[MKLaunchOptionsDirectionsModeKey])
        let walk = AppleMapsLink.launchOptions(for: coordinate, walkingDirections: true)
        XCTAssertEqual(walk[MKLaunchOptionsDirectionsModeKey] as? String, MKLaunchOptionsDirectionsModeWalking)
    }

    // MARK: Preflight checklist

    func testPreflightOffersCarrierSatelliteOnlyWhereSupported() {
        if #available(iOS 26.1, *) {
            XCTAssertTrue(TripPreflightView.Item.available.contains(.carrierSatellite))
        } else {
            XCTAssertFalse(TripPreflightView.Item.available.contains(.carrierSatellite))
        }
        XCTAssertTrue(TripPreflightView.Item.available.contains(.offlineMaps))
    }

    /// The checklist builds its keys at runtime, so check every one exists in all languages.
    func testPreflightCopyExistsInEveryLanguage() throws {
        let keys = TripPreflightView.Item.allCases.flatMap { ["preflight.\($0.rawValue).title", "preflight.\($0.rawValue).detail"] }
            + ["preflight.offlineMaps.action", "satellite.banner.title", "satellite.banner.detail",
               "maps.open.apple", "maps.open.directions", "maps.open.hint"]
        for language in ["en", "zh-Hans", "fr"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                      inDirectory: nil, forLocalization: language), language)
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], language)
            for key in keys {
                XCTAssertFalse(table[key, default: ""].isEmpty, "\(language): \(key)")
            }
        }
    }
}
