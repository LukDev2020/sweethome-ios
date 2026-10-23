import Foundation
import UserNotifications
import Combine

// MARK: - Silent Alarm Service
//
// "沉默即报警" — server-driven recurring check-in system.
// User sets daily check-in times. At each scheduled time, the server sends a
// silent push that wakes the app, which shows a local notification.
// If the user doesn't confirm within the window, the server escalates.
//
// Architecture:
//   Server schedules → silent push → app shows local notification → user taps →
//   app confirms to server → if no confirm within window → server escalates

final class SilentAlarmService: ObservableObject {

    static let shared = SilentAlarmService()
    private init() {}

    // MARK: - Published State

    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "silent_alarm_enabled") {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "silent_alarm_enabled") }
    }

    @Published var checkInTimes: [CheckInTime] = {
        if let data = UserDefaults.standard.data(forKey: "silent_alarm_times"),
           let times = try? JSONDecoder().decode([CheckInTime].self, from: data) {
            return times
        }
        return [
            CheckInTime(hour: 9, minute: 0),
            CheckInTime(hour: 21, minute: 0)
        ]
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(checkInTimes) {
                UserDefaults.standard.set(data, forKey: "silent_alarm_times")
            }
        }
    }

    @Published var confirmWindowMinutes: Int = UserDefaults.standard.object(forKey: "silent_alarm_window") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(confirmWindowMinutes, forKey: "silent_alarm_window") }
    }

    @Published var gracePeriodMisses: Int = UserDefaults.standard.object(forKey: "silent_alarm_grace") as? Int ?? 3 {
        didSet { UserDefaults.standard.set(gracePeriodMisses, forKey: "silent_alarm_grace") }
    }

    @Published var pendingCheckIn: PendingCheckIn?
    @Published var consecutiveMisses: Int = 0

    // MARK: - Types

    struct CheckInTime: Codable, Identifiable, Equatable {
        var id: String { "\(hour):\(minute)" }
        var hour: Int
        var minute: Int

        var displayString: String {
            String(format: "%02d:%02d", hour, minute)
        }
    }

    struct PendingCheckIn {
        let scheduledAt: Date
        let expiresAt: Date
        var isExpired: Bool { Date() > expiresAt }
    }

    struct SilentAlarmScheduleRequest: Codable {
        let enabled: Bool
        let times: [CheckInTime]
        let windowMinutes: Int
        let gracePeriodMisses: Int
    }

    // MARK: - Server Sync

    private var apiClient: APIClient?

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func syncScheduleToServer() async {
        guard let apiClient else { return }

        let request = SilentAlarmScheduleRequest(
            enabled: isEnabled,
            times: checkInTimes,
            windowMinutes: confirmWindowMinutes,
            gracePeriodMisses: gracePeriodMisses
        )

        do {
            let _: SuccessResponse = try await apiClient.post(
                "/v1/silent-alarm/schedule",
                body: request
            )
        } catch {
            #if DEBUG
            print("[SilentAlarm] sync error: \(error)")
            #endif
        }
    }

    // MARK: - Check-In Handling

    func handleCheckInPush() {
        let now = Date()
        let expires = now.addingTimeInterval(TimeInterval(confirmWindowMinutes * 60))

        pendingCheckIn = PendingCheckIn(scheduledAt: now, expiresAt: expires)

        // Show local notification
        let content = UNMutableNotificationContent()
        content.title = "安全确认"
        content.body = "请确认您当前安全。点击确认或打开应用。"
        content.sound = .default
        content.categoryIdentifier = "SILENT_ALARM_CHECKIN"

        let request = UNNotificationRequest(
            identifier: "silent_alarm_\(Int(now.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func confirmCheckIn() async {
        pendingCheckIn = nil
        consecutiveMisses = 0

        guard let apiClient else { return }

        do {
            let _: SuccessResponse = try await apiClient.post(
                "/v1/silent-alarm/confirm",
                body: EmptyBody()
            )
        } catch {
            #if DEBUG
            print("[SilentAlarm] confirm error: \(error)")
            #endif
        }
    }

    // MARK: - Notification Category Registration

    static func registerNotificationCategory() {
        let confirmAction = UNNotificationAction(
            identifier: "SILENT_ALARM_CONFIRM",
            title: "我安全",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "SILENT_ALARM_CHECKIN",
            actions: [confirmAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
