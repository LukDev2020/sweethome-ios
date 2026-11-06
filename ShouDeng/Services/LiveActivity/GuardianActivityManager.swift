import ActivityKit
import Foundation

/// Manages Live Activities for both roles.
/// - Protected Person: shows guardians watching you + SOS/check-in
/// - Guardian: shows protected persons' status + call button
final class GuardianActivityManager {

    private var protectedActivity: Activity<ProtectedActivityAttributes>?
    private var guardianActivity: Activity<GuardianActivityAttributes>?

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
        emergencyMedications: [ProtectedActivityAttributes.MedInfo] = []
    ) {
        guard !ExploreMode.isActive else { return }
        let authInfo = ActivityAuthorizationInfo()
        NSLog("[LiveActivity] Protected — areActivitiesEnabled: \(authInfo.areActivitiesEnabled)")

        guard authInfo.areActivitiesEnabled else {
            NSLog("[LiveActivity] Protected — not authorized, aborting")
            return
        }

        endAllActivities()

        let attributes = ProtectedActivityAttributes(userName: userName)
        let state = ProtectedActivityAttributes.ContentState(
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
        priorityPersonPhone: String
    ) {
        guard !ExploreMode.isActive else { return }
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

    func updateProtectedTimer(deadline: Date?, label: String?) {
        guard let activity = protectedActivity else { return }
        Task {
            var state = activity.content.state
            state.homeTimerDeadline = deadline
            state.homeTimerLabel = label
            state.status = deadline != nil ? .timerRunning : .normal
            state.statusText = deadline != nil ? WidgetDataStore.localized("la.home.timer") : WidgetDataStore.localized("la.normal")
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(600)))
        }
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
            let newState = GuardianActivityAttributes.ContentState(
                overallStatus: status,
                overallStatusText: Self.overallStatusText(status, count: persons.count),
                persons: Array(persons.prefix(3)),
                priorityPersonName: priorityName,
                priorityPersonPhone: priorityPhone,
                updatedAt: Date(),
                cardStyle: .stored
            )
            await activity.update(.init(state: newState, staleDate: Date().addingTimeInterval(600)))
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

    func triggerSOS(localEmergencyNumber: String) {
        guard !ExploreMode.isActive else { return }
        if let activity = protectedActivity {
            Task {
                var state = activity.content.state
                state.status = .sosActive
                state.statusText = WidgetDataStore.localized("la.sos.active")
                state.emergencyPhone = localEmergencyNumber
                state.emergencyLabel = localEmergencyNumber
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
                state.status = .normal
                state.statusText = WidgetDataStore.localized("la.normal")
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
            if full { updateProtectedTimer(deadline: now.addingTimeInterval(18 * 60), label: nil) }
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
