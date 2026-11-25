import SwiftUI
import UserNotifications
import UIKit

// MARK: - Pieces shared by both Settings screens
//
// Rows a normal user can trust: every switch here changes something, and every
// value shown is the one the app and server actually use.

/// The version people quote when reporting a problem: "1.0.0 (57)"
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "v\(version) (\($0))" } ?? "v\(version)"
    }
}

// MARK: Daily check-in reminder (protected person)

/// A real daily "Are you OK today?" notification on the phone, at a time the
/// person picks. (Settings used to show "09:00, 21:00" without scheduling anything.)
enum CheckInReminder {
    static let enabledKey = "checkin_daily_reminder_enabled"
    static let minutesKey = "checkin_daily_reminder_minutes"
    static let defaultMinutes = 9 * 60
    private static let idPrefix = "checkin_reminder_"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var minutes: Int { UserDefaults.standard.object(forKey: minutesKey) as? Int ?? defaultMinutes }

    /// Brings the scheduled notification in line with the setting (safe to call often)
    static func apply() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard isEnabled else { return }
            let content = UNMutableNotificationContent()
            content.title = LanguageManager.shared.localized("notif.checkinReminder.title")
            content.body = LanguageManager.shared.localized("notif.checkinReminder.body")
            content.categoryIdentifier = PushService.categoryCheckInReminder
            content.sound = .default
            var when = DateComponents()
            when.hour = minutes / 60
            when.minute = minutes % 60
            center.add(UNNotificationRequest(
                identifier: idPrefix + "daily",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
        }
    }

    /// Guardians and the demo don't get the protected person's reminder
    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(
                withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) })
        }
    }
}

/// "Daily check-in reminder" switch + time, and how long before family is alerted
/// (rows; the Settings section gives the title and the overdue hint)
struct CheckInSettingsPanel: View {
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage(CheckInReminder.enabledKey) private var enabled = true
    @AppStorage(CheckInReminder.minutesKey) private var minutes = CheckInReminder.defaultMinutes

    /// Same as the server's check-in overdue job (scheduled/checkinOverdue.ts)
    static let familyAlertHours = 8

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
                CheckInReminder.apply()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggleRow(icon: "checkmark.circle.fill", tint: SettingsTint.safe,
                              title: lang.localized("protected.settings.checkIn.dailyReminder"), isOn: $enabled)
                .accessibilityLabel(lang.localized("protected.settings.checkIn.dailyReminder"))
                .onChange(of: enabled) { _, _ in CheckInReminder.apply() }
            if enabled {
                SettingsDivider()
                HStack(spacing: 12) {
                    SettingsIcon(systemName: "alarm.fill", tint: SettingsTint.safe)
                    DatePicker(lang.localized("protected.settings.checkIn.time"), selection: time,
                               displayedComponents: .hourAndMinute)
                        .font(.scaled(size: 15))
                }
                .padding(.vertical, 6)
            }
            SettingsDivider()
            SettingsRow(icon: "bell.badge.fill", tint: SettingsTint.safe,
                        title: lang.localized("protected.settings.checkIn.overdueThreshold"),
                        value: String(format: lang.localized("protected.settings.checkIn.hours"), Self.familyAlertHours),
                        chevron: false)
        }
    }
}

// MARK: Notifications

/// SOS can't be muted (the server always sends it), so it's shown as always on.
/// If iOS notifications are off for the app, says so with a way to fix it —
/// otherwise an SOS would never reach this phone.
struct SOSNotificationRows: View {
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var systemOff = false
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if systemOff {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bell.slash.fill").foregroundStyle(alert)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.localized("settings.notification.systemOff.title"))
                                .font(.scaled(size: 13, weight: .semibold))
                                .foregroundStyle(alert)
                            Text(lang.localized("settings.notification.systemOff.body"))
                                .font(.scaled(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.scaled(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(alert.opacity(0.08)))
                }
                .buttonStyle(.settingsRow)
                .accessibilityIdentifier("settings.notifications.systemOff")
            }
            HStack(spacing: 12) {
                SettingsIcon(systemName: "bell.badge.fill", tint: SettingsTint.sos)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.localized("settings.notification.sos")).font(.scaled(size: 15))
                    Text(lang.localized("settings.notification.sos.alwaysOnHint"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Label(lang.localized("settings.notification.sos.alwaysOn"), systemImage: "checkmark.circle.fill")
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundStyle(systemOff ? Color.secondary : safe)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(lang.localized("settings.notification.sos.alwaysOn"))
            }
            .padding(.vertical, 3)
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private func refresh() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        systemOff = status == .denied
    }
}

// MARK: Log out

extension View {
    /// "Log out?" — a stray tap must not quietly stop the family's alerts
    func logoutConfirmation(isPresented: Binding<Bool>, isProtected: Bool, logout: @escaping () -> Void) -> some View {
        let lang = LanguageManager.shared
        return alert(lang.localized("settings.logout.confirm.title"), isPresented: isPresented) {
            Button(lang.localized("settings.action.cancel"), role: .cancel) {}
            Button(lang.localized("settings.logout"), role: .destructive, action: logout)
        } message: {
            Text(lang.localized(isProtected ? "settings.logout.confirm.protected" : "settings.logout.confirm.guardian"))
        }
    }
}
