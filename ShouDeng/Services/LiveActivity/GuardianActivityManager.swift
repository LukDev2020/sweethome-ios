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
        emergencyPhone: String,
        emergencyLabel: String
    ) {
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
            statusText: "正常",
            guardians: guardians,
            lastCheckIn: lastCheckIn,
            homeTimerDeadline: nil,
            homeTimerLabel: nil,
            emergencyPhone: emergencyPhone,
            emergencyLabel: emergencyLabel
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
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
            updatedAt: Date()
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
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
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func updateProtectedGuardians(_ guardians: [ProtectedActivityAttributes.GuardianInfo]) {
        guard let activity = protectedActivity else { return }
        Task {
            var state = activity.content.state
            state.guardians = guardians
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func updateProtectedCheckIn() {
        guard let activity = protectedActivity else { return }
        Task {
            var state = activity.content.state
            state.lastCheckIn = Date()
            state.status = .normal
            state.statusText = "正常"
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func updateProtectedTimer(deadline: Date?, label: String?) {
        guard let activity = protectedActivity else { return }
        Task {
            var state = activity.content.state
            state.homeTimerDeadline = deadline
            state.homeTimerLabel = label
            state.status = deadline != nil ? .timerRunning : .normal
            state.statusText = deadline != nil ? "回家计时中" : "正常"
            await activity.update(.init(state: state, staleDate: nil))
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
                updatedAt: Date()
            )
            await activity.update(.init(state: newState, staleDate: nil))
        }
    }

    // MARK: - SOS (both roles)

    func triggerSOS(localEmergencyNumber: String) {
        if let activity = protectedActivity {
            Task {
                var state = activity.content.state
                state.status = .sosActive
                state.statusText = "紧急求助中"
                state.emergencyPhone = localEmergencyNumber
                state.emergencyLabel = localEmergencyNumber
                await activity.update(
                    .init(state: state, staleDate: nil),
                    alertConfiguration: .init(
                        title: "SOS 紧急求助",
                        body: "守灯已触发紧急求助",
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
                state.statusText = "正常"
                await activity.update(.init(state: state, staleDate: nil))
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
        Task {
            for activity in Activity<ProtectedActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            for activity in Activity<GuardianActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
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
        case .allSafe: return "全部安全"
        case .needsAttention: return "需关注"
        case .sosAlert: return "紧急"
        }
    }
}
