import Foundation

// MARK: - Cross-Timezone Duty Scheduler
//
// The killer feature competitors don't have.
//
// When a family is spread across Toronto (UTC-5), Kyiv (UTC+2), and Sydney (UTC+11),
// there's almost always someone awake. This scheduler:
//   1. Builds a 24-hour coverage bar for the protected person's timezone
//   2. Detects gaps where no guardian is available
//   3. Routes gaps to the response center (paid tier)
//   4. Sends handoff reminders before shift changes
//   5. Adjusts for DST automatically

final class DutyScheduler {

    // MARK: - Coverage Map

    /// One hour-slot in the protected person's day
    struct CoverageSlot {
        let hour: Int                      // 0-23 in protected person's local time
        var coveredBy: [GuardianCoverage]  // Who's covering this hour
        var isGap: Bool { coveredBy.isEmpty }
    }

    struct GuardianCoverage {
        let guardianId: String
        let guardianName: String
        let guardianTimeZone: TimeZone
        let localHour: Int                 // What hour it is for the guardian
        let isAwakeHour: Bool              // Based on guardian's typical waking hours
        let isConfirmed: Bool              // Guardian confirmed this slot
    }

    struct DayCoverage {
        let protectedPersonId: String
        let date: Date
        let timeZone: TimeZone             // Protected person's time zone
        let slots: [CoverageSlot]          // 24 slots, one per hour
        let gaps: [GapInfo]
        let totalCoveredHours: Int
        let totalGapHours: Int

        var coveragePercentage: Double {
            Double(totalCoveredHours) / 24.0
        }
    }

    struct GapInfo {
        let startHour: Int
        let endHour: Int
        let durationHours: Int
        let routedToResponseCenter: Bool
    }

    // MARK: - Configuration

    struct Config {
        var defaultAwakeHours: ClosedRange<Int> = 7...23  // 7 AM to 11 PM
        var handoffReminderMinutesBefore: Int = 15
        var autoRouteGapsToResponseCenter: Bool = true
    }

    // MARK: - Properties

    private let config: Config
    var onHandoffReminder: ((String, String, Int) -> Void)?  // (outgoing guardian, incoming guardian, minutes)
    var onGapDetected: ((GapInfo) -> Void)?

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Build Coverage Map

    func buildDayCoverage(
        protectedPerson: ProtectedPerson,
        guardians: [Guardian],
        date: Date = Date()
    ) -> DayCoverage {

        let protectedTZ = protectedPerson.user.timeZone
        let calendar = Calendar.current

        var slots: [CoverageSlot] = (0..<24).map { CoverageSlot(hour: $0, coveredBy: []) }

        for guardian in guardians {
            let guardianTZ = guardian.user.timeZone

            // Option A: Guardian has explicit duty slots
            if let schedule = guardian.dutySchedule {
                for dutySlot in schedule.slots {
                    // Check if this duty slot applies to today
                    let dayOfWeek = calendar.component(.weekday, from: date)
                    if !dutySlot.dayOfWeek.isEmpty && !dutySlot.dayOfWeek.contains(dayOfWeek) {
                        continue
                    }

                    let start = dutySlot.startHour
                    let end = dutySlot.endHour

                    let hours: [Int]
                    if start < end {
                        hours = Array(start..<end)
                    } else {
                        // Wraps midnight
                        hours = Array(start..<24) + Array(0..<end)
                    }

                    for hour in hours {
                        let guardianLocalHour = convertHour(
                            hour,
                            from: protectedTZ,
                            to: guardianTZ,
                            on: date
                        )

                        slots[hour].coveredBy.append(GuardianCoverage(
                            guardianId: guardian.id,
                            guardianName: guardian.user.displayName,
                            guardianTimeZone: guardianTZ,
                            localHour: guardianLocalHour,
                            isAwakeHour: config.defaultAwakeHours.contains(guardianLocalHour),
                            isConfirmed: dutySlot.isConfirmed
                        ))
                    }
                }
            }
            // Option B: No explicit schedule — use awake hours
            else {
                for protectedHour in 0..<24 {
                    let guardianLocalHour = convertHour(
                        protectedHour,
                        from: protectedTZ,
                        to: guardianTZ,
                        on: date
                    )

                    if config.defaultAwakeHours.contains(guardianLocalHour) {
                        slots[protectedHour].coveredBy.append(GuardianCoverage(
                            guardianId: guardian.id,
                            guardianName: guardian.user.displayName,
                            guardianTimeZone: guardianTZ,
                            localHour: guardianLocalHour,
                            isAwakeHour: true,
                            isConfirmed: false
                        ))
                    }
                }
            }
        }

        // Detect gaps
        let gaps = detectGaps(slots: slots)

        let totalCovered = slots.filter { !$0.isGap }.count
        let totalGaps = slots.filter { $0.isGap }.count

        return DayCoverage(
            protectedPersonId: protectedPerson.id,
            date: date,
            timeZone: protectedTZ,
            slots: slots,
            gaps: gaps,
            totalCoveredHours: totalCovered,
            totalGapHours: totalGaps
        )
    }

    // MARK: - Gap Detection

    private func detectGaps(slots: [CoverageSlot]) -> [GapInfo] {
        var gaps: [GapInfo] = []
        var gapStart: Int?

        for i in 0..<24 {
            if slots[i].isGap {
                if gapStart == nil {
                    gapStart = i
                }
            } else if let start = gapStart {
                let gap = GapInfo(
                    startHour: start,
                    endHour: i,
                    durationHours: i - start,
                    routedToResponseCenter: config.autoRouteGapsToResponseCenter
                )
                gaps.append(gap)
                onGapDetected?(gap)
                gapStart = nil
            }
        }

        // Handle gap that wraps around midnight
        if let start = gapStart {
            let gap = GapInfo(
                startHour: start,
                endHour: 24,
                durationHours: 24 - start,
                routedToResponseCenter: config.autoRouteGapsToResponseCenter
            )
            gaps.append(gap)
            onGapDetected?(gap)
        }

        return gaps
    }

    // MARK: - Determine Current On-Duty Guardian

    func currentOnDutyGuardian(
        coverage: DayCoverage
    ) -> GuardianCoverage? {
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: coverage.timeZone, from: Date())
        let currentHour = components.hour ?? 12

        guard currentHour >= 0 && currentHour < 24 else { return nil }
        let slot = coverage.slots[currentHour]

        // Prefer confirmed guardians, then anyone covering this hour
        return slot.coveredBy.first { $0.isConfirmed }
            ?? slot.coveredBy.first
    }

    // MARK: - Handoff Schedule

    struct HandoffEvent {
        let time: Date                      // When the handoff happens
        let outgoingGuardianId: String?
        let outgoingGuardianName: String?
        let incomingGuardianId: String
        let incomingGuardianName: String
        let protectedPersonTimeZone: TimeZone
    }

    func todayHandoffs(coverage: DayCoverage) -> [HandoffEvent] {
        var handoffs: [HandoffEvent] = []
        let calendar = Calendar.current

        var previousGuardianId: String? = coverage.slots[23].coveredBy.first?.guardianId

        for hour in 0..<24 {
            let slot = coverage.slots[hour]
            let currentGuardianId = slot.coveredBy.first?.guardianId

            if currentGuardianId != previousGuardianId, let newGuardian = slot.coveredBy.first {
                var components = calendar.dateComponents(in: coverage.timeZone, from: coverage.date)
                components.hour = hour
                components.minute = 0

                if let handoffTime = calendar.date(from: components) {
                    let previousName = coverage.slots[max(0, hour - 1)].coveredBy.first?.guardianName

                    handoffs.append(HandoffEvent(
                        time: handoffTime,
                        outgoingGuardianId: previousGuardianId,
                        outgoingGuardianName: previousName,
                        incomingGuardianId: newGuardian.guardianId,
                        incomingGuardianName: newGuardian.guardianName,
                        protectedPersonTimeZone: coverage.timeZone
                    ))
                }
            }

            previousGuardianId = currentGuardianId
        }

        return handoffs
    }

    // MARK: - "Who's Awake Right Now" Sort

    /// Sorts guardians by "most likely to respond right now"
    /// Used for the contact list on the protected person's home screen
    func sortByResponsiveness(
        guardians: [Guardian],
        protectedTimeZone: TimeZone,
        at date: Date = Date()
    ) -> [Guardian] {

        return guardians.sorted { a, b in
            let scoreA = responsivenessScore(guardian: a, protectedTZ: protectedTimeZone, at: date)
            let scoreB = responsivenessScore(guardian: b, protectedTZ: protectedTimeZone, at: date)
            return scoreA > scoreB
        }
    }

    private func responsivenessScore(
        guardian: Guardian,
        protectedTZ: TimeZone,
        at date: Date
    ) -> Double {
        let calendar = Calendar.current
        let guardianComponents = calendar.dateComponents(in: guardian.user.timeZone, from: date)
        let guardianHour = guardianComponents.hour ?? 12

        var score: Double = 0

        // Is it a reasonable hour for the guardian?
        if config.defaultAwakeHours.contains(guardianHour) {
            score += 50
        }

        // Is the guardian on duty?
        if guardian.isOnDuty {
            score += 30
        }

        // Prefer faster historical responders
        if guardian.averageResponseTime > 0 {
            score += max(0, 20 - guardian.averageResponseTime / 10)
        }

        return score
    }

    // MARK: - Time Zone Conversion

    private func convertHour(
        _ hour: Int,
        from sourceTimeZone: TimeZone,
        to targetTimeZone: TimeZone,
        on date: Date
    ) -> Int {
        let calendar = Calendar.current

        // Build a date for the given hour in the source time zone
        var components = calendar.dateComponents(in: sourceTimeZone, from: date)
        components.hour = hour
        components.minute = 0
        components.second = 0

        guard let dateInSource = calendar.date(from: components) else { return hour }

        // Convert to target time zone
        let targetComponents = calendar.dateComponents(in: targetTimeZone, from: dateInSource)
        return targetComponents.hour ?? hour
    }
}
