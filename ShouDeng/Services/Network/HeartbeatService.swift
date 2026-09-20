import Foundation
import UIKit

// MARK: - Heartbeat Service
//
// Collects passive "alive" signals from the device and reports to server.
// These signals feed into the BaselineScorer's phone inactivity factor.
//
// Signal sources:
//   1. App foreground events (applicationDidBecomeActive)
//   2. Significant location change wake-ups
//   3. Silent push wake-ups (server sends every ~30 min)
//   4. Push notification receipts (user interacted with notification)
//   5. Geofence region events
//   6. Watch sync events
//
// On iOS, we can't monitor screen-on/screen-off directly.
// But the aggregate of these signals lets us infer "phone is active"
// vs "phone has been sitting untouched for hours."

final class HeartbeatService {

    // MARK: - Configuration

    struct Config {
        var maxHeartbeatsPerHour: Int = 12        // Don't flood the server
        var minIntervalBetweenBeats: TimeInterval = 60  // At least 1 min between beats
        var batteryReportThreshold: Double = 0.05  // Report when battery changes by > 5%
    }

    // MARK: - Properties

    private let config: Config
    private var lastBeatTime: Date?
    private var lastBatteryLevel: Double?
    private var beatsThisHour: Int = 0
    private var hourResetTimer: Timer?

    var userId: String = ""
    var onHeartbeat: ((HeartbeatSignal) -> Void)?

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Start

    func start() {
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Reset hourly counter
        hourResetTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.beatsThisHour = 0
        }

        // Record initial state
        recordBeat(source: .appForeground)
    }

    func stop() {
        hourResetTimer?.invalidate()
        hourResetTimer = nil
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    // MARK: - Record Heartbeat

    /// Call this from various parts of the app when "something happened"
    func recordBeat(source: HeartbeatSource, location: Location? = nil) {
        let now = Date()

        // Rate limiting
        if let lastTime = lastBeatTime,
           now.timeIntervalSince(lastTime) < config.minIntervalBetweenBeats {
            return
        }

        if beatsThisHour >= config.maxHeartbeatsPerHour {
            return
        }

        // Gather current device state
        let batteryLevel = Double(UIDevice.current.batteryLevel)
        let batteryState: BatteryState
        switch UIDevice.current.batteryState {
        case .charging: batteryState = .charging
        case .full: batteryState = .full
        case .unplugged: batteryState = .unplugged
        default: batteryState = .unknown
        }

        let signal = HeartbeatSignal(
            userId: userId,
            timestamp: now,
            source: source,
            batteryLevel: batteryLevel >= 0 ? batteryLevel : nil,
            batteryState: batteryLevel >= 0 ? batteryState : nil,
            location: location
        )

        lastBeatTime = now
        lastBatteryLevel = batteryLevel
        beatsThisHour += 1

        onHeartbeat?(signal)
    }

    // MARK: - App Lifecycle Hooks

    /// Call from AppDelegate.applicationDidBecomeActive
    func appDidBecomeActive() {
        recordBeat(source: .appForeground)
    }

    /// Call from AppDelegate.didReceiveRemoteNotification (silent push)
    func silentPushReceived() {
        recordBeat(source: .silentPush)
    }

    /// Call when a visible push notification was interacted with
    func pushReceiptRecorded() {
        recordBeat(source: .pushReceipt)
    }

    /// Call from significant location change callback
    func significantLocationChanged(location: Location) {
        recordBeat(source: .significantLocation, location: location)
    }

    /// Call from geofence enter/exit
    func regionEventOccurred(location: Location) {
        recordBeat(source: .regionEvent, location: location)
    }

    /// Call when Watch sends data via WatchConnectivity
    func watchSyncReceived() {
        recordBeat(source: .watchSync)
    }

    // MARK: - Battery Alert

    /// Check if battery is critically low and dropping
    func checkBatteryAlert() -> BatteryAlert? {
        let level = Double(UIDevice.current.batteryLevel)
        guard level >= 0 else { return nil }

        let state = UIDevice.current.batteryState

        if level < 0.05 && state == .unplugged {
            return BatteryAlert(
                level: level,
                isCharging: false,
                estimatedMinutesRemaining: estimateRemainingMinutes(level: level),
                message: String(format: "电量仅%.0f%%，即将关机", level * 100)
            )
        } else if level < 0.15 && state == .unplugged {
            return BatteryAlert(
                level: level,
                isCharging: false,
                estimatedMinutesRemaining: estimateRemainingMinutes(level: level),
                message: String(format: "电量%.0f%%", level * 100)
            )
        }

        return nil
    }

    struct BatteryAlert {
        let level: Double
        let isCharging: Bool
        let estimatedMinutesRemaining: Int?
        let message: String
    }

    /// Rough battery life estimate based on current level
    /// In production, use historical drain rate for this user
    private func estimateRemainingMinutes(level: Double) -> Int? {
        // Very rough: assume ~10 hours from 100% to 0% with normal use
        let totalMinutes = 600.0
        return Int(level * totalMinutes)
    }
}
