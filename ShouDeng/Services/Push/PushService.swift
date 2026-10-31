import Foundation
import UserNotifications

// MARK: - Push Service
//
// Handles three tiers of push notifications:
//   1. Normal: reminders, status updates (respects DND)
//   2. High: anomaly warnings (time-sensitive interruption)
//   3. Critical: SOS alerts (bypasses DND, plays sound at system volume)
//
// iOS Critical Alerts require an Apple entitlement — apply early.

final class PushService: NSObject {

    // MARK: - Notification Categories

    static let categorySOSAlert = "SOS_ALERT"
    static let categorySafetyWarning = "SAFETY_WARNING"
    static let categoryCheckInReminder = "CHECKIN_REMINDER"
    static let categoryHandoff = "DUTY_HANDOFF"
    static let categorySOSPending = "SOS_PENDING"
    static let pendingSOSNoticeId = "sos_pending_notice"

    // Actions
    static let actionTakenOver = "ACTION_TAKEN_OVER"
    static let actionCall = "ACTION_CALL"
    static let actionCheckIn = "ACTION_CHECKIN"
    static let actionDismiss = "ACTION_DISMISS"
    static let actionCancelSOS = "ACTION_CANCEL_SOS"

    // MARK: - Properties

    private(set) var isRegistered = false
    private(set) var deviceToken: String?
    private(set) var hasCriticalAlertPermission = false

    var onDeviceTokenReceived: ((String) -> Void)?
    var onSOSTakenOver: ((String) -> Void)?       // SOS event ID
    var onCheckInFromNotification: (() -> Void)?
    /// Guardian opened an SOS push (tap or "call"): (protectedPersonId, sosEventId)
    var onOpenSOSAlert: ((String, String?) -> Void)?
    var onSilentPushReceived: (([AnyHashable: Any]) -> Void)?
    var onCancelPendingSOS: (() -> Void)?

    // MARK: - Registration

    func registerForPushNotifications() {
        guard !ExploreMode.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Normal permissions only. Critical Alerts are requested separately,
        // after a guardian opts in (requestCriticalAlertPermission).
        let options: UNAuthorizationOptions = [.alert, .sound, .badge, .providesAppNotificationSettings]

        center.requestAuthorization(options: options) { [weak self] granted, error in
            if let error {
                #if DEBUG
                print("[PushService] Authorization error: \(error)")
                #endif
            }

            if granted {
                DispatchQueue.main.async {
                    Self.registerAllCategories()
                }
            }
            self?.refreshCriticalAlertPermission()
        }
    }

    /// Asks iOS for Critical Alerts permission (separate system prompt). Only
    /// call after the guardian has opted in to SOS critical alerts in the app.
    /// Requires the com.apple.developer.usernotifications.critical-alerts entitlement.
    func requestCriticalAlertPermission(completion: ((Bool) -> Void)? = nil) {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge, .criticalAlert, .providesAppNotificationSettings]
        UNUserNotificationCenter.current().requestAuthorization(options: options) { [weak self] _, _ in
            self?.refreshCriticalAlertPermission(completion: completion)
        }
    }

    private func refreshCriticalAlertPermission(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let enabled = settings.criticalAlertSetting == .enabled
            self?.hasCriticalAlertPermission = enabled
            DispatchQueue.main.async { completion?(enabled) }
        }
    }

    // MARK: - Notification Categories & Actions

    /// Registers every app notification category in ONE call. Separate
    /// get-then-set registrations from different services raced and overwrote each
    /// other, so some action buttons silently disappeared.
    static func registerAllCategories() {
        let lm = LanguageManager.shared
        // SOS Alert — shown when a protected person triggers SOS
        let takenOverAction = UNNotificationAction(
            identifier: Self.actionTakenOver,
            title: lm.localized("push.action.takenOver"),
            options: []
        )
        let callAction = UNNotificationAction(
            identifier: Self.actionCall,
            title: lm.localized("push.action.call"),
            options: [.foreground]
        )

        let sosCategory = UNNotificationCategory(
            identifier: Self.categorySOSAlert,
            actions: [takenOverAction, callAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Safety Warning — anomaly detected
        let dismissAction = UNNotificationAction(
            identifier: Self.actionDismiss,
            title: lm.localized("push.action.dismiss"),
            options: []
        )

        let warningCategory = UNNotificationCategory(
            identifier: Self.categorySafetyWarning,
            actions: [callAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // Check-in Reminder
        let checkInAction = UNNotificationAction(
            identifier: Self.actionCheckIn,
            title: lm.localized("push.action.checkIn"),
            options: []
        )

        let checkInCategory = UNNotificationCategory(
            identifier: Self.categoryCheckInReminder,
            actions: [checkInAction],
            intentIdentifiers: [],
            options: []
        )

        // Pending SOS — countdown running while the app is in the background
        let cancelSOSAction = UNNotificationAction(
            identifier: Self.actionCancelSOS,
            title: LanguageManager.shared.localized("sos.pending.cancel"),
            options: [.destructive]
        )
        let sosPendingCategory = UNNotificationCategory(
            identifier: Self.categorySOSPending,
            actions: [cancelSOSAction],
            intentIdentifiers: [],
            options: []
        )

        // Handoff Reminder
        let handoffCategory = UNNotificationCategory(
            identifier: Self.categoryHandoff,
            actions: [dismissAction],
            intentIdentifiers: [],
            options: []
        )

        var all: Set<UNNotificationCategory> = [sosCategory, warningCategory, checkInCategory, handoffCategory, sosPendingCategory]
        all.formUnion(DeadManSwitchService.notificationCategories())
        all.formUnion(SilentAlarmService.notificationCategories())
        all.formUnion(FakeCallService.notificationCategories())
        UNUserNotificationCenter.current().setNotificationCategories(all)
    }

    // MARK: - Schedule Local Notifications

    /// Schedule a check-in reminder at a specific time
    func scheduleCheckInReminder(at hour: Int, minute: Int = 0) {
        let content = UNMutableNotificationContent()
        content.title = "报平安提醒"
        content.body = "今天还好吗？点击报个平安。"
        content.categoryIdentifier = Self.categoryCheckInReminder
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: "checkin_reminder_\(hour)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Schedule a duty handoff reminder
    func scheduleHandoffReminder(at date: Date, outgoing: String?, incoming: String) {
        let content = UNMutableNotificationContent()

        if let outgoing {
            content.title = "值班交接"
            content.body = "\(outgoing)的值班即将结束，\(incoming)即将接班。"
        } else {
            content.title = "值班开始"
            content.body = "你的值班时段即将开始。"
        }

        content.categoryIdentifier = Self.categoryHandoff
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "handoff_\(date.timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Pending SOS notice

    /// Shown when an SOS countdown starts while the app isn't in the foreground,
    /// so the user can still cancel an accidental trigger.
    func firePendingSOSNotice(seconds: Int) {
        let lang = LanguageManager.shared
        let content = UNMutableNotificationContent()
        content.title = lang.localized("sos.pending.notice.title")
        content.body = String(format: lang.localized("sos.pending.notice.body"), seconds)
        content.categoryIdentifier = Self.categorySOSPending
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: Self.pendingSOSNoticeId,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func removePendingSOSNotice() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.pendingSOSNoticeId])
        center.removeDeliveredNotifications(withIdentifiers: [Self.pendingSOSNoticeId])
    }

    // MARK: - Build Critical Alert Payload (for SOS)

    /// Creates a local critical alert notification (for testing / offline fallback)
    func fireCriticalSOSAlert(
        protectedPersonName: String,
        locationDescription: String,
        sosEventId: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "\(protectedPersonName)正在求助"
        content.body = locationDescription
        content.categoryIdentifier = Self.categorySOSAlert
        content.userInfo = [
            "sos_id": sosEventId,
            "type": "sos_alert"
        ]

        #if CRITICAL_ALERTS
        // Critical alert — bypasses DND, plays at system volume
        content.sound = UNNotificationSound.criticalSoundNamed(
            UNNotificationSoundName("sos_alert.caf"),
            withAudioVolume: 1.0
        )
        content.interruptionLevel = .critical
        #else
        content.sound = UNNotificationSound(named: UNNotificationSoundName("sos_alert.caf"))
        content.interruptionLevel = .timeSensitive
        #endif
        content.relevanceScore = 1.0

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)

        let request = UNNotificationRequest(
            identifier: "sos_\(sosEventId)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                #if DEBUG
                print("[PushService] Failed to fire critical alert: \(error)")
                #endif
            }
        }
    }

    // MARK: - Handle Device Token

    func didRegisterForRemoteNotifications(withDeviceToken token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = tokenString
        isRegistered = true
        onDeviceTokenReceived?(tokenString)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushService: UNUserNotificationCenterDelegate {

    // Handle notification while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let categoryId = notification.request.content.categoryIdentifier

        // Always show SOS alerts even when app is in foreground
        if categoryId == Self.categorySOSAlert {
            completionHandler([.banner, .sound, .badge, .list])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    // Handle notification action (user tapped a button)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        PushService.route(
            actionIdentifier: response.actionIdentifier,
            categoryIdentifier: response.notification.request.content.categoryIdentifier,
            userInfo: userInfo,
            handlers: .init(
                sosTakenOver: { [weak self] in self?.onSOSTakenOver?($0) },
                checkIn: { [weak self] in self?.onCheckInFromNotification?() },
                openSOSAlert: { [weak self] in self?.onOpenSOSAlert?($0, $1) },
                deadManDismiss: { DeadManSwitchService.shared.cancel() },
                deadManExtend: { DeadManSwitchService.shared.extend(by: .min5) },
                silentAlarmConfirm: { Task { await SilentAlarmService.shared.confirmCheckIn() } },
                cancelPendingSOS: { [weak self] in
                    DispatchQueue.main.async { self?.onCancelPendingSOS?() }
                }
            )
        )

        completionHandler()
    }
}

// MARK: - Notification response routing (pure, testable)

extension PushService {
    struct ResponseHandlers {
        var sosTakenOver: (String) -> Void
        var checkIn: () -> Void
        var openSOSAlert: (String, String?) -> Void
        var deadManDismiss: () -> Void
        var deadManExtend: () -> Void
        var silentAlarmConfirm: () -> Void
        /// "Cancel" on the notification shown during the SOS cancel window.
        var cancelPendingSOS: () -> Void = {}
    }

    /// Routes a notification response to the right service. Previously only the
    /// guardian actions were handled — dead-man "I'm safe" / "+5 min" and the
    /// silent-alarm "I'm safe" went nowhere, so the server escalated false alarms.
    static func route(
        actionIdentifier: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any],
        handlers: ResponseHandlers
    ) {
        let sosId = (userInfo["sos_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let personId = (userInfo["person_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let action = userInfo["action"] as? String ?? userInfo["type"] as? String

        switch actionIdentifier {
        case actionTakenOver:
            if let sosId { handlers.sosTakenOver(sosId) }
        case actionCheckIn:
            handlers.checkIn()
        case actionCall:
            // Open the alert screen; it has the call buttons for this person
            if let personId { handlers.openSOSAlert(personId, sosId) }
        case "DMS_DISMISS":
            handlers.deadManDismiss()
        case "DMS_EXTEND_5":
            handlers.deadManExtend()
        case SilentAlarmService.confirmActionId:
            handlers.silentAlarmConfirm()
        case actionCancelSOS:
            handlers.cancelPendingSOS()
        case UNNotificationDefaultActionIdentifier:
            if (action == "sos_alert" || action == "sos_acknowledged" || categoryIdentifier == categorySOSAlert),
               let personId {
                handlers.openSOSAlert(personId, sosId)
            }
        default:
            break
        }
    }
}
