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

    func testOverlayWindowTakesTouchesOnlyInsideReportedRegions() {
        let window = PassthroughWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = UIHostingController(rootView: Color.clear)
        window.isHidden = false
        window.layoutIfNeeded()

        var regions: [CGRect] = []
        window.interactiveRegions = { regions }
        XCTAssertNil(window.hitTest(CGPoint(x: 200, y: 600), with: nil), "empty overlay passes touches through")

        regions = [CGRect(x: 16, y: 500, width: 368, height: 230)] // tip card
        XCTAssertNotNil(window.hitTest(CGPoint(x: 60, y: 700), with: nil), "\"Hide tips\" on the card is tappable")
        XCTAssertNil(window.hitTest(CGPoint(x: 200, y: 100), with: nil), "app above the card still gets the tap")
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
        for language in ["en", "zh-Hans", "fr"] {
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
        for language in ["en", "zh-Hans", "fr"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                      inDirectory: nil, forLocalization: language))
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            XCTAssertNotEqual(table["home.arrivalReport"], table["home.itinerary"], language)
        }
    }
}
