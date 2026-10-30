import XCTest
@testable import ShouDeng

/// Every `localized("…")` key used in the app must exist in en, zh-Hans and fr —
/// otherwise users see raw keys like `location.justUpdated` on screen.
final class LocalizationCompletenessTests: XCTestCase {

    private static let languages = ["en", "zh-Hans", "fr"]

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func table(_ lang: String) throws -> [String: String] {
        let bundle = Bundle(for: AppCoordinator.self)
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: lang),
                                "Localizable.strings missing for \(lang)")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    /// Keys passed as a literal to LanguageManager.localized (any receiver except
    /// WidgetDataStore, which has its own switch-based table).
    private func usedKeys() throws -> [String: String] {
        var keys: [String: String] = [:]
        let regex = try NSRegularExpression(pattern: #"(\w+(?:\.shared)?)\.localized\(\s*"([^"\\]+)""#)
        let dir = repoRoot.appendingPathComponent("ShouDeng")
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 100, "source scan found too few files — wrong root?")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let receiver = String(text[Range(m.range(at: 1), in: text)!])
                if receiver == "WidgetDataStore" { continue }
                let key = String(text[Range(m.range(at: 2), in: text)!])
                keys[key] = file.lastPathComponent
            }
        }
        return keys
    }

    func testEveryUsedKeyExistsInAllLanguages() throws {
        let used = try usedKeys()
        XCTAssertGreaterThan(used.count, 500)
        for lang in Self.languages {
            let t = try table(lang)
            let missing = used.keys.filter { t[$0] == nil }.sorted()
            XCTAssertTrue(missing.isEmpty, "\(lang) is missing \(missing.count) keys: \(missing.prefix(20).map { "\($0) (\(used[$0]!))" })")
        }
    }

    func testTablesHaveTheSameKeys() throws {
        let en = Set(try table("en").keys)
        for lang in ["zh-Hans", "fr"] {
            let other = Set(try table(lang).keys)
            XCTAssertEqual(en.subtracting(other).sorted(), [], "\(lang) lacks keys present in en")
            XCTAssertEqual(other.subtracting(en).sorted(), [], "\(lang) has keys missing from en")
        }
    }

    /// `String(format:)` with a translation whose placeholders differ crashes or
    /// prints garbage ("3 %d guardians").
    func testFormatPlaceholdersMatchAcrossLanguages() throws {
        let spec = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|h)?([dDiuxXfFeEgGcsS@])"#)
        func placeholders(_ s: String) -> [String] {
            let cleaned = s.replacingOccurrences(of: "%%", with: "")
            return spec.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
                .map { String(cleaned[Range($0.range(at: 1), in: cleaned)!]) }.sorted()
        }
        let en = try table("en")
        for lang in ["zh-Hans", "fr"] {
            let t = try table(lang)
            for (key, value) in en {
                guard let other = t[key] else { continue }
                XCTAssertEqual(placeholders(value), placeholders(other), "\(lang) \(key): \"\(value)\" vs \"\(other)\"")
            }
        }
    }

    /// `String(format: localized("key"), args…)` with a translation that has no
    /// placeholder silently drops the arguments ("Seeking Help" instead of
    /// "Mom needs help").
    func testFormatCallSitesUseKeysWithPlaceholders() throws {
        let en = try table("en")
        let call = try NSRegularExpression(pattern: #"String\(format:\s*\w+(?:\.shared)?\.localized\("([^"]+)"(?:,\s*fallback:\s*"[^"]*")?\)\s*,"#)
        let spec = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|h)?[dDiuxXfFeEgGcsS@]"#)
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: repoRoot.appendingPathComponent("ShouDeng"), includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for m in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(m.range(at: 1), in: text)!])
                guard let value = en[key] else { continue }
                let cleaned = value.replacingOccurrences(of: "%%", with: "")
                if spec.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) == nil {
                    offenders.append("\(file.lastPathComponent): \(key) = \"\(value)\"")
                }
            }
        }
        XCTAssertEqual(offenders, [])
    }

    func testFormattedKeysRenderWithoutRawPlaceholders() {
        let lm = LanguageManager.shared
        let battery = String(format: lm.localized("protected.home.battery"), 82)
        XCTAssertTrue(battery.contains("82%"), battery)
        XCTAssertFalse(battery.contains("%d"))
        let guardians = String(format: lm.localized("protected.home.guardianCount"), 3)
        XCTAssertTrue(guardians.contains("3"))
        XCTAssertFalse(guardians.contains("%d"))
        XCTAssertNotEqual(lm.localized("location.justUpdated"), "location.justUpdated")
        XCTAssertNotEqual(lm.localized("guardian.member.batteryLabel"), "guardian.member.batteryLabel")
    }
}
