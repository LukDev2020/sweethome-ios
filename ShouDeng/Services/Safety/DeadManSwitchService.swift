import Foundation
import UIKit
import UserNotifications
import BackgroundTasks
import AudioToolbox
import CoreLocation

// MARK: - Dead Man's Switch Service
//
// A user-initiated countdown timer that auto-triggers SOS if the user does not
// dismiss it before expiry. Designed for solo high-risk activities (night run,
// meeting a stranger, walking home alone).
//
// Lifecycle:
//   User starts timer → countdown ticks every second → warnings at 60s / 30s / 0s
//   → if dismissed: cancelled cleanly
//   → if reaches 0: SOS posted to /v1/sos/trigger with method .deadManSwitch
//
// Persistence:
//   Active state is written to UserDefaults on every mutation so it survives
//   app kill. On next cold launch, call restoreIfNeeded() to reconnect.
//
// Background execution:
//   Uses UIBackgroundTask (immediate; ~30 s iOS allowance) for warnings.
//   BGAppRefreshTask ("com.shoudeng.deadman.check") is registered so the system
//   can wake the app near expiry when the UIBackgroundTask budget is exhausted.
//   The BG task is submitted whenever the timer is started or modified.

final class DeadManSwitchService: ObservableObject {

    // MARK: - Singleton

    static let shared = DeadManSwitchService()
    private init() {}

    // MARK: - Published State

    @Published var isActive: Bool = false
    @Published var remainingSeconds: Int = 0
    @Published var totalSeconds: Int = 0
    @Published var isPaused: Bool = false

    // MARK: - Preset Durations

    enum Preset: Int, CaseIterable, Identifiable {
        case min5   = 300
        case min10  = 600
        case min15  = 900
        case min20  = 1200
        case min30  = 1800
        case min45  = 2700
        case min60  = 3600
        case min90  = 5400
        case min120 = 7200

        var id: Int { rawValue }

        var displayName: String {
            switch self {
            case .min5:   return "5 min"
            case .min10:  return "10 min"
            case .min15:  return "15 min"
            case .min20:  return "20 min"
            case .min30:  return "30 min"
            case .min45:  return "45 min"
            case .min60:  return "1 hr"
            case .min90:  return "1.5 hr"
            case .min120: return "2 hr"
            }
        }
    }

    // MARK: - Quick-Start Profiles

    struct QuickStartProfile: Identifiable {
        let id: String
        let name: String           // Localisable key — callers may localise
        let nameRaw: String        // English fallback for logging
        let preset: Preset
        let icon: String           // SF Symbol name

        static let all: [QuickStartProfile] = [
            QuickStartProfile(id: "walking_home",     name: "Walking Home",     nameRaw: "Walking Home",     preset: .min20, icon: "figure.walk"),
            QuickStartProfile(id: "meeting_stranger", name: "Meeting Stranger",  nameRaw: "Meeting Stranger",  preset: .min30, icon: "person.2"),
            QuickStartProfile(id: "night_run",        name: "Night Run",         nameRaw: "Night Run",         preset: .min15, icon: "figure.run"),
            QuickStartProfile(id: "custom",           name: "Custom",            nameRaw: "Custom",            preset: .min20, icon: "slider.horizontal.3"),
        ]
    }

    // MARK: - Extension Increments (seconds)

    enum Extension: Int, CaseIterable, Identifiable {
        case min5  = 300
        case min10 = 600
        case min15 = 900

        var id: Int { rawValue }

        var displayName: String {
            switch self {
            case .min5:  return "+5 min"
            case .min10: return "+10 min"
            case .min15: return "+15 min"
            }
        }
    }

    // MARK: - BGTask Identifier

    static let bgTaskIdentifier = "com.shoudeng.deadman.check"

    // MARK: - UserDefaults Keys

    // Keychain keys — neutral names to avoid revealing safety timer in backups
    private enum KCKey {
        static let isActive      = "dt_a"
        static let startTime     = "dt_s"
        static let totalDuration = "dt_d"
        static let isPaused      = "dt_p"
        static let pausedAt      = "dt_pa"
        static let remainingAtPause = "dt_r"
    }

    // MARK: - Dependencies (injected after init)

    private weak var apiClient: APIClient?
    private weak var locationManager: AdaptiveLocationManager?

    func configure(apiClient: APIClient, locationManager: AdaptiveLocationManager) {
        self.apiClient = apiClient
        self.locationManager = locationManager
    }

    // MARK: - Private Timer State

    private var dispatchTimer: DispatchSourceTimer?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    // Tracks whether the 60s / 30s / 0s notifications have already been sent
    // for the current countdown epoch so they are not sent twice.
    private var sentNotification60 = false
    private var sentNotification30 = false
    private var sentNotification0  = false

    // Tracks whether the continuous-vibration loop at ≤10 s has started.
    private var criticalVibrationActive = false

    // MARK: - Public API

    /// Start a new countdown from the given duration in seconds.
    /// Any existing active timer is cancelled first.
    func start(seconds: Int) {
        guard seconds > 0 else { return }
        cancel(suppressNotifications: true)

        let now = Date()
        totalSeconds      = seconds
        remainingSeconds  = seconds
        isPaused          = false
        isActive          = true

        resetNotificationFlags()

        persist(startTime: now, totalDuration: seconds, isPaused: false, pausedAt: nil, remainingAtPause: nil)
        scheduleLocalNotifications(from: now, duration: seconds)
        submitBGTask(fireAt: now.addingTimeInterval(TimeInterval(seconds)))
        beginBackgroundTask()
        startDispatchTimer()
    }

    /// Convenience: start from a Preset.
    func start(preset: Preset) {
        start(seconds: preset.rawValue)
    }

    /// Pause the countdown. Idempotent.
    func pause() {
        guard isActive, !isPaused else { return }
        isPaused = true
        stopDispatchTimer()

        let now = Date()
        let remaining = remainingSeconds

        persistUpdate(isPaused: true, pausedAt: now, remainingAtPause: remaining)
        cancelScheduledLocalNotifications()
        cancelBGTask()
        endBackgroundTask()
    }

    /// Resume a paused countdown. Idempotent.
    func resume() {
        guard isActive, isPaused else { return }
        isPaused = false

        // Re-anchor start time so that remaining is preserved.
        let now = Date()
        let remaining = remainingSeconds

        // Recalculate a synthetic startTime such that:
        //   now + remaining = startTime + totalDuration
        //   => startTime = now - (totalDuration - remaining)
        let newStartTime = now.addingTimeInterval(-TimeInterval(totalSeconds - remaining))

        persist(startTime: newStartTime, totalDuration: totalSeconds, isPaused: false, pausedAt: nil, remainingAtPause: nil)
        resetNotificationFlags()
        scheduleLocalNotifications(from: now, duration: remaining)
        submitBGTask(fireAt: now.addingTimeInterval(TimeInterval(remaining)))
        beginBackgroundTask()
        startDispatchTimer()
    }

    /// Cancel the timer entirely. User-initiated safe dismissal.
    func cancel() {
        cancel(suppressNotifications: false)
    }

    /// Add extra time to an active (running or paused) timer.
    func extend(by increment: Extension) {
        guard isActive else { return }
        let added = increment.rawValue
        totalSeconds    += added
        remainingSeconds = min(remainingSeconds + added, totalSeconds)

        if isPaused {
            persistUpdate(isPaused: true, pausedAt: nil, remainingAtPause: remainingSeconds)
        } else {
            // Reschedule everything with the new end time.
            let now = Date()
            let newStartTime = now.addingTimeInterval(-TimeInterval(totalSeconds - remainingSeconds))
            persist(startTime: newStartTime, totalDuration: totalSeconds, isPaused: false, pausedAt: nil, remainingAtPause: nil)
            cancelScheduledLocalNotifications()
            resetNotificationFlags()
            scheduleLocalNotifications(from: now, duration: remainingSeconds)
            submitBGTask(fireAt: now.addingTimeInterval(TimeInterval(remainingSeconds)))
        }
    }

    // MARK: - App-Launch Restore

    /// Call this once on app launch (e.g. from AppCoordinator.onAppear).
    /// Reconnects the in-memory timer to any persisted state that survived a kill.
    func restoreIfNeeded() {
        let state = loadPersistedState()
        guard state.isActive else { return }

        let savedTotal     = state.totalDuration
        let wasPaused      = state.isPaused
        let savedStart     = state.startTime
        let savedPausedAt  = state.pausedAt
        let savedRemaining = state.remainingAtPause ?? 0

        guard savedTotal > 0 else {
            clearPersistence()
            return
        }

        totalSeconds = savedTotal
        isPaused     = wasPaused

        if wasPaused {
            // Paused timers do not advance wall-clock time.
            remainingSeconds = savedRemaining > 0 ? savedRemaining : savedTotal
            isActive = remainingSeconds > 0
            if isActive {
                resetNotificationFlags()
                // Don't start dispatch timer — timer is paused. UI will show frozen state.
            } else {
                clearPersistence()
            }
        } else {
            // Running timer: recalculate remaining from wall clock.
            guard let startTime = savedStart else {
                clearPersistence()
                return
            }
            let elapsed   = Int(Date().timeIntervalSince(startTime))
            let remaining = savedTotal - elapsed

            if remaining <= 0 {
                // Timer already expired while app was dead — fire SOS now.
                isActive         = false
                remainingSeconds = 0
                clearPersistence()
                fireSOS()
            } else {
                remainingSeconds = remaining
                isActive         = true
                resetNotificationFlags()
                // Reschedule notifications relative to remaining, not total.
                scheduleLocalNotifications(from: Date(), duration: remaining)
                submitBGTask(fireAt: Date().addingTimeInterval(TimeInterval(remaining)))
                beginBackgroundTask()
                startDispatchTimer()
            }
        }

        _ = savedPausedAt // referenced to avoid warning; used only for wasPaused branch
    }

    // MARK: - BGTaskScheduler Integration

    /// Register the background task handler. Call once from
    /// AppDelegate.application(_:didFinishLaunchingWithOptions:) BEFORE the app
    /// finishes launching (BGTaskScheduler requirement).
    static func registerBGTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: bgTaskIdentifier,
            using: nil
        ) { task in
            DeadManSwitchService.shared.handleBGTask(task as! BGAppRefreshTask)
        }
    }

    // MARK: - Private: Timer Engine

    private func startDispatchTimer() {
        stopDispatchTimer()

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        dispatchTimer = timer
    }

    private func stopDispatchTimer() {
        dispatchTimer?.cancel()
        dispatchTimer = nil
    }

    private func tick() {
        guard isActive, !isPaused else { return }

        let newRemaining = remainingSeconds - 1

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.remainingSeconds = max(0, newRemaining)
            self.handleWarnings(remaining: self.remainingSeconds)
        }

        if newRemaining <= 0 {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isActive = false
                self.isPaused = false
                self.clearPersistence()
                self.stopDispatchTimer()
                self.endBackgroundTask()
                self.fireSOS()
            }
        }
    }

    // MARK: - Private: Warnings

    private func handleWarnings(remaining: Int) {
        // 60-second warning — local notification
        if remaining == 60, !sentNotification60 {
            sentNotification60 = true
            postImmediateNotification(
                identifier: "dms_warning_60",
                title: NSLocalizedString("dms.notification.warning60.title", value: "Dead Man's Switch", comment: ""),
                body:  NSLocalizedString("dms.notification.warning60.body",  value: "60 seconds remaining. Tap to dismiss.", comment: ""),
                categoryIdentifier: "DMS_WARNING"
            )
        }

        // 30-second warning — local notification + single vibration
        if remaining == 30, !sentNotification30 {
            sentNotification30 = true
            postImmediateNotification(
                identifier: "dms_warning_30",
                title: NSLocalizedString("dms.notification.warning30.title", value: "Dead Man's Switch", comment: ""),
                body:  NSLocalizedString("dms.notification.warning30.body",  value: "30 seconds remaining! Tap to cancel.", comment: ""),
                categoryIdentifier: "DMS_WARNING"
            )
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }

        // 10-second critical warning — start continuous short vibrations
        if remaining <= 10, !criticalVibrationActive {
            criticalVibrationActive = true
            startCriticalVibration()
        }

        // 0-second notification (fires alongside fireSOS)
        if remaining == 0, !sentNotification0 {
            sentNotification0 = true
            postImmediateNotification(
                identifier: "dms_expired",
                title: NSLocalizedString("dms.notification.expired.title", value: "SOS Triggered", comment: ""),
                body:  NSLocalizedString("dms.notification.expired.body",  value: "Dead Man's Switch expired. Emergency alert sent to guardians.", comment: ""),
                categoryIdentifier: "DMS_EXPIRED"
            )
        }
    }

    private func startCriticalVibration() {
        // Fire short vibrations every 0.5 s for up to 10 s.
        // Each iteration checks that the timer is still active (not dismissed mid-way).
        var count = 0
        let maxCount = 20 // 10 seconds × 2 per second

        func vibrate() {
            guard isActive, count < maxCount else {
                criticalVibrationActive = false
                return
            }
            AudioServicesPlaySystemSound(1519) // short "peek" haptic
            count += 1
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.5) {
                vibrate()
            }
        }
        vibrate()
    }

    private func resetNotificationFlags() {
        sentNotification60      = false
        sentNotification30      = false
        sentNotification0       = false
        criticalVibrationActive = false
    }

    // MARK: - Private: Cancel

    private func cancel(suppressNotifications: Bool) {
        stopDispatchTimer()
        endBackgroundTask()
        cancelBGTask()
        cancelScheduledLocalNotifications()

        isActive         = false
        isPaused         = false
        remainingSeconds = 0
        totalSeconds     = 0
        criticalVibrationActive = false
        resetNotificationFlags()
        clearPersistence()
    }

    // MARK: - Private: SOS Trigger

    private func fireSOS() {
        // Grab location snapshot before going async.
        let location = locationManager?.lastReportedLocation
        let lat = location?.coordinate.latitude
        let lon = location?.coordinate.longitude

        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryRaw = UIDevice.current.batteryLevel
        let batteryLevel: Double? = batteryRaw >= 0 ? Double(batteryRaw) : nil

        guard let apiClient else {
            #if DEBUG
            print("[DeadManSwitch] No APIClient configured — SOS not sent")
            #endif
            return
        }

        apiClient.postQueued(
            "/v1/sos/trigger",
            body: SOSTriggerRequest(
                protectedPersonId: resolveProtectedPersonId(),
                triggerMethod: .deadManSwitch,
                latitude:  lat,
                longitude: lon,
                batteryLevel: batteryLevel
            )
        ) { success in
            #if DEBUG
            print("[DeadManSwitch] SOS delivery \(success ? "succeeded" : "queued for retry")")
            #endif
        }
    }

    /// Reads the current user ID from UserDefaults (written by AuthManager on login).
    /// Falls back to an empty string — the server will reject gracefully if the token
    /// carries a different identity, but this prevents a silent no-op.
    private func resolveProtectedPersonId() -> String {
        UserDefaults.standard.string(forKey: "current_user_id") ?? ""
    }

    // MARK: - Private: Local Notifications

    private func scheduleLocalNotifications(from now: Date, duration: Int) {
        cancelScheduledLocalNotifications()
        let center = UNUserNotificationCenter.current()

        let milestones: [(seconds: Int, identifier: String, title: String, body: String)] = [
            (
                60,
                "dms_sched_60",
                NSLocalizedString("dms.notification.warning60.title", value: "Dead Man's Switch", comment: ""),
                NSLocalizedString("dms.notification.warning60.body",  value: "60 seconds remaining. Tap to dismiss.", comment: "")
            ),
            (
                30,
                "dms_sched_30",
                NSLocalizedString("dms.notification.warning30.title", value: "Dead Man's Switch", comment: ""),
                NSLocalizedString("dms.notification.warning30.body",  value: "30 seconds remaining! Tap to cancel.", comment: "")
            ),
            (
                0,
                "dms_sched_0",
                NSLocalizedString("dms.notification.expired.title", value: "SOS Triggered", comment: ""),
                NSLocalizedString("dms.notification.expired.body",  value: "Dead Man's Switch expired. Emergency alert sent to guardians.", comment: "")
            ),
        ]

        for milestone in milestones {
            let fireInSeconds = duration - milestone.seconds
            guard fireInSeconds > 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = milestone.title
            content.body  = milestone.body
            content.sound = milestone.seconds == 0 ? .defaultCritical : .default
            content.categoryIdentifier = milestone.seconds == 0 ? "DMS_EXPIRED" : "DMS_WARNING"
            content.interruptionLevel  = milestone.seconds == 0 ? .critical : .timeSensitive

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(fireInSeconds),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: milestone.identifier,
                content: content,
                trigger: trigger
            )
            center.add(request) { error in
                #if DEBUG
                if let error { print("[DeadManSwitch] Notification schedule error: \(error)") }
                #endif
            }
        }
    }

    private func cancelScheduledLocalNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["dms_sched_60", "dms_sched_30", "dms_sched_0"]
        )
    }

    private func postImmediateNotification(
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = categoryIdentifier == "DMS_EXPIRED" ? .defaultCritical : .default
        content.categoryIdentifier = categoryIdentifier
        content.interruptionLevel  = categoryIdentifier == "DMS_EXPIRED" ? .critical : .timeSensitive

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Private: Background Task (UIKit ~30 s budget)

    private func beginBackgroundTask() {
        guard backgroundTaskId == .invalid else { return }
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "DeadManSwitch") { [weak self] in
            // Expiry handler — iOS is about to suspend us.
            // The BGTask submission above will handle waking the app near expiry.
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
    }

    // MARK: - Private: BGTaskScheduler

    private func submitBGTask(fireAt date: Date) {
        cancelBGTask()
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        // Schedule slightly before actual expiry so the app wakes with time to act.
        request.earliestBeginDate = date.addingTimeInterval(-15)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[DeadManSwitch] BGTask submit error: \(error)")
            #endif
        }
    }

    private func cancelBGTask() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgTaskIdentifier)
    }

    private func handleBGTask(_ task: BGAppRefreshTask) {
        // Reschedule immediately so next expiry is covered.
        if isActive, !isPaused, remainingSeconds > 15 {
            submitBGTask(fireAt: Date().addingTimeInterval(TimeInterval(remainingSeconds)))
        }

        task.expirationHandler = { [weak self] in
            // System is reclaiming the task. Nothing to clean up — dispatch timer
            // handles actual SOS; the UIBackgroundTask covers short gaps.
            self?.endBackgroundTask()
        }

        // If the timer expired while we were dead, fire SOS now.
        restoreIfNeeded()

        task.setTaskCompleted(success: true)
    }

    // MARK: - Private: Persistence

    private func persist(
        startTime: Date,
        totalDuration: Int,
        isPaused: Bool,
        pausedAt: Date?,
        remainingAtPause: Int?
    ) {
        savePersistedState(PersistedTimerState(
            isActive: true, startTime: startTime, totalDuration: totalDuration,
            isPaused: isPaused, pausedAt: pausedAt, remainingAtPause: remainingAtPause
        ))
    }

    /// Lightweight update for pause/resume/extend without re-writing start time.
    private func persistUpdate(isPaused: Bool, pausedAt: Date?, remainingAtPause: Int?) {
        var state = loadPersistedState()
        state.isPaused = isPaused
        state.pausedAt = pausedAt
        state.remainingAtPause = remainingAtPause
        if !isPaused { state.totalDuration = totalSeconds }
        savePersistedState(state)
    }

    private func clearPersistence() {
        savePersistedState(PersistedTimerState(isActive: false, startTime: nil, totalDuration: 0, isPaused: false, pausedAt: nil, remainingAtPause: nil))
    }

    // Encrypted file persistence — hidden from device backups
    private struct PersistedTimerState: Codable {
        var isActive: Bool
        var startTime: Date?
        var totalDuration: Int
        var isPaused: Bool
        var pausedAt: Date?
        var remainingAtPause: Int?
    }

    private var timerStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dt_state.enc")
    }

    private func savePersistedState(_ state: PersistedTimerState) {
        let url = timerStateURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: [.completeFileProtection])
            var resourceURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? resourceURL.setResourceValues(values)
        }
    }

    private func loadPersistedState() -> PersistedTimerState {
        guard let data = try? Data(contentsOf: timerStateURL),
              let state = try? JSONDecoder().decode(PersistedTimerState.self, from: data) else {
            return PersistedTimerState(isActive: false, startTime: nil, totalDuration: 0, isPaused: false, pausedAt: nil, remainingAtPause: nil)
        }
        return state
    }

    // MARK: - Notification Category Registration

    /// Register UNNotificationCategory values for actionable warnings.
    /// Call once from AppDelegate or AppCoordinator setup.
    static func registerNotificationCategories() {
        let dismissAction = UNNotificationAction(
            identifier: "DMS_DISMISS",
            title: NSLocalizedString("dms.action.dismiss", value: "I'm Safe — Cancel", comment: ""),
            options: [.foreground]
        )
        let extendAction = UNNotificationAction(
            identifier: "DMS_EXTEND_5",
            title: NSLocalizedString("dms.action.extend5", value: "+5 min", comment: ""),
            options: []
        )

        let warningCategory = UNNotificationCategory(
            identifier: "DMS_WARNING",
            actions: [dismissAction, extendAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let expiredCategory = UNNotificationCategory(
            identifier: "DMS_EXPIRED",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories(
            [warningCategory, expiredCategory]
        )
    }

    // MARK: - Notification Response Handling

    /// Forward notification action responses here from UNUserNotificationCenterDelegate.
    /// Handles "I'm Safe — Cancel" and "+5 min" actions from lock screen.
    func handleNotificationResponse(_ response: UNNotificationResponse) {
        switch response.actionIdentifier {
        case "DMS_DISMISS":
            cancel()
        case "DMS_EXTEND_5":
            extend(by: .min5)
        default:
            break
        }
    }

    // MARK: - deinit

    deinit {
        stopDispatchTimer()
        endBackgroundTask()
    }
}
