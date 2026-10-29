import Foundation
import CallKit
import AVFoundation
import UIKit
import Combine

// MARK: - FakeCallService
//
// "虚假来电" — simulates an incoming phone call so the user can safely exit a
// threatening situation.  The caller name, ring delay, and whether a silent SOS
// fires on call-end are all user-configurable and persisted in UserDefaults.
//
// Architecture:
//   User schedules call → delay timer fires → CXProvider reports incoming call
//   (simulator: skip CallKit, play system sound + local notification instead)
//   → user answers → AVAudioPlayer loops a pre-recorded conversation clip
//   → user ends call → optionally triggers SilentAlarmService SOS escalation

// MARK: - Types

enum FakeCallDelay: Int, CaseIterable, Identifiable, Codable {
    case instant  = 0
    case five     = 5
    case fifteen  = 15
    case thirty   = 30
    case sixty    = 60

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .instant: return NSLocalizedString("fake_call_delay_instant", comment: "Instant")
        case .five:    return NSLocalizedString("fake_call_delay_5s",      comment: "5 seconds")
        case .fifteen: return NSLocalizedString("fake_call_delay_15s",     comment: "15 seconds")
        case .thirty:  return NSLocalizedString("fake_call_delay_30s",     comment: "30 seconds")
        case .sixty:   return NSLocalizedString("fake_call_delay_60s",     comment: "1 minute")
        }
    }

    var timeInterval: TimeInterval { TimeInterval(rawValue) }
}

enum FakeCallState: Equatable {
    case idle
    case scheduled(fireAt: Date)
    case ringing
    case active
    case ended
}

// MARK: - FakeCallService

final class FakeCallService: NSObject, ObservableObject {

    static let shared = FakeCallService()

    // MARK: - Persisted Settings

    @Published var callerName: String = UserDefaults.standard.string(forKey: "fakeCall_callerName") ?? "妈妈" {
        didSet { UserDefaults.standard.set(callerName, forKey: "fakeCall_callerName") }
    }

    @Published var selectedDelay: FakeCallDelay = {
        let raw = UserDefaults.standard.integer(forKey: "fakeCall_delay")
        return FakeCallDelay(rawValue: raw) ?? .five
    }() {
        didSet { UserDefaults.standard.set(selectedDelay.rawValue, forKey: "fakeCall_delay") }
    }

    @Published var triggerSilentSOSOnEnd: Bool = UserDefaults.standard.bool(forKey: "fakeCall_autoSOS") {
        didSet { UserDefaults.standard.set(triggerSilentSOSOnEnd, forKey: "fakeCall_autoSOS") }
    }

    // MARK: - Runtime State

    @Published var callState: FakeCallState = .idle
    @Published var callDuration: TimeInterval = 0

    // MARK: - Private

    private var provider: CXProvider?
    private var callController: CXCallController?
    private var activeCallUUID: UUID?
    private var scheduleTimer: Timer?
    private var durationTimer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private override init() {
        super.init()
        setupCallKit()
    }

    // MARK: - CallKit Setup

    private func setupCallKit() {
        guard !isSimulator else { return }

        let config = CXProviderConfiguration()
        config.supportsVideo        = false
        config.maximumCallGroups    = 1
        config.supportedHandleTypes = [.phoneNumber, .generic]

        // Use the system ringtone so the call feels authentic
        config.ringtoneSound = nil   // nil → default system ringtone

        provider = CXProvider(configuration: config)
        provider?.setDelegate(self, queue: .main)
        callController = CXCallController()
    }

    // MARK: - Public API

    /// Schedule a fake incoming call with the currently configured delay.
    func scheduleCall() {
        cancelScheduledCall()

        let delay = selectedDelay.timeInterval
        let fireAt = Date().addingTimeInterval(delay)
        callState = delay == 0 ? .ringing : .scheduled(fireAt: fireAt)

        if delay == 0 {
            triggerIncomingCall()
        } else {
            scheduleTimer = Timer.scheduledTimer(
                withTimeInterval: delay,
                repeats: false
            ) { [weak self] _ in
                self?.triggerIncomingCall()
            }
        }
    }

    /// Cancel a pending scheduled call before it fires.
    func cancelScheduledCall() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        if callState != .active {
            callState = .idle
        }
    }

    /// Programmatically end an active call (e.g. user taps "End Call" in UI).
    func endCall() {
        guard let uuid = activeCallUUID else {
            tearDownCall(triggeredBySOS: triggerSilentSOSOnEnd)
            return
        }

        if isSimulator {
            tearDownCall(triggeredBySOS: triggerSilentSOSOnEnd)
        } else {
            let endAction = CXEndCallAction(call: uuid)
            let transaction = CXTransaction(action: endAction)
            callController?.request(transaction) { [weak self] error in
                if let error {
                    #if DEBUG
                    print("[FakeCall] CXEndCallAction error: \(error)")
                    #endif
                    self?.tearDownCall(triggeredBySOS: self?.triggerSilentSOSOnEnd ?? false)
                }
            }
        }
    }

    // MARK: - Internal Trigger

    private func triggerIncomingCall() {
        callState = .ringing

        if isSimulator {
            handleSimulatorRing()
        } else {
            reportCallKitIncoming()
        }
    }

    // MARK: - CallKit Incoming Report

    private func reportCallKitIncoming() {
        let uuid = UUID()
        activeCallUUID = uuid

        let update = CXCallUpdate()
        update.remoteHandle       = CXHandle(type: .generic, value: callerName)
        update.localizedCallerName = callerName
        update.hasVideo            = false
        update.supportsHolding     = false
        update.supportsGrouping    = false
        update.supportsUngrouping  = false

        provider?.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error {
                #if DEBUG
                print("[FakeCall] reportNewIncomingCall error: \(error)")
                #endif
                // Fallback to simulator path if CallKit rejects
                self?.handleSimulatorRing()
            }
        }
    }

    // MARK: - Simulator / Fallback Path

    private func handleSimulatorRing() {
        // Play system ringtone sound as audible feedback
        AudioServicesPlaySystemSound(1007)  // kSystemSoundID_Vibrate equivalent for alert

        // Show a local notification that mimics an incoming call banner
        let content = UNMutableNotificationContent()
        content.title = callerName
        content.body  = NSLocalizedString("fake_call_incoming_body", comment: "Incoming call")
        content.sound = .defaultRingtone
        content.categoryIdentifier = "FAKE_CALL_INCOMING"

        let request = UNNotificationRequest(
            identifier: "fakeCall_\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)

        // Auto-answer after 4 s to simulate user picking up
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.beginActiveCall()
        }
    }

    // MARK: - Active Call (audio playback)

    private func beginActiveCall() {
        callState = .active
        callDuration = 0
        startDurationTimer()
        startConversationAudio()
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.callDuration += 1
        }
    }

    private func startConversationAudio() {
        // The app bundle should include "fake_call_audio.m4a" — a ~60-second
        // ambient conversation clip.  We loop it for the duration of the call.
        // If the file is absent (e.g. during unit tests) we degrade gracefully.
        configureAudioSession()

        guard let url = Bundle.main.url(forResource: "fake_call_audio", withExtension: "m4a") else {
            #if DEBUG
            print("[FakeCall] fake_call_audio.m4a not found in bundle — audio skipped")
            #endif
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1   // loop indefinitely
            audioPlayer?.volume        = 0.75
            audioPlayer?.play()
        } catch {
            #if DEBUG
            print("[FakeCall] AVAudioPlayer init error: \(error)")
            #endif
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("[FakeCall] AVAudioSession error: \(error)")
            #endif
        }
    }

    // MARK: - Tear Down

    private func tearDownCall(triggeredBySOS: Bool) {
        audioPlayer?.stop()
        audioPlayer = nil

        durationTimer?.invalidate()
        durationTimer = nil

        scheduleTimer?.invalidate()
        scheduleTimer = nil

        activeCallUUID = nil
        callDuration   = 0
        callState      = .ended

        deactivateAudioSession()

        // Reset to idle after a brief pause so the UI can show "ended" state
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.callState = .idle
        }

        if triggeredBySOS {
            fireSilentSOS()
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false,
                options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("[FakeCall] AVAudioSession deactivate error: \(error)")
            #endif
        }
    }

    // MARK: - Silent SOS Escalation

    private func fireSilentSOS() {
        // Hand off to SilentAlarmService which owns the server escalation path.
        // We synthesize a missed check-in so the server escalates to guardians.
        Task { @MainActor in
            SilentAlarmService.shared.handleCheckInPush()
            // Do not call confirmCheckIn() — the deliberately missed confirmation
            // within the window triggers server escalation automatically.
            #if DEBUG
            print("[FakeCall] Silent SOS fired — missed check-in injected")
            #endif
        }
    }

    // MARK: - Notification Category

    static func registerNotificationCategory() {
        let answerAction = UNNotificationAction(
            identifier: "FAKE_CALL_ANSWER",
            title: NSLocalizedString("fake_call_answer", comment: "Answer"),
            options: [.foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: "FAKE_CALL_DECLINE",
            title: NSLocalizedString("fake_call_decline", comment: "Decline"),
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: "FAKE_CALL_INCOMING",
            actions: [answerAction, declineAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - CXProviderDelegate

extension FakeCallService: CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        tearDownCall(triggeredBySOS: false)
    }

    /// User answered the call from the CallKit UI (lock screen / native sheet).
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        beginActiveCall()
        action.fulfill()
    }

    /// User ended the call from the CallKit UI.
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let shouldSOS = triggerSilentSOSOnEnd && callState == .active
        tearDownCall(triggeredBySOS: shouldSOS)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // CallKit has activated our audio session — start playback now.
        startConversationAudio()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        audioPlayer?.volume = action.isMuted ? 0 : 0.75
        action.fulfill()
    }
}
