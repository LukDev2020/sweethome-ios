import XCTest
@testable import ShouDeng

final class DutySchedulerTests: XCTestCase {

    private var scheduler: DutyScheduler!

    override func setUp() {
        super.setUp()
        scheduler = DutyScheduler()
    }

    override func tearDown() {
        scheduler = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeUser(
        id: String,
        name: String,
        timeZone: TimeZone = .current
    ) -> User {
        User(
            id: id,
            displayName: name,
            role: .guardian,
            avatarInitial: String(name.prefix(1)),
            timeZone: timeZone,
            countryCode: "CN",
            cityName: "Beijing",
            createdAt: Date()
        )
    }

    private func makeGuardian(
        id: String,
        name: String,
        timeZone: TimeZone = .current,
        isOnDuty: Bool = false,
        dutySchedule: DutySchedule? = nil,
        avgResponseTime: TimeInterval = 60
    ) -> Guardian {
        Guardian(
            id: id,
            user: makeUser(id: id, name: name, timeZone: timeZone),
            permissions: .defaultPermissions,
            isOnDuty: isOnDuty,
            dutySchedule: dutySchedule,
            averageResponseTime: avgResponseTime,
            linkedSince: Date()
        )
    }

    private func makeProtectedPerson(timeZone: TimeZone = .current) -> ProtectedPerson {
        ProtectedPerson(
            id: "pp-1",
            user: User(
                id: "pp-1",
                displayName: "XiaoYu",
                role: .protected_,
                avatarInitial: "X",
                timeZone: timeZone,
                countryCode: "UA",
                cityName: "Kyiv",
                createdAt: Date()
            ),
            guardians: [],
            protectionLayers: 1,
            lastCheckIn: Date(),
            lastKnownLocation: nil,
            batteryLevel: 0.8,
            batteryState: .unplugged,
            lastPhoneActivity: Date(),
            status: .normal
        )
    }

    // MARK: - Config Defaults

    func testDefaultAwakeHours() {
        let config = DutyScheduler.Config()
        XCTAssertEqual(config.defaultAwakeHours, 7...23)
    }

    func testDefaultHandoffReminderMinutes() {
        let config = DutyScheduler.Config()
        XCTAssertEqual(config.handoffReminderMinutesBefore, 15)
    }

    // MARK: - Coverage Map

    func testCoverageMapHas24Slots() {
        let person = makeProtectedPerson()
        let guardian = makeGuardian(id: "g-1", name: "Mom")
        let coverage = scheduler.buildDayCoverage(
            protectedPerson: person,
            guardians: [guardian]
        )

        XCTAssertEqual(coverage.slots.count, 24)
    }

    func testCoverageMapWithNoGuardiansAllGaps() {
        let person = makeProtectedPerson()
        let coverage = scheduler.buildDayCoverage(
            protectedPerson: person,
            guardians: []
        )

        XCTAssertEqual(coverage.totalGapHours, 24)
        XCTAssertEqual(coverage.totalCoveredHours, 0)
        XCTAssertEqual(coverage.coveragePercentage, 0)
    }

    func testCoverageMapWithOneGuardianSameTimezone() {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        let person = makeProtectedPerson(timeZone: tz)
        let guardian = makeGuardian(id: "g-1", name: "Mom", timeZone: tz)

        let coverage = scheduler.buildDayCoverage(
            protectedPerson: person,
            guardians: [guardian]
        )

        // Guardian covers awake hours (7-23) = 17 hours
        XCTAssertEqual(coverage.totalCoveredHours, 17)
        XCTAssertEqual(coverage.totalGapHours, 7)
    }

    func testCoveragePercentageCalculation() {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        let person = makeProtectedPerson(timeZone: tz)
        let guardian = makeGuardian(id: "g-1", name: "Mom", timeZone: tz)

        let coverage = scheduler.buildDayCoverage(
            protectedPerson: person,
            guardians: [guardian]
        )

        let expected = Double(coverage.totalCoveredHours) / 24.0
        XCTAssertEqual(coverage.coveragePercentage, expected, accuracy: 0.001)
    }

    // MARK: - Cross-Timezone Coverage

    func testCrossTimezoneFillsMoreHours() {
        let shanghaiTZ = TimeZone(identifier: "Asia/Shanghai")!   // UTC+8
        let torontoTZ = TimeZone(identifier: "America/Toronto")!  // UTC-5

        let person = makeProtectedPerson(timeZone: shanghaiTZ)

        let guardianShanghai = makeGuardian(id: "g-1", name: "Mom", timeZone: shanghaiTZ)
        let guardianToronto = makeGuardian(id: "g-2", name: "Uncle", timeZone: torontoTZ)

        let coverageSingle = scheduler.buildDayCoverage(
            protectedPerson: person,
            guardians: [guardianShanghai]
        )

        let coverageDual = scheduler.buildDayCoverage(
            protectedPerson: person,
            guardians: [guardianShanghai, guardianToronto]
        )

        XCTAssertGreaterThanOrEqual(
            coverageDual.totalCoveredHours,
            coverageSingle.totalCoveredHours,
            "Adding a guardian in another timezone should cover more hours"
        )
    }

    // MARK: - Gap Detection

    func testGapDetectionFindsNightGap() {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        let person = makeProtectedPerson(timeZone: tz)
        let guardian = makeGuardian(id: "g-1", name: "Mom", timeZone: tz)

        let coverage = scheduler.buildDayCoverage(
            protectedPerson: person,
            guardians: [guardian]
        )

        // Should have gap during sleep hours (0-6)
        XCTAssertFalse(coverage.gaps.isEmpty, "Should detect at least one gap during night hours")
    }

    func testGapCallback() {
        var detectedGaps: [DutyScheduler.GapInfo] = []
        scheduler.onGapDetected = { gap in
            detectedGaps.append(gap)
        }

        let tz = TimeZone(identifier: "Asia/Shanghai")!
        let person = makeProtectedPerson(timeZone: tz)

        _ = scheduler.buildDayCoverage(
            protectedPerson: person,
            guardians: [] // No guardians = all gaps
        )

        XCTAssertFalse(detectedGaps.isEmpty)
    }

    // MARK: - Duty Schedule Slots

    func testGuardianWithExplicitDutySlots() {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        let person = makeProtectedPerson(timeZone: tz)

        let schedule = DutySchedule(
            guardianId: "g-1",
            slots: [
                DutySlot(startHour: 22, endHour: 6, dayOfWeek: [], isConfirmed: true),
            ]
        )
        let guardian = makeGuardian(
            id: "g-1", name: "Night Owl", timeZone: tz,
            dutySchedule: schedule
        )

        let coverage = scheduler.buildDayCoverage(
            protectedPerson: person,
            guardians: [guardian]
        )

        // Hours 22-23 and 0-5 should be covered (8 hours)
        let coveredHours = coverage.slots.enumerated()
            .filter { !$0.element.isGap }
            .map { $0.offset }

        XCTAssertTrue(coveredHours.contains(22))
        XCTAssertTrue(coveredHours.contains(23))
        XCTAssertTrue(coveredHours.contains(0))
        XCTAssertTrue(coveredHours.contains(3))
    }

    // MARK: - Sort By Responsiveness

    func testSortByResponsivenessPreferOnDuty() {
        let tz = TimeZone.current
        let onDuty = makeGuardian(id: "g-1", name: "OnDuty", timeZone: tz, isOnDuty: true)
        let offDuty = makeGuardian(id: "g-2", name: "OffDuty", timeZone: tz, isOnDuty: false)

        let sorted = scheduler.sortByResponsiveness(
            guardians: [offDuty, onDuty],
            protectedTimeZone: tz
        )

        XCTAssertEqual(sorted.first?.id, "g-1", "On-duty guardian should be first")
    }

    func testSortByResponsivenessPreferFastResponder() {
        let tz = TimeZone.current
        let slow = makeGuardian(id: "g-slow", name: "Slow", timeZone: tz, avgResponseTime: 300)
        let fast = makeGuardian(id: "g-fast", name: "Fast", timeZone: tz, avgResponseTime: 10)

        let sorted = scheduler.sortByResponsiveness(
            guardians: [slow, fast],
            protectedTimeZone: tz
        )

        XCTAssertEqual(sorted.first?.id, "g-fast", "Faster responder should rank higher")
    }

    // MARK: - Coverage Slot

    func testCoverageSlotIsGapWhenEmpty() {
        let slot = DutyScheduler.CoverageSlot(hour: 3, coveredBy: [])
        XCTAssertTrue(slot.isGap)
    }

    func testCoverageSlotIsNotGapWhenCovered() {
        let coverage = DutyScheduler.GuardianCoverage(
            guardianId: "g-1",
            guardianName: "Mom",
            guardianTimeZone: .current,
            localHour: 10,
            isAwakeHour: true,
            isConfirmed: true
        )
        let slot = DutyScheduler.CoverageSlot(hour: 10, coveredBy: [coverage])
        XCTAssertFalse(slot.isGap)
    }

    // MARK: - Handoffs

    func testTodayHandoffsDetectsTransition() {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        let person = makeProtectedPerson(timeZone: tz)

        // Two guardians with explicit non-overlapping duty
        let scheduleA = DutySchedule(guardianId: "g-1", slots: [
            DutySlot(startHour: 8, endHour: 16, dayOfWeek: [], isConfirmed: true),
        ])
        let scheduleB = DutySchedule(guardianId: "g-2", slots: [
            DutySlot(startHour: 16, endHour: 23, dayOfWeek: [], isConfirmed: true),
        ])

        let guardianA = makeGuardian(id: "g-1", name: "Morning", timeZone: tz, dutySchedule: scheduleA)
        let guardianB = makeGuardian(id: "g-2", name: "Evening", timeZone: tz, dutySchedule: scheduleB)

        let coverage = scheduler.buildDayCoverage(
            protectedPerson: person,
            guardians: [guardianA, guardianB]
        )

        let handoffs = scheduler.todayHandoffs(coverage: coverage)

        // At least one handoff at hour 16 when Morning → Evening
        XCTAssertFalse(handoffs.isEmpty, "Should detect handoff between shifts")
    }
}
