import XCTest
@testable import ShouDeng

final class EscalationEngineTests: XCTestCase {

    private var engine: EscalationEngine!

    override func setUp() {
        super.setUp()
        engine = EscalationEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialSessionIsNil() {
        XCTAssertNil(engine.activeSession)
    }

    // MARK: - Freeze

    func testFreezeWithoutSessionIsNoOp() {
        engine.freeze(by: "guardian-123")
        XCTAssertNil(engine.activeSession)
    }

    // MARK: - Resolve

    func testResolveWithoutSessionIsNoOp() {
        engine.resolve(by: "user-123", resolution: .protectedCancelled)
        XCTAssertNil(engine.activeSession)
    }

    // MARK: - Resolution Types

    func testAllResolutionTypesExist() {
        let resolutions: [SOSResolution] = [
            .guardianConfirmedSafe,
            .protectedCancelled,
            .falseAlarm,
        ]
        XCTAssertEqual(resolutions.count, 3)
    }

    // MARK: - Callbacks

    func testNotificationCallbackConfigurable() {
        engine.onSendNotification = { _ in }
        XCTAssertNotNil(engine.onSendNotification)
    }

    func testFreezeCallbackConfigurable() {
        engine.onEscalationFrozen = { _, _ in }
        XCTAssertNotNil(engine.onEscalationFrozen)
    }

    func testVoiceCallCallbackConfigurable() {
        engine.onInitiateVoiceCall = { _, _ in }
        XCTAssertNotNil(engine.onInitiateVoiceCall)
    }

    // MARK: - Session Model

    func testSessionStartsUnfrozen() {
        let session = EscalationEngine.Session(
            id: "test-session",
            sosEvent: makeTestSOSEvent(),
            startedAt: Date()
        )

        XCTAssertEqual(session.id, "test-session")
        XCTAssertFalse(session.isFrozen)
        XCTAssertNil(session.frozenBy)
        XCTAssertFalse(session.isResolved)
        XCTAssertEqual(session.currentHop, 1)
    }

    // MARK: - Helpers

    private func makeTestSOSEvent() -> SOSEvent {
        SOSEvent(
            id: "sos-1",
            protectedPersonId: "person-1",
            triggeredAt: Date(),
            triggerMethod: .longPress,
            location: nil,
            batteryLevel: 0.8,
            escalationState: .initiated,
            resolvedAt: nil,
            resolvedBy: nil,
            resolution: nil
        )
    }
}

// MARK: - Critical Alerts entitlement claims

/// Verifies the behaviour promised in the Critical Alerts entitlement request:
/// manual SOS has a cancel window, duress / pre-confirmed SOS skip it, a
/// cancelled countdown never sends, and the guardian's consent is sent to the
/// server.
@MainActor
final class CriticalAlertClaimsTests: XCTestCase {

    func testManualTriggersHaveFiveSecondCancelWindow() {
        for method in [SOSTriggerMethod.longPress, .widgetTap, .bluetoothButton, .watchQuickAction] {
            XCTAssertEqual(AppCoordinator.sosCancelWindow(for: method), 5, "\(method)")
        }
    }

    func testDuressAndAlreadyConfirmedTriggersSkipTheWindow() {
        // Duress must stay instant and silent; fall / voice / distress sound /
        // safety timer already had their own countdown before reaching here.
        for method in [SOSTriggerMethod.duressPassword, .fallDetection, .voiceWakeWord, .audioDistress, .voiceCommand, .deadManSwitch, .crashReport] {
            XCTAssertEqual(AppCoordinator.sosCancelWindow(for: method), 0, "\(method)")
        }
    }

    func testManualSOSStartsCountdownInsteadOfSending() {
        let coordinator = AppCoordinator()
        coordinator.requestSOS(method: .longPress)
        XCTAssertNotNil(coordinator.pendingSOS)
        XCTAssertEqual(coordinator.pendingSOS?.duration, 5)
        XCTAssertNil(coordinator.activeSOSEvent, "Nothing may be sent during the cancel window")
        coordinator.cancelPendingSOS()
    }

    /// TestFlight build 33: an SOS left active on the phone made every press of the
    /// SOS button do nothing. A press now opens the running SOS instead.
    func testPressingSOSWhileOneIsActiveShowsIt() {
        let coordinator = AppCoordinator()
        coordinator.activeSOSEvent = SOSEvent(id: "old", protectedPersonId: "me", triggeredAt: Date().addingTimeInterval(-3600),
                                              triggerMethod: .longPress, location: nil, batteryLevel: nil,
                                              escalationState: .initiated, resolvedAt: nil, resolvedBy: nil, resolution: nil)
        coordinator.isSOSScreenPresented = false
        coordinator.requestSOS(method: .longPress)
        XCTAssertTrue(coordinator.isSOSScreenPresented, "the running SOS is shown")
        XCTAssertNil(coordinator.pendingSOS, "no second SOS on top of the running one")
        coordinator.activeSOSEvent = nil
    }

    func testDuressSOSDoesNotShowACountdown() {
        let coordinator = AppCoordinator()
        coordinator.requestSOS(method: .duressPassword)
        XCTAssertNil(coordinator.pendingSOS, "Duress SOS must not show an on-screen countdown")
    }

    func testCancelledCountdownNeverSends() async throws {
        let coordinator = AppCoordinator()
        coordinator.requestSOS(method: .widgetTap)
        coordinator.cancelPendingSOS()
        XCTAssertNil(coordinator.pendingSOS)

        try await Task.sleep(nanoseconds: 6_000_000_000) // past the 5 s window
        XCTAssertNil(coordinator.activeSOSEvent, "A cancelled SOS must never be sent")
        XCTAssertNil(coordinator.pendingSOS)
    }

    func testCountdownHandsOffToSendWhenItEnds() async throws {
        // No signed-in user, so triggerSOS stops before any network call; this
        // checks the countdown completes and clears itself after 5 s.
        let coordinator = AppCoordinator()
        coordinator.requestSOS(method: .bluetoothButton)
        XCTAssertNotNil(coordinator.pendingSOS)

        try await Task.sleep(nanoseconds: 4_000_000_000)
        XCTAssertNotNil(coordinator.pendingSOS, "Still counting down at 4 s")
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertNil(coordinator.pendingSOS)
    }

    func testSecondTriggerDuringCountdownIsIgnored() {
        let coordinator = AppCoordinator()
        coordinator.requestSOS(method: .longPress)
        let first = coordinator.pendingSOS
        coordinator.requestSOS(method: .widgetTap)
        XCTAssertEqual(coordinator.pendingSOS, first)
        coordinator.cancelPendingSOS()
    }

    func testInviteAcceptSendsGuardianConsent() throws {
        let data = try JSONEncoder().encode(AcceptInviteRequest(code: "ABC123", criticalAlertConsent: true))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["criticalAlertConsent"] as? Bool, true)
    }

    func testNotificationPrefsSendCriticalAlertChoice() throws {
        let prefs = NotificationPrefsRequest(sosAlerts: true, sosCriticalAlerts: false,
                                             checkinReminder: true, checkinOverdue: true, familyFeed: true)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(prefs)) as? [String: Any])
        XCTAssertEqual(json["sosCriticalAlerts"] as? Bool, false)
    }
}
