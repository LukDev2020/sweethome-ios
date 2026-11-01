import XCTest
@testable import ShouDeng

/// Every `localized("…")` key used in the app must exist in en, zh-Hans and fr —
/// otherwise users see raw keys like `location.justUpdated` on screen.
final class LocalizationCompletenessTests: XCTestCase {

    private static let languages = ["en", "zh-Hans", "zh-Hant", "fr", "ja"]

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
        for lang in ["zh-Hans", "zh-Hant", "fr", "ja"] {
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
        for lang in ["zh-Hans", "zh-Hant", "fr", "ja"] {
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

/// Hong Kong, Macao and Taiwan use Traditional Chinese.
final class TraditionalChineseTests: XCTestCase {

    func testTraditionalChineseIsDetectedFromSystemLanguage() {
        for preferred in ["zh-Hant-TW", "zh-Hant-HK", "zh-HK", "zh-TW", "zh-Hant-MO"] {
            XCTAssertEqual(LanguageManager.detectLanguage(preferred: preferred), .traditionalChinese, preferred)
        }
        XCTAssertEqual(LanguageManager.detectLanguage(preferred: "zh-Hans-CN"), .chinese)
        XCTAssertEqual(LanguageManager.detectLanguage(preferred: "fr-CA"), .french)
        XCTAssertEqual(LanguageManager.detectLanguage(preferred: "en-SG"), .english)
    }

    func testTraditionalTableIsInTraditionalCharacters() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                  inDirectory: nil, forLocalization: "zh-Hant"))
        let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        XCTAssertEqual(table["app.name"], "守燈")
        // A few characters that only exist in Simplified must not appear.
        let simplifiedOnly = CharacterSet(charactersIn: "灯这说们设边过还")
        let offenders = table.filter { $0.value.rangeOfCharacter(from: simplifiedOnly) != nil }.map(\.key)
        XCTAssertEqual(offenders, [], "Simplified characters in zh-Hant")
    }

    func testBrandNamePerLanguage() {
        XCTAssertEqual(AppLanguage.chinese.brandName, "守灯")
        XCTAssertEqual(AppLanguage.traditionalChinese.brandName, "守燈")
        XCTAssertEqual(AppLanguage.english.brandName, "Lantern Care")
    }
}

final class LanguageChoiceTests: XCTestCase {
    func testExplicitChoiceIsNotOverriddenByPhoneCountry() {
        let lm = LanguageManager.shared
        let key = "app_language_user_chosen"
        let original = lm.current
        let hadChoice = UserDefaults.standard.object(forKey: key)
        defer {
            if let hadChoice { UserDefaults.standard.set(hadChoice, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            lm.current = original
        }
        UserDefaults.standard.removeObject(forKey: key)
        lm.suggest(.english)                  // +1 number, no choice yet → follows the country
        XCTAssertEqual(lm.current, .english)
        lm.choose(.traditionalChinese)        // person taps 繁
        lm.suggest(.english)                  // screen rebuilt / country re-applied
        XCTAssertEqual(lm.current, .traditionalChinese)
    }
}

/// Japanese for the Japan market.
final class JapaneseTests: XCTestCase {

    func testJapaneseIsDetectedFromSystemLanguage() {
        for preferred in ["ja", "ja-JP", "ja-Jpan-JP"] {
            XCTAssertEqual(LanguageManager.detectLanguage(preferred: preferred), .japanese, preferred)
        }
    }

    func testJapaneseTableIsMostlyJapanese() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                  inDirectory: nil, forLocalization: "ja"))
        let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        // Kana or kanji; the rest are brand names, "OK", "SOS", numbers
        let japanese = table.values.filter {
            $0.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
        }
        XCTAssertGreaterThan(Double(japanese.count) / Double(table.count), 0.95)
    }

    func testVoiceSOSListensInTheAppLanguage() {
        XCTAssertEqual(VoiceCommandService.recognitionLocale(for: .japanese).identifier, "ja-JP")
        XCTAssertEqual(VoiceCommandService.recognitionLocale(for: .english).identifier, "en-US")
        XCTAssertEqual(VoiceCommandService.recognitionLocale(for: .traditionalChinese).identifier, "zh-TW")
    }

    func testOnboardingDisclaimerNamesJapaneseNumbers() {
        let screens = DisclaimerCopy.Onboarding.screens(for: .japanese)
        XCTAssertEqual(screens.count, 3)
        XCTAssertTrue(screens[0].body.contains("119"))
    }
}

/// Keys built at runtime (`localized("prefix.\(value)")`) are invisible to the
/// literal-key scan above; a mismatch shows the raw key on screen (the guardian
/// Records tabs showed "guardian.records.tab.timeline").
final class DynamicLocalizationKeyTests: XCTestCase {
    func testEveryRuntimeBuiltKeyExistsInEveryLanguage() throws {
        var keys: [String] = []
        keys += ["timeline", "schedule", "contacts"].map { "guardian.records.tab.\($0)" }
        keys += ["primary", "backup", "observer"].map { "member.role.\($0)" }
        keys += ["active", "pending", "declined"].map { "member.status.\($0)" }
        keys += ["sms", "wechat", "link"].map { "invite.method.\($0)" }
        keys += ["walking", "cycling", "driving", "transit"].map { "map.route.\($0)" }
        keys += ["walking", "cycling", "driving", "flying", "stationary", "unknown", "running"].map { "trip.mode.\($0)" }
        keys += ["offlineMaps", "findMy", "satelliteSOS", "carrierSatellite"].flatMap { ["preflight.\($0).title", "preflight.\($0).detail"] }
        keys += ["standard", "large", "extraLarge", "huge"].map { "fontScale.\($0)" }
        // In-app tips (read through AppTips.text, which the literal scan does not see)
        keys += ["sos", "homeSafe", "inviteGuardian", "memberCard", "statusBar", "inviteCode"]
            .flatMap { ["tip.\($0).title", "tip.\($0).message"] } + ["tip.inviteGuardian.action"]
        keys += ["section", "show", "reset", "resetDone"].map { "settings.tips.\($0)" }
        for language in ["en", "zh-Hans", "zh-Hant", "fr", "ja"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                                      inDirectory: nil, forLocalization: language), language)
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], language)
            let missing = keys.filter { table[$0]?.isEmpty ?? true }
            XCTAssertEqual(missing, [], language)
        }
    }
}
