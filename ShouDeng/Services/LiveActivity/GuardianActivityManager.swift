import ActivityKit
import Foundation

/// Manages Live Activities for both roles.
/// - Protected Person: shows guardians watching you + SOS/check-in
/// - Guardian: shows protected persons' status + call button
final class GuardianActivityManager {

    private var startedProtected: Activity<ProtectedActivityAttributes>?
    private var startedGuardian: Activity<GuardianActivityAttributes>?

    /// The card this launch started, or — after iOS relaunched the app (SOS, lock-screen
    /// button) — the one still on the lock screen, so updates keep reaching it.
    private var protectedActivity: Activity<ProtectedActivityAttributes>? {
        get { startedProtected ?? Activity<ProtectedActivityAttributes>.activities.first { $0.activityState == .active } }
        set { startedProtected = newValue }
    }
    private var guardianActivity: Activity<GuardianActivityAttributes>? {
        get { startedGuardian ?? Activity<GuardianActivityAttributes>.activities.first { $0.activityState == .active } }
        set { startedGuardian = newValue }
    }

    private static var stale: Date { Date().addingTimeInterval(600) }

    /// Changes the protected card's state (nothing if no card is up).
    private func updateProtected(_ change: @escaping (inout ProtectedActivityAttributes.ContentState) -> Void) {
        guard let activity = protectedActivity else { return }
        Task {
            var state = activity.content.state
            change(&state)
            guard state != activity.content.state else { return }
            await activity.update(.init(state: state, staleDate: Self.stale))
        }
    }

    private func updateGuardian(_ change: @escaping (inout GuardianActivityAttributes.ContentState) -> Void) {
        guard let activity = guardianActivity else { return }
        Task {
            var state = activity.content.state
            change(&state)
            guard state != activity.content.state else { return }
            await activity.update(.init(state: state, staleDate: Self.stale))
        }
    }

    // MARK: - Start (Protected Person role)

    func startProtectedActivity(
        userName: String,
        guardians: [ProtectedActivityAttributes.GuardianInfo],
        lastCheckIn: Date?,
        latestUpdate: String? = nil,
        latestUpdateAt: Date? = nil,
        emergencyPhone: String,
        emergencyLabel: String,
        bloodType: String? = nil,
        allergies: [String] = [],
        conditions: [String] = [],
        emergencyNote: String? = nil,
        emergencyMedications: [ProtectedActivityAttributes.MedInfo] = [],
        familyContactName: String? = nil,
        familyContactPhone: String? = nil,
        demo: Bool = false
    ) {
        // During the demo only the demo's own (sample) card may start — never the real one
        guard !ExploreMode.isActive || demo else { return }
        let authInfo = ActivityAuthorizationInfo()
        NSLog("[LiveActivity] Protected — areActivitiesEnabled: \(authInfo.areActivitiesEnabled)")

        guard authInfo.areActivitiesEnabled else {
            NSLog("[LiveActivity] Protected — not authorized, aborting")
            return
        }

        endAllActivities()

        let attributes = ProtectedActivityAttributes(userName: userName)
        var state = ProtectedActivityAttributes.ContentState(
            status: .normal,
            statusText: WidgetDataStore.localized("la.normal"),
            guardians: guardians,
            lastCheckIn: lastCheckIn,
            homeTimerDeadline: nil,
            homeTimerLabel: nil,
            emergencyPhone: emergencyPhone,
            emergencyLabel: emergencyLabel,
            bloodType: bloodType,
            allergies: allergies,
            conditions: conditions,
            emergencyNote: emergencyNote,
            emergencyMedications: emergencyMedications,
            latestUpdate: latestUpdate,
            latestUpdateAt: latestUpdateAt,
            cardStyle: .stored
        )
        state.familyContactName = familyContactName
        state.familyContactPhone = familyContactPhone

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(600)),
                pushType: Self.pushType
            )
            protectedActivity = activity
            NSLog("[LiveActivity] Protected started: \(activity.id)")
            observePushToken(activity)
        } catch {
            NSLog("[LiveActivity] Protected start FAILED: \(error)")
        }
    }

    // MARK: - Start (Guardian role)

    func startGuardianActivity(
        guardianName: String,
        persons: [GuardianActivityAttributes.PersonInfo],
        priorityPersonName: String,
        priorityPersonPhone: String,
        demo: Bool = false
    ) {
        guard !ExploreMode.isActive || demo else { return }
        let authInfo = ActivityAuthorizationInfo()
        NSLog("[LiveActivity] Guardian — areActivitiesEnabled: \(authInfo.areActivitiesEnabled)")

        guard authInfo.areActivitiesEnabled else {
            NSLog("[LiveActivity] Guardian — not authorized, aborting")
            return
        }

        endAllActivities()

        let overallStatus = Self.computeOverallStatus(persons)
        let attributes = GuardianActivityAttributes(guardianName: guardianName)
        let state = GuardianActivityAttributes.ContentState(
            overallStatus: overallStatus,
            overallStatusText: Self.overallStatusText(overallStatus, count: persons.count),
            persons: Array(persons.prefix(3)),
            priorityPersonName: priorityPersonName,
            priorityPersonPhone: priorityPersonPhone,
            updatedAt: Date(),
            cardStyle: .stored
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(600)),
                pushType: Self.pushType
            )
            guardianActivity = activity
            NSLog("[LiveActivity] Guardian started: \(activity.id)")
            observePushToken(activity)
        } catch {
            NSLog("[LiveActivity] Guardian start FAILED: \(error)")
        }
    }

    // MARK: - Update (Protected)

    func updateProtectedStatus(_ status: ProtectedActivityAttributes.OverallStatus, text: String) {
        guard let activity = protectedActivity else { return }
        Task {
            var state = activity.content.state
            state.status = status
            state.statusText = text
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(600)))
        }
    }

    func updateProtectedGuardians(_ guardians: [ProtectedActivityAttributes.GuardianInfo]) {
        guard let activity = protectedActivity else { return }
        Task {
            var state = activity.content.state
            state.guardians = guardians
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(600)))
        }
    }

    func updateProtectedCheckIn() {
        guard let activity = protectedActivity else { return }
        Task {
            var state = activity.content.state
            state.lastCheckIn = Date()
            state.status = .normal
            state.statusText = WidgetDataStore.localized("la.normal")
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(600)))
        }
    }

    /// Guardians, last check-in and latest family post, refreshed on each trip to the background.
    func updateProtectedOverview(
        guardians: [ProtectedActivityAttributes.GuardianInfo],
        lastCheckIn: Date?,
        latestUpdate: String?,
        latestUpdateAt: Date?
    ) {
        guard let activity = protectedActivity else { return }
        Task {
            var state = activity.content.state
            state.guardians = guardians
            if let lastCheckIn, lastCheckIn > (state.lastCheckIn ?? .distantPast) { state.lastCheckIn = lastCheckIn }
            state.latestUpdate = latestUpdate
            state.latestUpdateAt = latestUpdateAt
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(600)))
        }
    }

    /// "Location" on the card: a fresh location went to the family.
    func updateProtectedLocationShared() {
        guard let activity = protectedActivity else { return }
        Task {
            var state = activity.content.state
            state.lastLocationShare = Date()
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(600)))
        }
    }

    /// The running countdown (safety timer or home timer) on the card; nil ends it.
    /// An SOS on the card stays — the countdown shows again once it's over.
    func updateProtectedTimer(deadline: Date?, startedAt: Date? = nil, kind: String? = nil, label: String?) {
        updateProtected { state in
            state.homeTimerDeadline = deadline
            state.homeTimerLabel = label
            state.timerStartedAt = deadline == nil ? nil : startedAt
            state.timerKind = deadline == nil ? nil : kind
            guard state.status != .sosActive else { return }
            state.status = deadline != nil ? .timerRunning : .normal
            state.statusText = WidgetDataStore.localized(deadline != nil ? "la.home.timer" : "la.normal")
        }
    }

    /// What the server has done for my SOS (guardians reached, who is handling it, next step).
    func updateOwnSOS(_ info: ProtectedActivityAttributes.SOSCardInfo) {
        updateProtected { state in
            guard state.status == .sosActive else { return }
            state.sos = info
        }
    }

    /// Silent SOS: waiting for the second tap until `until` (nil: not any more)
    func setSilentSOSArmed(until: Date?) {
        updateProtected { $0.silentSOSArmedUntil = until }
    }

    /// Silent SOS sent from the card (nil: that SOS is over)
    func markSilentSOSSent(_ at: Date?) {
        updateProtected { state in
            state.silentSOSArmedUntil = nil
            state.silentSOSSentAt = at
        }
    }

    /// Who a bystander can call for the family
    func updateFamilyContact(name: String?, phone: String?) {
        updateProtected { state in
            state.familyContactName = name
            state.familyContactPhone = phone
        }
    }

    // MARK: - Update (Guardian SOS)

    /// Someone I look after raised an SOS (nil: no SOS any more).
    func updateGuardianSOS(_ info: GuardianActivityAttributes.SOSCardInfo?) {
        updateGuardian { $0.sos = info }
    }

    // MARK: - Update (Guardian)

    func updateGuardianPersons(
        _ persons: [GuardianActivityAttributes.PersonInfo],
        priorityName: String,
        priorityPhone: String
    ) {
        guard let activity = guardianActivity else { return }
        let status = Self.computeOverallStatus(persons)
        Task {
            var newState = GuardianActivityAttributes.ContentState(
                overallStatus: status,
                overallStatusText: Self.overallStatusText(status, count: persons.count),
                persons: Array(persons.prefix(3)),
                priorityPersonName: priorityName,
                priorityPersonPhone: priorityPhone,
                updatedAt: Date(),
                cardStyle: .stored
            )
            newState.sos = activity.content.state.sos
            await activity.update(.init(state: newState, staleDate: Date().addingTimeInterval(600)))
        }
    }

    /// Rider mode: shift, crew nearby, who is coming during an SOS (nil: standard card).
    func updateRider(_ info: RiderCardInfo?) {
        guard let activity = protectedActivity else { return }
        Task {
            var state = activity.content.state
            guard state.rider != info else { return }
            state.rider = info
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(600)))
        }
    }

    /// Settings → Lock screen card changed: redraw both cards with the stored style.
    func restyle() {
        let style = LockScreenCardStyle.stored
        if let activity = protectedActivity {
            Task {
                var state = activity.content.state
                state.cardStyle = style
                await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(600)))
            }
        }
        if let activity = guardianActivity {
            Task {
                var state = activity.content.state
                state.cardStyle = style
                await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(600)))
            }
        }
    }

    // MARK: - SOS (both roles)

    func triggerSOS(localEmergencyNumber: String, startedAt: Date = Date(), bystander: Bool = false, demo: Bool = false) {
        guard !ExploreMode.isActive || demo else { return }
        if let activity = protectedActivity {
            Task {
                var state = activity.content.state
                state.status = .sosActive
                state.statusText = WidgetDataStore.localized("la.sos.active")
                state.emergencyPhone = localEmergencyNumber
                state.emergencyLabel = localEmergencyNumber
                state.sos = .init(startedAt: startedAt, bystander: bystander)
                await activity.update(
                    .init(state: state, staleDate: Date().addingTimeInterval(600)),
                    alertConfiguration: .init(
                        title: "SOS",
                        body: "SOS",
                        sound: .default
                    )
                )
            }
        }
        // Guardian activity SOS is handled via updateGuardianPersons with alert status
    }

    func cancelSOS() {
        if let activity = protectedActivity {
            Task {
                var state = activity.content.state
                state.sos = nil
                state.silentSOSSentAt = nil
                // A countdown still running comes back
                state.status = state.homeTimerDeadline != nil ? .timerRunning : .normal
                state.statusText = WidgetDataStore.localized(state.homeTimerDeadline != nil ? "la.home.timer" : "la.normal")
                await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(600)))
            }
        }
    }

    // MARK: - End

    func endActivity() {
        if let activity = protectedActivity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            protectedActivity = nil
        }
        if let activity = guardianActivity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            guardianActivity = nil
        }
    }

    func endAllActivities() {
        // End synchronously to avoid race with subsequent start
        for activity in Activity<ProtectedActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        for activity in Activity<GuardianActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        protectedActivity = nil
        guardianActivity = nil
    }

    // MARK: - State

    var isRunning: Bool {
        protectedActivity != nil || guardianActivity != nil
    }

    // MARK: - Helpers

    private static var pushType: PushType? {
        #if DEBUG
        return nil
        #else
        return .token
        #endif
    }

    private func observePushToken<T: ActivityAttributes>(_ activity: Activity<T>) {
        guard Self.pushType != nil else { return }
        Task {
            for await pushToken in activity.pushTokenUpdates {
                let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
                await sendPushTokenToServer(tokenString)
            }
        }
    }

    private func sendPushTokenToServer(_ token: String) async {
        #if DEBUG
        NSLog("[LiveActivity] Push token: \(token.prefix(16))...")
        #endif
    }

    private static func computeOverallStatus(_ persons: [GuardianActivityAttributes.PersonInfo]) -> GuardianActivityAttributes.OverallStatus {
        if persons.contains(where: { $0.status == .alert }) { return .sosAlert }
        if persons.contains(where: { $0.status == .overdue || $0.status == .unreachable }) { return .needsAttention }
        return .allSafe
    }

    private static func overallStatusText(_ status: GuardianActivityAttributes.OverallStatus, count: Int) -> String {
        switch status {
        case .allSafe: return WidgetDataStore.localized("la.all.safe")
        case .needsAttention: return WidgetDataStore.localized("la.needs.attention")
        case .sosAlert: return WidgetDataStore.localized("la.emergency")
        }
    }
}

#if DEBUG
// MARK: - Simulator preview
//
// Launch with `-la-preview protected|protected-empty|guardian|guardian-empty` to put a
// sample card on the lock screen (Debug builds only), e.g. to check the fixed layout.
extension GuardianActivityManager {
    func startPreview(_ kind: String) {
        let now = Date()
        switch kind {
        case "protected", "protected-empty":
            let full = kind == "protected"
            startProtectedActivity(
                userName: "妈妈",
                guardians: full ? [
                    .init(name: "Sarah", initial: "S", isOnDuty: true, isOnline: true),
                    .init(name: "Kevin", initial: "K", isOnDuty: false, isOnline: false),
                ] : [],
                lastCheckIn: full ? now.addingTimeInterval(-25 * 60) : nil,
                latestUpdate: full ? "Sarah：妈，到家了吗？" : nil,
                latestUpdateAt: full ? now.addingTimeInterval(-6 * 60) : nil,
                emergencyPhone: "120",
                emergencyLabel: "120",
                bloodType: full ? "A+" : nil,
                allergies: full ? ["青霉素"] : [],
                emergencyMedications: full ? [.init(name: "硝酸甘油", location: "包里", dosage: "")] : []
            )
            if full {
                updateProtectedTimer(deadline: now.addingTimeInterval(18 * 60), startedAt: now.addingTimeInterval(-12 * 60),
                                     kind: "safety", label: nil)
            }
        case "guardian", "guardian-empty":
            let full = kind == "guardian"
            startGuardianActivity(
                guardianName: "Sarah",
                persons: full ? [
                    .init(id: "1", displayName: "妈妈", initial: "妈", status: .normal, cityName: "成都",
                          lastCheckIn: now.addingTimeInterval(-25 * 60), batteryLevel: 0.82),
                    .init(id: "2", displayName: "爸爸", initial: "爸", status: .overdue, cityName: "成都",
                          lastCheckIn: now.addingTimeInterval(-9 * 3600), batteryLevel: 0.15),
                ] : [],
                priorityPersonName: full ? "爸爸" : "",
                priorityPersonPhone: full ? "+8613800138000" : ""
            )
        default:
            break
        }
    }
}
#endif
