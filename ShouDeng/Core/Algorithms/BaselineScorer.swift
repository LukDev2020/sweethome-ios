import Foundation

// MARK: - Missing Person Detection: Personal Baseline Anomaly Scoring
//
// Instead of fixed thresholds ("no check-in for 12 hours = alert"),
// we build a per-person behavioral baseline over 14+ days, then score
// deviation from that baseline using 5 weighted, explainable factors.
//
// The key insight: a night-shift nurse and a retired grandparent have
// completely different "normal". Fixed thresholds will either miss
// real emergencies or cry wolf constantly.
//
// Every alert comes with human-readable reasons:
//   "She usually checks in by 9am. It's now 2pm (5 hours late).
//    Her phone has been inactive for 7 hours."
//
// Explainable alerts get taken seriously. Black-box alerts get turned off.

final class BaselineScorer {

    // MARK: - Configuration

    struct Config {
        var baselineDaysRequired: Int = 14
        var baselineWindowDays: Int = 30       // Rolling window for baseline computation
        var yellowThreshold: Double = 0.45
        var redThreshold: Double = 0.70

        // Factor weights (must sum to 1.0)
        var weightCheckInOvertime: Double = 0.35
        var weightPhoneInactivity: Double = 0.25
        var weightLocationAnomaly: Double = 0.20
        var weightBatteryAnomaly: Double = 0.10
        var weightRegionalRisk: Double = 0.10
    }

    // MARK: - Baseline Data

    struct PersonBaseline {
        let personId: String
        var dataPoints: Int                     // Total data points collected
        var daysOfData: Int                     // Days with at least one data point
        var isReady: Bool { daysOfData >= 14 }

        // Check-in patterns
        var checkInTimes: [TimeOfDayBucket]     // When they usually check in
        var longestCheckInGap: TimeInterval     // Historical max gap between check-ins
        var averageCheckInGap: TimeInterval
        var checkInGapStdDev: TimeInterval

        // Phone activity patterns
        var activeHours: Set<Int>               // Hours (0-23) when phone is typically used
        var averageActivePeriodsPerDay: Double
        var longestInactivePeriod: TimeInterval

        // Location patterns
        var locationGrid: [GridCell: Double]    // Grid cell → frequency (0-1)
        var timeSlotLocations: [TimeSlot: [GridCell]]  // Time-of-day → usual locations

        // Battery patterns
        var averageBatteryAtCheckIn: Double
        var typicalChargingHours: Set<Int>

        var buildDate: Date
    }

    struct TimeOfDayBucket {
        let hour: Int      // 0-23
        let count: Int     // How many check-ins in this hour over baseline window
        let percentage: Double
    }

    struct GridCell: Hashable, Codable {
        let latBucket: Int    // latitude * 1000, rounded
        let lngBucket: Int    // longitude * 1000, rounded (~111m precision)

        init(latitude: Double, longitude: Double) {
            self.latBucket = Int((latitude * 1000).rounded())
            self.lngBucket = Int((longitude * 1000).rounded())
        }
    }

    enum TimeSlot: Int, CaseIterable {
        case earlyMorning = 0   // 05-08
        case morning = 1        // 08-12
        case afternoon = 2      // 12-17
        case evening = 3        // 17-21
        case night = 4          // 21-01
        case lateNight = 5      // 01-05

        static func from(hour: Int) -> TimeSlot {
            switch hour {
            case 5..<8: return .earlyMorning
            case 8..<12: return .morning
            case 12..<17: return .afternoon
            case 17..<21: return .evening
            case 21..<25: return .night  // 21-24
            default: return .lateNight   // 0-4
            }
        }
    }

    // MARK: - Risk Score Result

    struct RiskScore {
        let totalScore: Double              // 0.0 - 1.0
        let level: AlertLevel
        let factors: [RiskFactor]
        let humanReadableReasons: [String]  // The critical output
        let computedAt: Date
        let baselineReady: Bool

        var isYellow: Bool { totalScore > 0.45 }
        var isRed: Bool { totalScore > 0.70 }
    }

    struct RiskFactor {
        let name: String
        let weight: Double
        let rawValue: Double         // The measured value
        let baselineValue: Double    // What's "normal" for this person
        let deviationRatio: Double   // How far from normal (0 = normal, 1 = max deviation)
        let contribution: Double     // weight × deviationRatio
        let explanation: String      // Human-readable
    }

    // MARK: - Properties

    private let config: Config
    private var baselines: [String: PersonBaseline] = [:]

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Build Baseline from Historical Data

    func buildBaseline(
        personId: String,
        checkIns: [CheckInEvent],
        heartbeats: [HeartbeatSignal],
        locations: [Location],
        timeZone: TimeZone
    ) -> PersonBaseline {

        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -config.baselineWindowDays, to: Date())!

        // Filter to baseline window
        let recentCheckIns = checkIns.filter { $0.timestamp > cutoff }
        let recentHeartbeats = heartbeats.filter { $0.timestamp > cutoff }
        let recentLocations = locations.filter { $0.timestamp > cutoff }

        // Days with data
        let daysWithCheckIn = Set(recentCheckIns.map {
            calendar.startOfDay(for: $0.timestamp)
        }).count

        // Check-in time distribution
        var hourCounts = [Int: Int]()
        for ci in recentCheckIns {
            let comps = calendar.dateComponents(in: timeZone, from: ci.timestamp)
            let hour = comps.hour ?? 0
            hourCounts[hour, default: 0] += 1
        }
        let totalCheckIns = max(recentCheckIns.count, 1)
        let checkInBuckets = hourCounts.map { hour, count in
            TimeOfDayBucket(hour: hour, count: count, percentage: Double(count) / Double(totalCheckIns))
        }.sorted { $0.hour < $1.hour }

        // Check-in gaps
        let sortedCheckIns = recentCheckIns.sorted { $0.timestamp < $1.timestamp }
        var gaps: [TimeInterval] = []
        for i in 1..<sortedCheckIns.count {
            gaps.append(sortedCheckIns[i].timestamp.timeIntervalSince(sortedCheckIns[i-1].timestamp))
        }
        let maxGap = gaps.max() ?? (24 * 3600)
        let avgGap = gaps.isEmpty ? (24 * 3600) : gaps.reduce(0, +) / Double(gaps.count)
        let gapStdDev = standardDeviation(gaps)

        // Active hours from heartbeats
        var activeHourSet = Set<Int>()
        for hb in recentHeartbeats {
            let comps = calendar.dateComponents(in: timeZone, from: hb.timestamp)
            if let hour = comps.hour { activeHourSet.insert(hour) }
        }

        // Longest inactive period
        let sortedBeats = recentHeartbeats.sorted { $0.timestamp < $1.timestamp }
        var beatGaps: [TimeInterval] = []
        for i in 1..<sortedBeats.count {
            beatGaps.append(sortedBeats[i].timestamp.timeIntervalSince(sortedBeats[i-1].timestamp))
        }
        let maxInactive = beatGaps.max() ?? (8 * 3600)

        // Location grid
        var grid = [GridCell: Int]()
        var slotLocations = [TimeSlot: [GridCell]]()
        for loc in recentLocations {
            let cell = GridCell(latitude: loc.latitude, longitude: loc.longitude)
            grid[cell, default: 0] += 1
            let comps = calendar.dateComponents(in: timeZone, from: loc.timestamp)
            let slot = TimeSlot.from(hour: comps.hour ?? 12)
            slotLocations[slot, default: []].append(cell)
        }
        let totalLocPoints = max(recentLocations.count, 1)
        let locationFreq = grid.mapValues { Double($0) / Double(totalLocPoints) }

        // Battery at check-in
        let batteriesAtCheckIn = recentCheckIns.compactMap { _ -> Double? in
            // In real impl, join with heartbeat nearest to check-in time
            return nil
        }
        let avgBattery = batteriesAtCheckIn.isEmpty ? 0.7 : batteriesAtCheckIn.reduce(0, +) / Double(batteriesAtCheckIn.count)

        let baseline = PersonBaseline(
            personId: personId,
            dataPoints: recentCheckIns.count + recentHeartbeats.count,
            daysOfData: daysWithCheckIn,
            checkInTimes: checkInBuckets,
            longestCheckInGap: maxGap,
            averageCheckInGap: avgGap,
            checkInGapStdDev: gapStdDev,
            activeHours: activeHourSet,
            averageActivePeriodsPerDay: Double(recentHeartbeats.count) / Double(max(daysWithCheckIn, 1)),
            longestInactivePeriod: maxInactive,
            locationGrid: locationFreq,
            timeSlotLocations: slotLocations,
            averageBatteryAtCheckIn: avgBattery,
            typicalChargingHours: Set<Int>(),
            buildDate: Date()
        )

        baselines[personId] = baseline
        return baseline
    }

    // MARK: - Compute Risk Score

    func computeRiskScore(
        personId: String,
        lastCheckIn: Date?,
        lastHeartbeat: Date?,
        currentLocation: Location?,
        batteryLevel: Double?,
        batteryState: BatteryState,
        regionRiskLevel: Double,   // 0.0-1.0, from server
        timeZone: TimeZone
    ) -> RiskScore {

        guard let baseline = baselines[personId] else {
            return fallbackFixedThresholdScore(
                lastCheckIn: lastCheckIn,
                lastHeartbeat: lastHeartbeat
            )
        }

        let now = Date()
        var factors: [RiskFactor] = []

        // ── Factor 1: Check-in overtime (weight: 0.35) ──────────

        let checkInGap: TimeInterval
        if let lastCheckIn {
            checkInGap = now.timeIntervalSince(lastCheckIn)
        } else {
            checkInGap = 48 * 3600  // No check-in ever → max concern
        }

        let checkInDeviation: Double
        if baseline.longestCheckInGap > 0 {
            checkInDeviation = min(checkInGap / baseline.longestCheckInGap, 3.0) / 3.0
        } else {
            checkInDeviation = min(checkInGap / (24 * 3600), 1.0)
        }

        let checkInHoursLate = max(0, checkInGap - baseline.averageCheckInGap) / 3600
        let checkInExplanation: String
        if let lastCheckIn {
            let usualHour = baseline.checkInTimes.max(by: { $0.count < $1.count })?.hour ?? 9
            checkInExplanation = String(format: "通常在%d点前报平安，已超时%.0f小时", usualHour, checkInHoursLate)
        } else {
            checkInExplanation = "从未报过平安"
        }

        factors.append(RiskFactor(
            name: "check_in_overtime",
            weight: config.weightCheckInOvertime,
            rawValue: checkInGap,
            baselineValue: baseline.averageCheckInGap,
            deviationRatio: checkInDeviation,
            contribution: config.weightCheckInOvertime * checkInDeviation,
            explanation: checkInExplanation
        ))

        // ── Factor 2: Phone inactivity (weight: 0.25) ──────────

        let inactiveGap: TimeInterval
        if let lastHeartbeat {
            inactiveGap = now.timeIntervalSince(lastHeartbeat)
        } else {
            inactiveGap = 24 * 3600
        }

        let inactiveDeviation: Double
        if baseline.longestInactivePeriod > 0 {
            inactiveDeviation = min(inactiveGap / baseline.longestInactivePeriod, 3.0) / 3.0
        } else {
            inactiveDeviation = min(inactiveGap / (8 * 3600), 1.0)
        }

        let inactiveHours = inactiveGap / 3600
        let inactiveExplanation = String(format: "手机已%.0f小时无任何操作", inactiveHours)

        factors.append(RiskFactor(
            name: "phone_inactivity",
            weight: config.weightPhoneInactivity,
            rawValue: inactiveGap,
            baselineValue: baseline.longestInactivePeriod,
            deviationRatio: inactiveDeviation,
            contribution: config.weightPhoneInactivity * inactiveDeviation,
            explanation: inactiveExplanation
        ))

        // ── Factor 3: Location anomaly (weight: 0.20) ──────────

        var locationDeviation: Double = 0
        var locationExplanation = "位置正常"

        if let loc = currentLocation {
            let cell = GridCell(latitude: loc.latitude, longitude: loc.longitude)
            let frequency = baseline.locationGrid[cell] ?? 0

            // How unusual is this location?
            // frequency 0 = never seen before, frequency 1 = most common location
            locationDeviation = 1.0 - min(frequency * 5.0, 1.0)  // Scale so >20% visits = normal

            let calendar = Calendar.current
            let hour = calendar.dateComponents(in: timeZone, from: now).hour ?? 12
            let slot = TimeSlot.from(hour: hour)
            let usualCells = baseline.timeSlotLocations[slot] ?? []
            let isUsualForTimeSlot = usualCells.contains(cell)

            if !isUsualForTimeSlot && locationDeviation > 0.5 {
                locationExplanation = "当前位置在该时段从未出现过"
                locationDeviation = min(locationDeviation * 1.3, 1.0)
            } else if locationDeviation > 0.3 {
                locationExplanation = "当前位置不常出现"
            }
        }

        factors.append(RiskFactor(
            name: "location_anomaly",
            weight: config.weightLocationAnomaly,
            rawValue: locationDeviation,
            baselineValue: 0,
            deviationRatio: locationDeviation,
            contribution: config.weightLocationAnomaly * locationDeviation,
            explanation: locationExplanation
        ))

        // ── Factor 4: Battery anomaly (weight: 0.10) ──────────

        var batteryDeviation: Double = 0
        var batteryExplanation = "电量正常"

        if let level = batteryLevel {
            if level < 0.1 && batteryState == .unplugged {
                batteryDeviation = 0.9
                batteryExplanation = String(format: "电量仅%.0f%%且在下降", level * 100)
            } else if level < 0.2 && batteryState == .unplugged {
                batteryDeviation = 0.5
                batteryExplanation = String(format: "电量%.0f%%", level * 100)
            }
        } else {
            // No battery data — phone might be off
            if inactiveGap > 4 * 3600 {
                batteryDeviation = 0.7
                batteryExplanation = "无法获取电量信息，手机可能已关机"
            }
        }

        factors.append(RiskFactor(
            name: "battery_anomaly",
            weight: config.weightBatteryAnomaly,
            rawValue: batteryLevel ?? 0,
            baselineValue: baseline.averageBatteryAtCheckIn,
            deviationRatio: batteryDeviation,
            contribution: config.weightBatteryAnomaly * batteryDeviation,
            explanation: batteryExplanation
        ))

        // ── Factor 5: Regional risk (weight: 0.10) ──────────

        let regionExplanation = regionRiskLevel > 0.5 ? "所在地区风险较高" : "所在地区安全"

        factors.append(RiskFactor(
            name: "regional_risk",
            weight: config.weightRegionalRisk,
            rawValue: regionRiskLevel,
            baselineValue: 0,
            deviationRatio: regionRiskLevel,
            contribution: config.weightRegionalRisk * regionRiskLevel,
            explanation: regionExplanation
        ))

        // ── Total Score ──────────

        let totalScore = min(factors.reduce(0) { $0 + $1.contribution }, 1.0)

        let level: AlertLevel
        switch totalScore {
        case ..<config.yellowThreshold: level = .info
        case ..<config.redThreshold: level = .warning
        default: level = .critical
        }

        // Build human-readable reasons (only factors contributing significantly)
        let significantFactors = factors
            .filter { $0.contribution > 0.05 }
            .sorted { $0.contribution > $1.contribution }

        let reasons = significantFactors.map { $0.explanation }

        return RiskScore(
            totalScore: totalScore,
            level: level,
            factors: factors,
            humanReadableReasons: reasons,
            computedAt: now,
            baselineReady: baseline.isReady
        )
    }

    // MARK: - Fallback for Insufficient Baseline Data

    private func fallbackFixedThresholdScore(
        lastCheckIn: Date?,
        lastHeartbeat: Date?
    ) -> RiskScore {
        let now = Date()
        var score: Double = 0
        var reasons: [String] = []

        if let lastCheckIn {
            let hours = now.timeIntervalSince(lastCheckIn) / 3600
            if hours > 24 {
                score += 0.4
                reasons.append(String(format: "超过%.0f小时未报平安（基线数据不足，使用固定阈值）", hours))
            } else if hours > 12 {
                score += 0.2
                reasons.append(String(format: "%.0f小时未报平安", hours))
            }
        } else {
            score += 0.3
            reasons.append("从未报过平安")
        }

        if let lastHeartbeat {
            let hours = now.timeIntervalSince(lastHeartbeat) / 3600
            if hours > 8 {
                score += 0.2
                reasons.append(String(format: "手机%.0f小时无操作", hours))
            }
        }

        reasons.append("（正在收集行为数据以建立个人基线，需14天）")

        let level: AlertLevel = score > 0.7 ? .critical : score > 0.45 ? .warning : .info

        return RiskScore(
            totalScore: score,
            level: level,
            factors: [],
            humanReadableReasons: reasons,
            computedAt: now,
            baselineReady: false
        )
    }

    // MARK: - Math Helpers

    private func standardDeviation(_ values: [TimeInterval]) -> TimeInterval {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return sqrt(variance)
    }
}
