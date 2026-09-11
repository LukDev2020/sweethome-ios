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
