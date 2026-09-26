import ActivityKit
import Foundation

/// Manages the Live Activity lifecycle — start, update, end.
/// Called from AppCoordinator to keep lock screen / Dynamic Island in sync.
final class GuardianActivityManager {

    private var currentActivity: Activity<GuardianActivityAttributes>?

    // MARK: - Start

    func startGuardianActivity(
        userName: String,
        guardianName: String,
        guardianPhone: String,
        protectionLayers: Int
    ) {
        let authInfo = ActivityAuthorizationInfo()
        NSLog("[LiveActivity] areActivitiesEnabled: \(authInfo.areActivitiesEnabled), frequentPushesEnabled: \(authInfo.frequentPushesEnabled)")

        guard authInfo.areActivitiesEnabled else {
            NSLog("[LiveActivity] Not authorized — aborting")
            return
        }

        // End any stale activity first
        endAllActivities()

        let attributes = GuardianActivityAttributes(
            userName: userName,
            serviceTier: "standard"
        )

        let initialState = GuardianActivityAttributes.ContentState(
            status: .normal,
            statusText: "正常",
            locationAccuracy: nil,
            lastLocationUpdate: Date(),
            guardianName: guardianName,
            guardianOnline: true,
            protectionLayers: protectionLayers,
            emergencyPhone: guardianPhone,
            emergencyLabel: guardianName
        )

        do {
            #if DEBUG
            let pushType: PushType? = nil
            #else
            let pushType: PushType? = .token
            #endif
            NSLog("[LiveActivity] Requesting activity with pushType=\(String(describing: pushType))")
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: pushType
            )
            currentActivity = activity
            NSLog("[LiveActivity] Started successfully: id=\(activity.id)")

            // Forward push token to server (only when push type is .token)
            if pushType != nil {
                Task { [weak self] in
                    for await pushToken in activity.pushTokenUpdates {
                        guard let self else { break }
                        let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
                        await self.sendPushTokenToServer(tokenString)
                    }
                }
            }
        } catch {
            NSLog("[LiveActivity] Start FAILED: \(error)")
        }
    }

    // MARK: - Update

    func updateLocation(accuracy: Int, timestamp: Date) {
        guard let activity = currentActivity else { return }
        Task {
            var state = activity.content.state
            state.locationAccuracy = accuracy
            state.lastLocationUpdate = timestamp
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func updateStatus(
        _ status: GuardianActivityAttributes.GuardianStatus,
        text: String
    ) {
        guard let activity = currentActivity else { return }
        Task {
            var state = activity.content.state
            state.status = status
            state.statusText = text
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func updateGuardianInfo(name: String, online: Bool, layers: Int) {
        guard let activity = currentActivity else { return }
        Task {
            var state = activity.content.state
            state.guardianName = name
            state.guardianOnline = online
            state.protectionLayers = layers
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func triggerSOS(localEmergencyNumber: String) {
        guard let activity = currentActivity else { return }
        Task {
            var state = activity.content.state
            state.status = .sos
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

    func cancelSOS(guardianName: String, guardianPhone: String) {
        guard let activity = currentActivity else { return }
        Task {
            var state = activity.content.state
            state.status = .normal
            state.statusText = "正常"
            state.emergencyPhone = guardianPhone
            state.emergencyLabel = guardianName
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    // MARK: - End

    func endActivity() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        #if DEBUG
        print("[LiveActivity] Ended")
        #endif
    }

    func endAllActivities() {
        Task {
            for activity in Activity<GuardianActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
    }

    // MARK: - Helpers

    var isRunning: Bool { currentActivity != nil }

    private func sendPushTokenToServer(_ token: String) async {
        // Will POST to /v1/device/live-activity-token
        #if DEBUG
        print("[LiveActivity] Push token: \(token.prefix(16))...")
        #endif
    }
}
