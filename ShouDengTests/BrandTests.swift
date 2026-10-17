import XCTest
@testable import ShouDeng

final class BrandTests: XCTestCase {

    // MARK: - Brand Helpers

    func testDisplayTitleEnglish() {
        XCTAssertEqual(Brand.displayTitle(locale: .english), "Vela")
    }

    func testDisplayTitleChinese() {
        XCTAssertEqual(Brand.displayTitle(locale: .chinese), "守灯")
    }

    func testDisplayTitleFrench() {
        XCTAssertEqual(Brand.displayTitle(locale: .french), "Vela")
    }

    func testDisplaySubtitleEnglish() {
        XCTAssertEqual(Brand.displaySubtitle(locale: .english), "守灯")
    }

    func testDisplaySubtitleChinese() {
        XCTAssertEqual(Brand.displaySubtitle(locale: .chinese), "VELA")
    }

    func testBrandConstants() {
        XCTAssertEqual(Brand.nameEN, "Vela")
        XCTAssertEqual(Brand.nameZH, "守灯")
        XCTAssertEqual(Brand.domain, "velar.care")
    }

    // MARK: - Banned Strings Scan

    /// Scans all .strings files in the main bundle for banned brand names.
    /// Fails if "Velar Care", "VELAR CARE", or "ShouDeng" appear in any
    /// user-facing localization file.
    func testNoBannedBrandNamesInStrings() throws {
        let bannedPatterns = ["Velar Care", "VELAR CARE", "ShouDeng"]
        let bundle = Bundle(for: type(of: self))

        // Check all lproj directories we ship
        let locales = ["en", "zh-Hans", "fr"]
        var violations: [String] = []

        for locale in locales {
            for table in ["Localizable", "InfoPlist"] {
                guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"),
                      let lprojBundle = Bundle(path: path) else { continue }

                guard let stringsPath = lprojBundle.path(forResource: table, ofType: "strings") else { continue }
                guard let contents = try? String(contentsOfFile: stringsPath, encoding: .utf8) else { continue }

                for banned in bannedPatterns {
                    if contents.contains(banned) {
                        violations.append("\(locale)/\(table).strings contains '\(banned)'")
                    }
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, "Banned brand names found:\n\(violations.joined(separator: "\n"))")
    }

    /// Scans Swift source files for hardcoded "Velar Care" or "ShouDeng" in
    /// user-facing strings (string literals). Allows struct/class names.
    func testNoBannedBrandNamesInSwiftSources() throws {
        // This test scans the project source directory for .swift files
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ShouDengTests/
            .deletingLastPathComponent() // project root

        let sourceDir = projectRoot.appendingPathComponent("ShouDeng")
        let bannedPatterns = ["\"Velar Care\"", "\"VELAR CARE\""]
        var violations: [String] = []

        let enumerator = FileManager.default.enumerator(
            at: sourceDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for banned in bannedPatterns {
                if contents.contains(banned) {
                    violations.append("\(fileURL.lastPathComponent) contains \(banned)")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, "Banned brand names in Swift sources:\n\(violations.joined(separator: "\n"))")
    }
}
