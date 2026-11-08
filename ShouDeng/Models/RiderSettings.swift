import Foundation

// MARK: - Rider settings (Settings → Rider)
//
// Everything defaults to how Rider mode behaved before, so nobody has to set anything.
// Guardrails live in the type, not only in the screen:
//  - SOS is always on the lock-screen card; two more buttons are the rider's choice
//  - the screen-hold countdown never goes below 3 s (pockets, accidental presses);
//    only the handlebar button may send at once
//  - the late-shift alert can be longer, never off
// The crew-facing ones (who hears a crew SOS off shift, how precisely the crew sees
// you) are kept on the server too (PUT /v1/crew/prefs), which enforces the same rules.

enum RiderVehicle: String, Codable, CaseIterable, Identifiable {
    case bicycle, ebike, scooter, motorbike, car
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .bicycle: return "bicycle"
        case .ebike: return "bicycle.circle"
        case .scooter: return "scooter"
        case .motorbike: return "motorcycle"
        case .car: return "car.fill"
        }
    }
}

/// Lock-screen card buttons besides SOS (which is always first)
enum RiderLockButton: String, Codable, CaseIterable, Identifiable {
    case ok, report, crash, location
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .report: return "exclamationmark.shield.fill"
        case .crash: return "car.side.rear.and.collision.and.car.side.front"
        case .location: return "location.fill"
        }
    }
}

struct ShiftTemplate: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    /// Calendar weekdays (1 = Sunday … 7 = Saturday); empty = no reminder days
    var weekdays: Set<Int>
    var watcherIds: [String]
    /// "Start your shift?" at the start time on those days (never starts by itself)
    var remind: Bool

    /// Planned end for a shift started now from this template (tomorrow if it has passed)
    func plannedEnd(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: now) ?? now
        return end <= now ? end.addingTimeInterval(86_400) : end
    }

    var timeRange: String {
        String(format: "%02d:%02d–%02d:%02d", startHour, startMinute, endHour, endMinute)
    }
}

struct RiderSettings: Codable, Equatable {
    static let storageKey = "rider_settings_v1"

    var vehicle: RiderVehicle = .bicycle
    // Crew (also on the server)
    var offShiftAlerts: String = "none"          // none | nearby | all
    var alertRadiusKm: Int = 3                    // 1 | 3 | 5 | 10
    var crewPrecision: String = "exact"           // exact | approx
    // Shifts
    var graceMinutes: Int = 30                    // 15 | 30 | 60
    var stillOkEveryMin: Int = 0                  // 0 (off) | 60 | 120
    var stillOkFromHour: Int = 22
    var stillOkToHour: Int = 6
    var templates: [ShiftTemplate] = []
    // SOS
    var handlebarCountdown: Int = 5               // 0…5
    var screenCountdown: Int = 5                  // 3 | 5
    // Lock-screen card
    var lockButtons: [RiderLockButton] = [.ok, .report]
    var showShiftTimer = true
    var showWatchers = false
    // Reports and caution spots
    var customReports: [String] = []
    var cautionHours: Int = 12                    // 2 | 12 | 24

    static let offShiftChoices = ["none", "nearby", "all"]
    static let radiusChoices = [1, 3, 5, 10]
    static let graceChoices = [15, 30, 60]
    static let stillOkChoices = [0, 60, 120]
    static let screenCountdownChoices = [3, 5]
    static let cautionChoices = [2, 12, 24]
    static let maxCustomReports = 5
    static let maxTemplates = 6

    /// Values outside the choices fall back to the defaults (an old or edited file)
    func sanitized() -> RiderSettings {
        var s = self
        let d = RiderSettings()
        if !Self.offShiftChoices.contains(s.offShiftAlerts) { s.offShiftAlerts = d.offShiftAlerts }
        if !Self.radiusChoices.contains(s.alertRadiusKm) { s.alertRadiusKm = d.alertRadiusKm }
        if s.crewPrecision != "approx" { s.crewPrecision = "exact" }
        if !Self.graceChoices.contains(s.graceMinutes) { s.graceMinutes = d.graceMinutes }
        if !Self.stillOkChoices.contains(s.stillOkEveryMin) { s.stillOkEveryMin = 0 }
        s.stillOkFromHour = min(max(s.stillOkFromHour, 0), 23)
        s.stillOkToHour = min(max(s.stillOkToHour, 0), 23)
        s.handlebarCountdown = min(max(s.handlebarCountdown, 0), 5)
        if !Self.screenCountdownChoices.contains(s.screenCountdown) { s.screenCountdown = max(3, min(5, s.screenCountdown)) >= 4 ? 5 : 3 }
        // Two distinct buttons besides SOS
        var buttons: [RiderLockButton] = []
        for b in s.lockButtons where !buttons.contains(b) { buttons.append(b) }
        for b in d.lockButtons where buttons.count < 2 && !buttons.contains(b) { buttons.append(b) }
        for b in RiderLockButton.allCases where buttons.count < 2 && !buttons.contains(b) { buttons.append(b) }
        s.lockButtons = Array(buttons.prefix(2))
        s.customReports = Array(s.customReports.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) }
            .filter { !$0.isEmpty }.prefix(Self.maxCustomReports))
        if !Self.cautionChoices.contains(s.cautionHours) { s.cautionHours = d.cautionHours }
        s.templates = Array(s.templates.prefix(Self.maxTemplates))
        return s
    }

    /// Seconds to cancel before an SOS goes out, for rider triggers
    func cancelWindow(for method: SOSTriggerMethod) -> Int? {
        switch method {
        case .bluetoothButton: return handlebarCountdown
        case .longPress, .widgetTap, .watchQuickAction: return max(3, screenCountdown)
        default: return nil
        }
    }

    // Tolerant decoding: a missing key keeps its default (fields added later)
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RiderSettings()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? nil ?? fallback }
        vehicle = v(.vehicle, d.vehicle)
        offShiftAlerts = v(.offShiftAlerts, d.offShiftAlerts)
        alertRadiusKm = v(.alertRadiusKm, d.alertRadiusKm)
        crewPrecision = v(.crewPrecision, d.crewPrecision)
        graceMinutes = v(.graceMinutes, d.graceMinutes)
        stillOkEveryMin = v(.stillOkEveryMin, d.stillOkEveryMin)
        stillOkFromHour = v(.stillOkFromHour, d.stillOkFromHour)
        stillOkToHour = v(.stillOkToHour, d.stillOkToHour)
        templates = v(.templates, d.templates)
        handlebarCountdown = v(.handlebarCountdown, d.handlebarCountdown)
        screenCountdown = v(.screenCountdown, d.screenCountdown)
        lockButtons = v(.lockButtons, d.lockButtons)
        showShiftTimer = v(.showShiftTimer, d.showShiftTimer)
        showWatchers = v(.showWatchers, d.showWatchers)
        customReports = v(.customReports, d.customReports)
        cautionHours = v(.cautionHours, d.cautionHours)
    }
}

/// PUT /v1/crew/prefs
struct RiderCrewPrefs: Codable, Equatable {
    var offShiftAlerts: String
    var alertRadiusKm: Int
    var crewPrecision: String
}

/// POST /v1/safety-events/crash
struct CrashReportRequest: Encodable {
    let clientEventId: String
    let hurt: Bool
    let latitude: Double?
    let longitude: Double?
    let accuracy: Double?
    let note: String?
    let vehicle: String
    let notifyCrew: Bool
    let sosEventId: String?
}

struct CrashReportResponse: Decodable {
    let id: String
    let notified: Int
}
