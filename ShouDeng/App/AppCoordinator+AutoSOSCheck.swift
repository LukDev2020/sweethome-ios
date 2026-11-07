import UIKit

// MARK: - "Are you OK?" after a detected fall, distress sound or voice command
//
// The countdown runs on the wall clock (DispatchWorkItem + background task), not on
// sensor samples — those stop when the screen locks, which used to leave a fall with
// no answer and no SOS. For a fall the server is told at once ("pending"); if this
// phone goes silent it sends the SOS itself after the countdown (safetyEvents.ts),
// with the same clientSOSId, so the two join as one SOS.
// "Test fall detection" runs the same chain with a short countdown and sends nothing.

enum AutoSOSReason: String {
    case fall, distressSound, voiceCommand

    var sosMethod: SOSTriggerMethod {
        switch self {
        case .fall: return .fallDetection
        case .distressSound: return .audioDistress
        case .voiceCommand: return .voiceCommand
        }
    }
    /// Localized title / subtitle keys for the check screen
    var titleKey: String { "autosos.\(rawValue).title" }
    var subtitleKey: String { "autosos.\(rawValue).subtitle" }
}

struct AutoSOSCheck: Equatable {
    let reason: AutoSOSReason
    let startedAt: Date
    let deadline: Date
    let clientEventId: String
    let clientSOSId: String
    let metrics: FallDetector.FallMetrics?
    let isTest: Bool
    var duration: TimeInterval { deadline.timeIntervalSince(startedAt) }
}

/// POST /v1/safety-events/fall
struct FallEventReport: Encodable {
    struct Metrics: Encodable {
        let peakImpactG: Double
        let freeFallMs: Double
        let orientationChangeDeg: Double
        let stillnessVariance: Double
        let detector: String
    }
    let clientEventId: String
    let clientSOSId: String
    let outcome: String
    let detectedAt: Date
    let countdownSec: Int
    let latitude: Double?
    let longitude: Double?
    let accuracy: Double?
    let batteryLevel: Double?
    let metrics: Metrics?
    let respondedAfterSec: Double?
}

struct FallEventResponse: Decodable {
    let outcome: String
    let sosEventId: String?
}

extension AppCoordinator {
    // var: the tests shorten it
    static var autoSOSCountdown: TimeInterval = 60
    static let fallTestCountdown: TimeInterval = 15

    func beginAutoSOSCheck(reason: AutoSOSReason, metrics: FallDetector.FallMetrics? = nil, isTest: Bool = false) {
        guard autoSOSCheck == nil else { return }
        let now = Date()
        let check = AutoSOSCheck(
            reason: reason,
            startedAt: now,
            deadline: now.addingTimeInterval(isTest ? Self.fallTestCountdown : Self.autoSOSCountdown),
            clientEventId: UUID().uuidString,
            clientSOSId: UUID().uuidString,
            metrics: metrics,
            isTest: isTest
        )
        autoSOSCheck = check
        fallConfirmationDeadline = check.deadline
        showFallConfirmation = true
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        // Keep counting if the app goes to the background / the screen locks
        autoSOSBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "auto-sos-check") { [weak self] in
            guard let self, self.autoSOSCheck == check else { return }
            // Out of background time: if the server can't take over, send now rather than never
            if !self.autoSOSServerArmed && !check.isTest { self.autoSOSCheckExpired() } else { self.endAutoSOSBackgroundTask() }
        }
        if UIApplication.shared.applicationState != .active {
            pushService.fireAutoSOSNotice(reason: reason, seconds: Int(check.duration))
        }
        let work = DispatchWorkItem { [weak self] in self?.autoSOSCheckExpired() }
        autoSOSWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + check.duration, execute: work)

        if reason == .fall && !isTest {
            autoSOSServerArmed = false
            reportFall(check, outcome: "pending") { [weak self] delivered in
                if delivered != nil, self?.autoSOSCheck == check { self?.autoSOSServerArmed = true }
            }
        }
    }

    /// "I'm OK"
    func dismissFallConfirmation() {
        guard let check = autoSOSCheck else {
            showFallConfirmation = false
            return
        }
        let after = Date().timeIntervalSince(check.startedAt)
        clearAutoSOSCheck()
        if check.reason == .fall { motionService.resolveFall(dismissed: true) }
        if check.isTest {
            showFallTestResult(check, answeredAfter: after)
            return
        }
        guard check.reason == .fall else { return }
        addTimelineEntry(type: .fallDetected, description: LanguageManager.shared.localized("timeline.autosos.dismissed"))
        reportFall(check, outcome: "dismissed", respondedAfter: after) { [weak self] outcome in
            // Too late: the server already sent the SOS (this phone was offline or asleep).
            // Join it here so the person sees it and can end it.
            guard outcome?.outcome == "escalated_by_server" else { return }
            self?.triggerSOS(method: .fallDetection, clientSOSId: check.clientSOSId)
        }
    }

    /// The countdown ran out, or (byPerson) they tapped "I need help — send SOS now".
    func autoSOSCheckExpired(byPerson: Bool = false) {
        guard let check = autoSOSCheck else { return }
        clearAutoSOSCheck()
        if check.reason == .fall { motionService.resolveFall(dismissed: false) }
        if check.isTest {
            showFallTestResult(check, answeredAfter: nil)
            return
        }
        triggerSOS(method: check.reason.sosMethod, clientSOSId: check.clientSOSId)
        if check.reason == .fall {
            reportFall(check, outcome: byPerson ? "help_requested" : "escalated", respondedAfter: Date().timeIntervalSince(check.startedAt))
        }
    }

    /// Back in front after the deadline passed while suspended.
    func resumeAutoSOSCheckIfOverdue() {
        guard let check = autoSOSCheck, Date() >= check.deadline else { return }
        autoSOSCheckExpired()
    }

    /// Settings → "Test fall detection": a recorded fall through the real detector.
    /// In Explore Mode the whole chain runs (the demo SOS goes nowhere).
    func testFallDetection() {
        guard autoSOSCheck == nil else { return }
        fallTestArmed = !isDemo
        motionService.simulateFall()
        // The replay takes well under a second; never let a later real fall count as the test
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.fallTestArmed = false }
    }

    private func clearAutoSOSCheck() {
        autoSOSWork?.cancel()
        autoSOSWork = nil
        autoSOSCheck = nil
        autoSOSServerArmed = false
        showFallConfirmation = false
        fallConfirmationDeadline = nil
        pushService.removeAutoSOSNotice()
        endAutoSOSBackgroundTask()
    }

    private func endAutoSOSBackgroundTask() {
        if autoSOSBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(autoSOSBackgroundTask)
            autoSOSBackgroundTask = .invalid
        }
    }

    private func reportFall(_ check: AutoSOSCheck, outcome: String, respondedAfter: TimeInterval? = nil,
                            done: ((FallEventResponse?) -> Void)? = nil) {
        let location = locationManager.lastReportedLocation ?? locationManager.bestAvailableLocation
        UIDevice.current.isBatteryMonitoringEnabled = true
        let battery = UIDevice.current.batteryLevel
        let m = check.metrics
        let body = FallEventReport(
            clientEventId: check.clientEventId,
            clientSOSId: check.clientSOSId,
            outcome: outcome,
            detectedAt: check.startedAt,
            countdownSec: Int(check.duration),
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            accuracy: location.map { $0.horizontalAccuracy >= 0 ? $0.horizontalAccuracy : nil } ?? nil,
            batteryLevel: battery >= 0 ? Double(battery) : nil,
            metrics: m.map { .init(peakImpactG: $0.peakImpactG, freeFallMs: $0.freeFallMs, orientationChangeDeg: $0.orientationChangeDeg,
                                   stillnessVariance: $0.stillnessVariance, detector: FallDetector.FallMetrics.detectorName) },
            respondedAfterSec: respondedAfter
        )
        if outcome == "pending" {
            // Queued first (survives the app being killed), then sent at once
            apiClient.postQueued("/v1/safety-events/fall", body: body) { delivered in
                DispatchQueue.main.async { done?(delivered ? FallEventResponse(outcome: "pending", sosEventId: nil) : nil) }
            }
            return
        }
        let api = apiClient
        Task { @MainActor in
            let response: FallEventResponse? = await api.postSOS("/v1/safety-events/fall", body: body)
            done?(response)
        }
    }

    private func showFallTestResult(_ check: AutoSOSCheck, answeredAfter: TimeInterval?) {
        let L = LanguageManager.shared
        var message = answeredAfter.map { String(format: L.localized("fallTest.result.answered"), Int($0.rounded())) }
            ?? L.localized("fallTest.result.expired")
        if let m = check.metrics {
            message += "\n\n" + String(format: L.localized("fallTest.result.sensors"), m.peakImpactG, Int(m.freeFallMs), Int(m.orientationChangeDeg))
        }
        let alert = UIAlertController(title: L.localized("fallTest.result.title"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L.localized("common.ok"), style: .default))
        Self.topViewController()?.present(alert, animated: true)
    }
}
