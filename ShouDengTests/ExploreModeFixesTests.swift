import XCTest
import SwiftUI
import CoreLocation
@testable import ShouDeng

/// Regressions found while walking through Explore Mode on a simulator.
@MainActor
final class ExploreModeFixesTests: XCTestCase {

    override func tearDown() async throws {
        ExploreModeController.shared.exit()
        try await super.tearDown()
    }

    // MARK: 1. The demo showed this phone's real GPS position as Mom's

    func testDemoUsesThePersonaLocationNeverTheDevice() throws {
        let explore = ExploreModeController.shared
        explore.start(role: .mom)
        let demo = try XCTUnwrap(explore.coordinator)
        let chengdu = DemoRole.mom.homeCoordinate

        let best = try XCTUnwrap(demo.locationManager.bestAvailableLocation)
        XCTAssertEqual(best.coordinate.latitude, chengdu.latitude, accuracy: 1e-6)
        XCTAssertEqual(best.coordinate.longitude, chengdu.longitude, accuracy: 1e-6)
        let reported = try XCTUnwrap(demo.locationManager.lastReportedLocation)
        XCTAssertEqual(reported.coordinate.latitude, chengdu.latitude, accuracy: 1e-6)
    }

    // MARK: 2–3. Tip buttons never received taps (SwiftUI buttons have no UIView)

    func testOverlayTakesTouchesOnlyInsideReportedRegions() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = UIViewController()
        window.isHidden = false
        let overlay = PassthroughOverlayView(frame: window.bounds)
        let host = UIHostingController(rootView: Color.clear)
        host.view.frame = overlay.bounds
        overlay.addSubview(host.view)
        overlay.hostView = host.view
        window.addSubview(overlay)
        window.layoutIfNeeded()

        var regions: [CGRect] = []
        overlay.interactiveRegions = { regions }
        XCTAssertNil(overlay.hitTest(CGPoint(x: 200, y: 600), with: nil), "empty overlay passes touches through")
        XCTAssertFalse(window.hitTest(CGPoint(x: 200, y: 600), with: nil) is PassthroughOverlayView)

        regions = [CGRect(x: 16, y: 500, width: 368, height: 230)] // tip card
        XCTAssertNotNil(overlay.hitTest(CGPoint(x: 60, y: 700), with: nil), "\"Hide tips\" on the card is tappable")
        XCTAssertNil(overlay.hitTest(CGPoint(x: 200, y: 100), with: nil), "app above the card still gets the tap")
        window.isHidden = true
    }

    // MARK: 4. Feature disclosures were Chinese-only and always said 112

    func testFeatureDisclosuresNameTheLocalEmergencyNumber() {
        let body = DisclaimerCopy.FeatureDisclosure.sos.body(emergencyNumber: "911")
        XCTAssertTrue(body.contains("911"))
        XCTAssertFalse(body.contains("112"))
        XCTAssertFalse(body.contains("%@"))
    }

    func testFeatureDisclosureCopyExistsInEveryLanguage() throws {
        let keys = DisclaimerCopy.FeatureDisclosure.allCases.flatMap {
            ["disclosure.\($0.rawValue).title", "disclosure.\($0.rawValue).body"]
        } + ["disclosure.button.notNow", "disclosure.button.enable",
             "disclosure.button.sendSOS", "disclosure.button.understood", "home.arrivalReport"]
        for language in ["en", "zh-Hans", "zh-Hant", "fr", "ja"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                      inDirectory: nil, forLocalization: language), language)
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], language)
            for key in keys {
                XCTAssertFalse(table[key, default: ""].isEmpty, "\(language): \(key)")
            }
            XCTAssertTrue(table["disclosure.sos.body", default: ""].contains("%@"), "\(language): SOS number placeholder")
        }
    }

    // MARK: 5. Two home tiles were both labelled "Share Itinerary"

    func testArrivalReportTileHasItsOwnLabel() throws {
        for language in ["en", "zh-Hans", "zh-Hant", "fr", "ja"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                      inDirectory: nil, forLocalization: language))
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            XCTAssertNotEqual(table["home.arrivalReport"], table["home.itinerary"], language)
        }
    }

    // MARK: 6. Full button test leftovers

    private func demoStore(as user: String) -> (DemoStore, JSONDecoder) {
        let store = DemoStore(dataset: DemoDataset.build(now: Date(), language: .english), currentUserId: user)
        let decoder = APIClient(config: .init(baseURL: DemoURLProtocol.baseURL), offlineQueue: OfflineQueue(fileURL: nil)).decoder
        return (store, decoder)
    }

    func testSarahSeesWhoElseLooksAfterMomAndWhen() throws {
        let (store, decoder) = demoStore(as: DemoDataset.sarahId)
        let r = try XCTUnwrap(store.respond(method: "GET", path: "/v1/guardian/circle", query: ["personId": DemoDataset.momId], body: nil))
        XCTAssertEqual(r.0, 200)
        let circle = try decoder.decode([Guardian].self, from: r.1)
        XCTAssertEqual(circle.map(\.user.displayName), ["Sarah Chen", "Kevin Chen", "Lucy Chen"])
        XCTAssertTrue(circle.allSatisfy { $0.dutySchedule != nil })

        store.currentUserId = DemoDataset.kaiId // not one of Mom's guardians
        XCTAssertEqual(store.respond(method: "GET", path: "/v1/guardian/circle", query: ["personId": DemoDataset.momId], body: nil)?.0, 403)
    }

    func testMomsSOSStartAndEndAreOnHerTimeline() throws {
        let (store, decoder) = demoStore(as: DemoDataset.sarahId)
        let sos = store.triggerSOS(personId: DemoDataset.momId)
        _ = store.acknowledgeSOS(sosEventId: sos.sosEventId, by: DemoDataset.sarahId)
        store.resolveSOS(id: sos.sosEventId)
        let r = try XCTUnwrap(store.respond(method: "GET", path: "/v1/timeline", query: ["personId": DemoDataset.momId], body: nil))
        let types = try decoder.decode(TimelineResponse.self, from: r.1).entries.prefix(3).map(\.type)
        XCTAssertEqual(Set(types), [.sosTriggered, .guardianAlert, .sosResolved])
    }

    func testClaimMaterialsHaveMomsMedicalCardAndHerSOS() throws {
        let (store, decoder) = demoStore(as: DemoDataset.momId)
        let sos = store.triggerSOS(personId: DemoDataset.momId)
        store.resolveSOS(id: sos.sosEventId)
        let request = ClaimMaterialRequest(incidentDate: Date(), windowHours: 24, description: nil, insuranceType: nil, policyNumber: nil,
                                           includeSOS: true, includeCheckIns: true, includeTimeline: true,
                                           includeLocation: true, includeMedicalCard: true)
        let body = try APIClient(config: .init(baseURL: DemoURLProtocol.baseURL), offlineQueue: OfflineQueue(fileURL: nil)).encoder.encode(request)
        let r = try XCTUnwrap(store.respond(method: "POST", path: "/v1/insurance/claim-materials", query: [:], body: body))
        XCTAssertEqual(r.0, 200)
        let export = try decoder.decode(ClaimMaterialExport.self, from: r.1)
        XCTAssertEqual(export.personName, "Xiulan Chen")
        XCTAssertEqual(export.medicalSnapshot?.bloodType, "A+")
        XCTAssertEqual(export.medicalSnapshot?.allergies, ["Penicillin"])
        XCTAssertEqual(export.sosEvents?.count, 1)
        XCTAssertFalse(export.contentHash.isEmpty)
        XCTAssertFalse(try XCTUnwrap(export.medicalSnapshot).isEmpty)
        XCTAssertTrue(MedicalSnapshot(bloodType: nil, allergies: [], conditions: nil, insuranceProvider: "", policyNumber: nil).isEmpty)
    }

    func testPersonaBatteryIsTheDemoPhones() {
        let (store, _) = demoStore(as: DemoDataset.momId)
        XCTAssertEqual(store.batteryLevel(of: DemoDataset.momId), 0.82)
        XCTAssertEqual(store.batteryLevel(of: DemoDataset.dadId), 0.17)
    }

    func testShiftHoursReadAsRanges() {
        XCTAssertEqual(GuardianRecordsView.hourRanges([20, 21, 22, 23, 0, 1]), "00:00–02:00, 20:00–24:00")
        XCTAssertEqual(GuardianRecordsView.hourRanges([8]), "08:00–09:00")
    }

    func testNewCopyExistsInEveryLanguage() throws {
        let keys = ["emergencyContact.delete.title", "emergencyContact.delete.message", "emergencyContact.delete.confirm",
                    "emergencyContact.delete.cancel", "guardian.alert.sosEnded", "guardian.records.coverage",
                    "guardian.records.shift.none", "guardian.records.shift.awake", "guardian.records.shift.gap",
                    "claim.medicalEmpty", "timeline.sosEnded", "duress.how.step5"]
        for language in ["en", "zh-Hans", "zh-Hant", "fr", "ja"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                      inDirectory: nil, forLocalization: language))
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            for key in keys { XCTAssertFalse(table[key, default: ""].isEmpty, "\(language): \(key)") }
            XCTAssertFalse(table["deadman.info.title", default: ""].localizedCaseInsensitiveContains("dead man"), language)
        }
    }
}
