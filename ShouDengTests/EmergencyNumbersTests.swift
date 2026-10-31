import XCTest
@testable import ShouDeng

/// The number the app tells people to call in an SOS, per App Store market.
/// Mirrors shoudeng-backend services/twilio.ts getEmergencyNumber.
final class EmergencyNumbersTests: XCTestCase {

    static let primary: [String: String] = [
        "US": "911", "CA": "911", "HK": "999", "MO": "999", "TW": "119", "SG": "995",
        "AU": "000", "NZ": "111", "MY": "999", "TH": "1669", "PH": "911", "JP": "119",
    ]

    func testEveryMarketHasItsOwnPrimaryNumber() {
        for (country, number) in Self.primary {
            let info = RegionalEmergencyInfo.forCountry(country)
            XCTAssertEqual(info.numbers.first?.number, number, country)
            XCTAssertFalse(info.areaCode.isEmpty, "\(country) is not falling back to the generic entry")
            XCTAssertTrue(RegionalEmergencyInfo.supportedRegions.contains(country), country)
        }
    }

    func testUnknownRegionFallsBackTo112() {
        XCTAssertEqual(RegionalEmergencyInfo.forCountry("ZZ").numbers.first?.number, "112")
    }

    func testLabelsAreLocalizedNotRawKeys() {
        for country in RegionalEmergencyInfo.supportedRegions {
            for n in RegionalEmergencyInfo.forCountry(country).numbers {
                XCTAssertFalse(n.label.hasPrefix("emergency.svc."), "\(country): \(n.label)")
            }
        }
    }
}
