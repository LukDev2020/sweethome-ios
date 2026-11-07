import XCTest
@testable import ShouDeng

/// The whole chain on a real coordinator (Explore Mode, so the SOS stays on the phone):
/// a recorded fall through the real detector → "Are you OK?" → SOS, or "I'm OK" → none.
/// The countdown must run on the clock — no sensor samples arrive after the fall here,
/// exactly like a phone whose screen locked.
@MainActor
final class FallChainTests: XCTestCase {

    private var demo: AppCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        ExploreModeController.shared.exit()
        AppCoordinator.autoSOSCountdown = 1.5
        ExploreModeController.shared.start(role: .mom)
        demo = try XCTUnwrap(ExploreModeController.shared.coordinator)
        await waitUntil { self.demo.currentUser?.id == DemoDataset.momId }
    }

    override func tearDown() async throws {
        AppCoordinator.autoSOSCountdown = 60
        ExploreModeController.shared.exit()
        demo = nil
        try await super.tearDown()
    }

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition(), "condition not met within \(timeout)s", file: file, line: line)
    }

    func testUnansweredFallSendsTheSOSOnTheClockAndReArms() async throws {
        demo.motionService.simulateFall(.forwardFall())
        await waitUntil { self.demo.autoSOSCheck != nil }
        let check = try XCTUnwrap(demo.autoSOSCheck)
        XCTAssertEqual(check.reason, .fall)
        XCTAssertFalse(check.isTest, "Explore Mode runs the real chain")
        XCTAssertTrue(demo.showFallConfirmation)
        XCTAssertGreaterThan(check.metrics?.peakImpactG ?? 0, 2.5)
        XCTAssertGreaterThan(check.metrics?.orientationChangeDeg ?? 0, 60)
        XCTAssertNil(demo.activeSOSEvent)

        // No more samples: the countdown alone sends it
        await waitUntil(5) { self.demo.activeSOSEvent != nil }
        XCTAssertEqual(demo.activeSOSEvent?.triggerMethod, .fallDetection)
        XCTAssertEqual(demo.activeSOSEvent?.clientSOSId, check.clientSOSId, "same id as the server's fallback")
        XCTAssertNil(demo.autoSOSCheck)
        XCTAssertFalse(demo.showFallConfirmation)

        // The detector watches again (it used to stay "confirmed" for good)
        await waitUntil { self.demo.motionService.fallDetectorState == .monitoring }
    }

    func testImOKSendsNothingAndReArms() async throws {
        demo.motionService.simulateFall(.forwardFall())
        await waitUntil { self.demo.autoSOSCheck != nil }
        demo.dismissFallConfirmation()
        XCTAssertNil(demo.autoSOSCheck)
        try? await Task.sleep(nanoseconds: 2_500_000_000)   // past the countdown
        XCTAssertNil(demo.activeSOSEvent, "I'm OK means no SOS")
        await waitUntil { self.demo.motionService.fallDetectorState == .monitoring }

        // A second fall is caught again
        demo.motionService.simulateFall(.forwardFall())
        await waitUntil { self.demo.autoSOSCheck != nil }
    }

    func testSendNowDoesNotWait() async throws {
        AppCoordinator.autoSOSCountdown = 60
        demo.motionService.simulateFall(.stairsFall())
        await waitUntil { self.demo.autoSOSCheck != nil }
        demo.autoSOSCheckExpired(byPerson: true)      // "I need help — send SOS now"
        XCTAssertEqual(demo.activeSOSEvent?.triggerMethod, .fallDetection)
    }

    func testEverydayMovementNeverAsks() async throws {
        for trace in [FallSensorTrace.running(), .jump(), .sitDownHard(), .fallThenGetUp(), .phoneDroppedAndPickedUp()] {
            demo.motionService.simulateFall(trace)
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertNil(demo.autoSOSCheck)
        XCTAssertNil(demo.activeSOSEvent)
    }

    func testOverdueCheckSendsWhenTheAppComesBack() async throws {
        AppCoordinator.autoSOSCountdown = 60
        demo.motionService.simulateFall(.forwardFall())
        await waitUntil { self.demo.autoSOSCheck != nil }
        // The app was suspended past the deadline: the work item never ran
        let check = try XCTUnwrap(demo.autoSOSCheck)
        demo.autoSOSWork?.cancel()
        demo.autoSOSCheck = AutoSOSCheck(reason: check.reason, startedAt: check.startedAt.addingTimeInterval(-120),
                                         deadline: Date().addingTimeInterval(-1), clientEventId: check.clientEventId,
                                         clientSOSId: check.clientSOSId, metrics: check.metrics, isTest: false)
        demo.resumeAutoSOSCheckIfOverdue()
        XCTAssertEqual(demo.activeSOSEvent?.triggerMethod, .fallDetection)
    }
}
