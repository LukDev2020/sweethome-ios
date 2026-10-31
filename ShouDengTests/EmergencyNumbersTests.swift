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

    /// Pinning Japan used to save 110 (police) as the hotline card's red "emergency" button.
    func testConsulateEntriesUseTheAmbulanceFirstNumber() {
        for (country, number) in ["JP": "119", "TH": "1669", "SG": "995", "US": "911", "AU": "000"] {
            let entry = ConsulateEntry(code: country, flag: "", embassy: "", consulates: [])
            XCTAssertEqual(entry.emergency, number, country)
        }
    }
}

/// The in-app privacy policy and terms must exist in every UI language and
/// name the local emergency number, not China's 110/119/120.
final class LegalCopyTests: XCTestCase {
    func testEveryLanguageHasPolicyTermsAndTransferSection() {
        for language in AppLanguage.allCases {
            let blocks = LegalCopy.blocks(for: language, emergencyNumber: "000")
            let text = blocks.map { block -> String in
                switch block {
                case .title(let t), .updated(let t), .header(let t), .body(let t): return t
                case .bullet(let a, let b): return a + b
                case .divider: return ""
                }
            }.joined(separator: "\n")
            let titles = blocks.filter { if case .title = $0 { return true }; return false }
            XCTAssertEqual(titles.count, 2, "\(language): privacy policy + terms")
            XCTAssertTrue(text.contains("us-central1"), "\(language): cross-border transfer section")
            XCTAssertTrue(text.contains("000"), "\(language): local emergency number")
            XCTAssertFalse(text.contains("110/119/120"), "\(language)")
        }
    }

    func testTraditionalPolicyHasNoSimplifiedOnlyCharacters() {
        let text = LegalCopy.blocks(for: .traditionalChinese, emergencyNumber: "999").compactMap { block -> String? in
            if case .body(let t) = block { return t }; return nil
        }.joined()
        for ch in ["数", "据", "护", "务", "联"] {
            XCTAssertFalse(text.contains(ch), ch)
        }
    }
}

