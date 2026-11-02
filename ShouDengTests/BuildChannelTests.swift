import XCTest
@testable import ShouDeng

/// Builds without BETA (Debug, Release = App Store) must never simulate SOS, even if the
/// TestFlight "real SOS" preference is missing or off. docs/ops/RELEASE.md
final class BuildChannelTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: BuildChannel.realSOSKey)
        super.tearDown()
    }

    func testNonBetaBuildNeverSimulatesSOS() throws {
        #if BETA
        throw XCTSkip("Beta configuration")
        #else
        XCTAssertFalse(BuildChannel.isBetaBuild)
        XCTAssertFalse(BuildChannel.shared.betaFeaturesActive)
        UserDefaults.standard.set(false, forKey: BuildChannel.realSOSKey)
        XCTAssertFalse(BuildChannel.shared.simulatesSOS)
        UserDefaults.standard.removeObject(forKey: BuildChannel.realSOSKey)
        XCTAssertFalse(BuildChannel.shared.simulatesSOS)
        #endif
    }

    func testRefreshingTheInstallEnvironmentIsANoOpOutsideBeta() async {
        await BuildChannel.shared.refreshInstallEnvironment()
        XCTAssertFalse(BuildChannel.shared.isAppStoreInstall)
    }
}
