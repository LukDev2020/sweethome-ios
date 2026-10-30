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

    // Actions
    static let actionTakenOver = "ACTION_TAKEN_OVER"
    static let actionCall = "ACTION_CALL"
    static let actionCheckIn = "ACTION_CHECKIN"
    static let actionDismiss = "ACTION_DISMISS"

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

    // MARK: - Registration

    func registerForPushNotifications() {
        guard !ExploreMode.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Critical Alerts require Apple's com.apple.developer.usernotifications.critical-alerts
        // entitlement. Until it is granted, SOS uses the time-sensitive level
        // (entitlement shipped). Build with CRITICAL_ALERTS once Apple approves.
        #if CRITICAL_ALERTS
        let options: UNAuthorizationOptions = [.alert, .sound, .badge, .criticalAlert, .providesAppNotificationSettings]
        #else
        let options: UNAuthorizationOptions = [.alert, .sound, .badge, .providesAppNotificationSettings]
        #endif

        center.requestAuthorization(options: options) { [weak self] granted, error in
            if let error {
                #if DEBUG
                print("[PushService] Authorization error: \(error)")
                #endif
            }

            self?.hasCriticalAlertPermission = granted

            if granted {
                DispatchQueue.main.async {
                    Self.registerAllCategories()
                }
            }
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

        // Handoff Reminder
        let handoffCategory = UNNotificationCategory(
            identifier: Self.categoryHandoff,
            actions: [dismissAction],
            intentIdentifiers: [],
            options: []
        )

        var all: Set<UNNotificationCategory> = [sosCategory, warningCategory, checkInCategory, handoffCategory]
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
                silentAlarmConfirm: { Task { await SilentAlarmService.shared.confirmCheckIn() } }
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
