import XCTest
@testable import ShouDeng

/// First-launch disclaimers, Terms agreement, guardian duties and the consent upload.
final class DisclaimerTests: XCTestCase {

    /// The screens promised a 6-hour delay before sharing stops; the app stops it
    /// immediately. No language may say "6" hours again, and each says 4-hour pause.
    func testOnboardingMatchesTheApp() {
        for language in AppLanguage.allCases {
            let screens = DisclaimerCopy.Onboarding.screens(for: language)
            XCTAssertEqual(screens.map(\.id), ["onboard.not_emergency", "onboard.scope", "onboard.control"], "\(language)")
            let text = screens.map { $0.title + $0.body }.joined()
            XCTAssertFalse(text.contains("6 小时") || text.contains("6 小時") || text.contains("6-hour")
                           || text.contains("6 heures") || text.contains("6 時間"), "\(language) still promises a delay")
            XCTAssertTrue(text.contains("4"), "\(language) should name the 4-hour pause")
        }
        XCTAssertEqual(DisclaimerCopy.Onboarding.version, "v2.0")
    }

    func testComplianceGate() {
        let d = UserDefaults.standard
        let saved = (d.string(forKey: "terms_accepted_version"), d.string(forKey: "guardian_duty_version"))
        defer {
            d.set(saved.0, forKey: "terms_accepted_version")
            d.set(saved.1, forKey: "guardian_duty_version")
        }
        d.removeObject(forKey: "terms_accepted_version")
        d.removeObject(forKey: "guardian_duty_version")
        XCTAssertTrue(ComplianceGateView.isNeeded(role: .protected_, isDemo: false), "Terms not agreed")
        XCTAssertFalse(ComplianceGateView.isNeeded(role: .protected_, isDemo: true), "never in the demo")

        d.set(DisclaimerCopy.Terms.version, forKey: "terms_accepted_version")
        XCTAssertFalse(ComplianceGateView.isNeeded(role: .protected_, isDemo: false))
        XCTAssertTrue(ComplianceGateView.isNeeded(role: .guardian, isDemo: false), "guardian duties not confirmed")

        d.set(DisclaimerCopy.GuardianDuty.version, forKey: "guardian_duty_version")
        XCTAssertFalse(ComplianceGateView.isNeeded(role: .guardian, isDemo: false))

        d.set("2000-01-01", forKey: "terms_accepted_version")
        XCTAssertTrue(ComplianceGateView.isNeeded(role: .protected_, isDemo: false), "older Terms version")
        XCTAssertFalse(TermsAgreementRow.isAccepted)
    }

    func testConsentRecordsWaitForUpload() {
        let logger = ConsentLogger.shared
        logger.flush()
        let before = logger.pendingUpload()
        logger.markUploaded(upTo: before.total)
        XCTAssertTrue(logger.pendingUpload().records.isEmpty)

        logger.logTermsAccepted()
        logger.flush()
        let pending = logger.pendingUpload()
        XCTAssertEqual(pending.records.last?.item, DisclaimerCopy.Terms.consentKey)
        XCTAssertEqual(pending.records.last?.copyVersion, DisclaimerCopy.Terms.version)
        logger.markUploaded(upTo: pending.total)
        XCTAssertTrue(logger.pendingUpload().records.isEmpty)
    }

    /// While SMS and calls are off, nothing may describe a text or call as happening.
    func testNoTextOrCallPromisesWhilePhoneChannelsOff() throws {
        guard !DisclaimerCopy.EscalationChannels.phoneEnabled else { return }
        let bundle = Bundle(for: AppCoordinator.self)
        for lang in ["en", "zh-Hans", "zh-Hant", "fr", "ja"] {
            let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: lang))
            let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
            let tour = try XCTUnwrap(table["explore.tip.mom.sos.body"])
            for word in ["text", "SMS", "短信", "簡訊", "call", "电话", "電話"] {
                XCTAssertFalse(tour.contains(word), "\(lang) tour still mentions \(word): \(tour)")
            }
        }
    }
}
