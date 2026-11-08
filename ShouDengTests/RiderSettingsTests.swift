import XCTest
@testable import ShouDeng

/// Settings → Rider: defaults keep the old behaviour, guardrails hold, and the
/// settings reach the SOS countdown, the lock-screen card and crash reports.
@MainActor
final class RiderSettingsTests: XCTestCase {

    func testDefaultsKeepTheOldBehaviour() {
        let s = RiderSettings()
        XCTAssertEqual(s.cancelWindow(for: .longPress), 5)
        XCTAssertEqual(s.cancelWindow(for: .bluetoothButton), 5)
        XCTAssertNil(s.cancelWindow(for: .fallDetection), "not a rider setting")
        XCTAssertEqual(s.graceMinutes, 30)
        XCTAssertEqual(s.lockButtons, [.ok, .report])
        XCTAssertEqual(s.offShiftAlerts, "none")
        XCTAssertEqual(s.stillOkEveryMin, 0)
    }

    func testScreenHoldNeverGoesUnderThreeSeconds() {
        var s = RiderSettings()
        s.screenCountdown = 0
        s.handlebarCountdown = 0
        s = s.sanitized()
        XCTAssertEqual(s.cancelWindow(for: .longPress), 3)
        XCTAssertEqual(s.cancelWindow(for: .widgetTap), 3)
        XCTAssertEqual(s.cancelWindow(for: .bluetoothButton), 0, "only the handlebar button may send at once")
        s.handlebarCountdown = 9
        XCTAssertEqual(s.sanitized().handlebarCountdown, 5)
    }

    func testLockCardAlwaysHasTwoDistinctButtonsBesideSOS() {
        var s = RiderSettings()
        s.lockButtons = []
        XCTAssertEqual(s.sanitized().lockButtons, [.ok, .report])
        s.lockButtons = [.crash, .crash, .location, .ok]
        XCTAssertEqual(s.sanitized().lockButtons, [.crash, .location])
        // The widget's own fallback agrees
        XCTAssertEqual(RiderLockScreenCard.chosenButtons(["crash", "bogus"]), ["crash", "ok"])
        XCTAssertEqual(RiderLockScreenCard.chosenButtons(nil), ["ok", "report"])
    }

    func testOutOfRangeValuesFallBack() {
        var s = RiderSettings()
        s.offShiftAlerts = "sometimes"
        s.alertRadiusKm = 7
        s.graceMinutes = 0
        s.stillOkEveryMin = 45
        s.cautionHours = 100
        s.customReports = ["  Aggressive customer ", "", "a", "b", "c", "d", "e"]
        let t = s.sanitized()
        XCTAssertEqual(t.offShiftAlerts, "none")
        XCTAssertEqual(t.alertRadiusKm, 3)
        XCTAssertEqual(t.graceMinutes, 30, "the late-shift alert can't be switched off")
        XCTAssertEqual(t.stillOkEveryMin, 0)
        XCTAssertEqual(t.cautionHours, 12)
        XCTAssertEqual(t.customReports, ["Aggressive customer", "a", "b", "c", "d"])
    }

    func testOldSavedSettingsDecodeWithDefaultsForNewFields() throws {
        let old = #"{"vehicle":"motorbike","graceMinutes":60}"#
        let s = try JSONDecoder().decode(RiderSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.vehicle, .motorbike)
        XCTAssertEqual(s.graceMinutes, 60)
        XCTAssertEqual(s.lockButtons, [.ok, .report])
        XCTAssertEqual(s.screenCountdown, 5)
    }

    func testTemplateEndIsTomorrowWhenItHasPassed() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 23, minute: 0))!
        let t = ShiftTemplate(name: "Late", startHour: 21, startMinute: 0, endHour: 1, endMinute: 30, weekdays: [], watcherIds: [], remind: false)
        let end = t.plannedEnd(from: now, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.day, .hour, .minute], from: end), DateComponents(day: 8, hour: 1, minute: 30))
        XCTAssertEqual(t.timeRange, "21:00–01:30")
    }

    func testCrashLinkAndTriggerNeedNoCountdown() {
        XCTAssertEqual(AppCoordinator.sosCancelWindow(for: .crashReport), 0)
        XCTAssertFalse(SOSTriggerMethod.crashReport.isSilent)
    }

    // MARK: On a real (demo) coordinator

    func testRiderSettingsReachTheCountdownAndTheCard() async throws {
        ExploreModeController.shared.exit()
        ExploreModeController.shared.start(role: .kai)
        defer { ExploreModeController.shared.exit() }
        let demo = try XCTUnwrap(ExploreModeController.shared.coordinator)
        let deadline = Date().addingTimeInterval(10)
        while demo.currentUser?.id != DemoDataset.kaiId && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(demo.isRiderMode)

        demo.updateRiderSettings {
            $0.handlebarCountdown = 2
            $0.lockButtons = [.crash, .location]
            $0.vehicle = .scooter
            $0.showWatchers = true
        }
        demo.requestSOS(method: .bluetoothButton)
        XCTAssertEqual(demo.pendingSOS?.duration, 2)
        demo.cancelPendingSOS()

        let card = try XCTUnwrap(demo.riderCardInfo)
        XCTAssertEqual(card.buttons, ["crash", "location"])
        XCTAssertEqual(card.vehicleSymbol, RiderVehicle.scooter.symbol)
        XCTAssertNotNil(card.watcherNames)
    }

    func testHurtCrashSendsAnSOSAtOnce() async throws {
        ExploreModeController.shared.exit()
        ExploreModeController.shared.start(role: .kai)
        defer { ExploreModeController.shared.exit() }
        let demo = try XCTUnwrap(ExploreModeController.shared.coordinator)
        let deadline = Date().addingTimeInterval(10)
        while demo.currentUser?.id != DemoDataset.kaiId && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }

        await demo.reportCrash(hurt: true, note: nil, notifyCrew: true)
        XCTAssertEqual(demo.activeSOSEvent?.triggerMethod, .crashReport)
        XCTAssertNil(demo.pendingSOS, "no countdown: they said they're hurt")
        XCTAssertEqual(demo.timeline.first?.type, .crashReported)
    }
}
