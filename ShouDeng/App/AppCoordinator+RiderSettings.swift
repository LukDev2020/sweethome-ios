import Foundation
import UserNotifications

// MARK: - Rider settings and crash reports (Settings → Rider)
//
// Settings live on the phone (Explore Mode: in memory); the crew-facing ones are also
// sent to the server, which applies them to crew SOS alerts and crew positions.

extension AppCoordinator {

    func updateRiderSettings(_ change: (inout RiderSettings) -> Void) {
        var next = riderSettings
        change(&next)
        next = next.sanitized()
        guard next != riderSettings else { return }
        let old = riderSettings
        riderSettings = next
        guard !isDemo else { liveActivityManager.updateRider(riderCardInfo); return }
        if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: RiderSettings.storageKey) }
        let crewOld = RiderCrewPrefs(offShiftAlerts: old.offShiftAlerts, alertRadiusKm: old.alertRadiusKm, crewPrecision: old.crewPrecision)
        let crewNew = RiderCrewPrefs(offShiftAlerts: next.offShiftAlerts, alertRadiusKm: next.alertRadiusKm, crewPrecision: next.crewPrecision)
        if crewOld != crewNew {
            let api = apiClient
            Task { let _: [String: RiderCrewPrefs]? = try? await api.put("/v1/crew/prefs", body: crewNew) }
        }
        if old.templates != next.templates { scheduleShiftReminders() }
        liveActivityManager.updateRider(riderCardInfo)
    }

    /// The server's copy wins for the crew-facing settings (another phone may have changed them)
    func applyServerCrewPrefs(_ prefs: RiderCrewPrefs?) {
        guard let prefs, !isDemo else { return }
        var s = riderSettings
        s.offShiftAlerts = prefs.offShiftAlerts
        s.alertRadiusKm = prefs.alertRadiusKm
        s.crewPrecision = prefs.crewPrecision
        s = s.sanitized()
        if s != riderSettings {
            riderSettings = s
            if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: RiderSettings.storageKey) }
        }
    }

    // MARK: Crash report ("I've crashed")

    /// Hurt → an SOS straight away (no countdown: they just said so); not hurt → the
    /// shift's watchers and guardians hear about it, with the place. Both are kept.
    /// Returns how many people were told (not hurt), when the server answered.
    /// Main actor: the SOS changes published state; run on the cooperative pool it
    /// deadlocked with SwiftUI's view update (found by RiderSettingsTests).
    @MainActor
    @discardableResult
    func reportCrash(hurt: Bool, note: String?, notifyCrew: Bool) async -> Int? {
        let clientId = UUID().uuidString
        let location = locationManager.lastReportedLocation ?? locationManager.bestAvailableLocation
        let lang = LanguageManager.shared
        if hurt {
            triggerSOS(method: .crashReport, clientSOSId: clientId)
        }
        addTimelineEntry(type: .crashReported, description: lang.localized(hurt ? "rider.crash.timeline.hurt" : "rider.crash.timeline.ok"))
        let body = CrashReportRequest(
            clientEventId: clientId, hurt: hurt,
            latitude: location?.coordinate.latitude, longitude: location?.coordinate.longitude,
            accuracy: location.flatMap { $0.horizontalAccuracy >= 0 ? $0.horizontalAccuracy : nil },
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            vehicle: riderSettings.vehicle.rawValue, notifyCrew: notifyCrew, sosEventId: nil)
        if hurt {
            // The SOS is what matters; the record follows through the queue
            apiClient.postQueued("/v1/safety-events/crash", body: body)
            return nil
        }
        let response: CrashReportResponse? = await apiClient.postSOS("/v1/safety-events/crash", body: body)
        return response?.notified
    }

    // MARK: Shift template reminders ("Start your shift?" — never starts by itself)

    static let shiftReminderPrefix = "shift-template-"

    func scheduleShiftReminders() {
        guard !isDemo else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { [riderSettings] pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(Self.shiftReminderPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            let lang = LanguageManager.shared
            for t in riderSettings.templates where t.remind {
                for day in t.weekdays.sorted() {
                    let content = UNMutableNotificationContent()
                    content.title = String(format: lang.localized("rider.template.reminder.title"), t.name)
                    content.body = lang.localized("rider.template.reminder.body")
                    content.sound = .default
                    content.userInfo = ["action": "shift_template", "template_id": t.id]
                    var when = DateComponents()
                    when.weekday = day
                    when.hour = t.startHour
                    when.minute = t.startMinute
                    let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
                    center.add(UNNotificationRequest(identifier: "\(Self.shiftReminderPrefix)\(t.id)-\(day)", content: content, trigger: trigger))
                }
            }
        }
    }

    /// "Still OK?" answered (the notification, or the button on the rider home)
    func confirmStillOk() {
        apiClient.postQueued("/v1/crew/shift/ok", body: EmptyBody())
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
