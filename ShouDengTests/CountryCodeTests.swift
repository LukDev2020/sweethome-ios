import XCTest
@testable import ShouDeng

final class CountryCodeTests: XCTestCase {

    // MARK: - Data Integrity

    func testAllCountriesHaveRequiredFields() {
        for country in CountryCode.all {
            XCTAssertFalse(country.name.isEmpty, "\(country.isoCode) missing name")
            XCTAssertFalse(country.localName.isEmpty, "\(country.isoCode) missing localName")
            XCTAssertTrue(country.dialCode.hasPrefix("+"), "\(country.isoCode) dialCode should start with +")
            XCTAssertEqual(country.isoCode.count, 2, "\(country.isoCode) should be 2-letter ISO code")
            XCTAssertFalse(country.flag.isEmpty, "\(country.isoCode) missing flag emoji")
        }
    }

    func testNoDuplicateISOCodes() {
        let codes = CountryCode.all.map(\.isoCode)
        let unique = Set(codes)
        XCTAssertEqual(codes.count, unique.count, "Duplicate ISO codes found")
    }

    func testMinimumCountryCount() {
        // Should have at least 50 countries
        XCTAssertGreaterThanOrEqual(CountryCode.all.count, 50)
    }

    // MARK: - Key Countries Present

    func testMajorCountriesPresent() {
        let required = ["CN", "US", "GB", "JP", "KR", "AU", "DE", "FR", "IN", "SG", "HK", "TW"]
        for code in required {
            XCTAssertTrue(
                CountryCode.all.contains { $0.isoCode == code },
                "Missing required country: \(code)"
            )
        }
    }

    func testChinaDialCode() {
        let china = CountryCode.all.first { $0.isoCode == "CN" }
        XCTAssertNotNil(china)
        XCTAssertEqual(china?.dialCode, "+86")
        XCTAssertEqual(china?.localName, "中国")
    }

    func testUSDialCode() {
        let us = CountryCode.all.first { $0.isoCode == "US" }
        XCTAssertNotNil(us)
        XCTAssertEqual(us?.dialCode, "+1")
    }

    func testJapanDialCode() {
        let jp = CountryCode.all.first { $0.isoCode == "JP" }
        XCTAssertNotNil(jp)
        XCTAssertEqual(jp?.dialCode, "+81")
    }

    // MARK: - Flag Emoji Generation

    func testFlagEmojiForChina() {
        let flag = CountryCode.flag(for: "CN")
        XCTAssertFalse(flag.isEmpty)
        // Should be the Chinese flag emoji (2 unicode scalars)
        XCTAssertEqual(flag.unicodeScalars.count, 2)
    }

    func testFlagEmojiForUS() {
        let flag = CountryCode.flag(for: "US")
        XCTAssertFalse(flag.isEmpty)
        XCTAssertEqual(flag.unicodeScalars.count, 2)
    }

    func testFlagEmojiCaseInsensitive() {
        // flag(for:) uppercases internally
        let lower = CountryCode.flag(for: "cn")
        let upper = CountryCode.flag(for: "CN")
        XCTAssertEqual(lower, upper)
    }

    // MARK: - Device Default

    func testDeviceDefaultReturnsValidCountry() {
        let defaultCountry = CountryCode.deviceDefault
        XCTAssertFalse(defaultCountry.name.isEmpty)
        XCTAssertTrue(defaultCountry.dialCode.hasPrefix("+"))
    }

    // MARK: - Identifiable / Hashable

    func testIdentifiableUsesISOCode() {
        let china = CountryCode.all.first { $0.isoCode == "CN" }!
        XCTAssertEqual(china.id, "CN")
    }

    func testHashableConformance() {
        let china = CountryCode.all.first { $0.isoCode == "CN" }!
        let us = CountryCode.all.first { $0.isoCode == "US" }!
        let set: Set<CountryCode> = [china, us, china]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - Search/Filter Simulation

    func testFilterByEnglishName() {
        let results = CountryCode.all.filter {
            $0.name.lowercased().contains("china")
        }
        XCTAssertTrue(results.contains { $0.isoCode == "CN" })
    }

    func testFilterByChineseName() {
        let results = CountryCode.all.filter {
            $0.localName.contains("日本")
        }
        XCTAssertTrue(results.contains { $0.isoCode == "JP" })
    }

    func testFilterByDialCode() {
        let results = CountryCode.all.filter {
            $0.dialCode.contains("+86")
        }
        XCTAssertTrue(results.contains { $0.isoCode == "CN" })
    }

    func testFilterByISOCode() {
        let results = CountryCode.all.filter {
            $0.isoCode.lowercased() == "gb"
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "United Kingdom")
    }
}
