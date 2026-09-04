import Foundation
import UIKit
import CoreLocation
import Combine

// MARK: - Device Health Monitor
//
// From revised plan, section 5, "最高优先级：状态永不撒谎":
//
//   "最可能导致败诉的场景，不是产品存在缺陷，
//    而是用户以为自己受到保护，实际上并没有。"
//
//   "定位权限被系统降级、后台进程被厂商省电策略终止、
//    设备离线或电量耗尽——上述情形下必须主动、显著地
//    向两端告知，绝不可继续显示绿色的「一切正常」。"
//
// This monitor watches device-level signals and publishes
// degradation warnings that the UI layer renders as banners.

final class DeviceHealthMonitor: ObservableObject {

    // MARK: - Published State

    @Published var activeWarnings: [DisclaimerCopy.Degradation.Warning] = []

    var hasCriticalWarning: Bool {
        activeWarnings.contains { $0.severity == .critical }
    }

    var hasAnyWarning: Bool {
        !activeWarnings.isEmpty
    }

    // MARK: - Dependencies

    private var cancellables = Set<AnyCancellable>()
    private var checkTimer: Timer?
    private let protectedPersonName: String

    // MARK: - Init

    init(protectedPersonName: String = "被守护者") {
        self.protectedPersonName = protectedPersonName
        // Defer monitoring start — don't evaluate until after onboarding
        // to avoid triggering system dialogs during the disclosure flow.
        if UserDefaults.standard.bool(forKey: "onboardingComplete") {
            startMonitoring()
        }
    }

    /// Call after onboarding completes to begin health monitoring.
    func beginMonitoring() {
        startMonitoring()
    }

    deinit {
        checkTimer?.invalidate()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Periodic check every 30 seconds
        checkTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluateConditions()
        }

        // Also check immediately
        evaluateConditions()

        // React to battery changes
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in self?.evaluateConditions() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .sink { [weak self] _ in self?.evaluateConditions() }
            .store(in: &cancellables)

        // React to app becoming active (permissions may have changed)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.evaluateConditions() }
            .store(in: &cancellables)
    }

    // MARK: - Evaluation

    private func evaluateConditions() {
        var warnings: [DisclaimerCopy.Degradation.Warning] = []

        // 1. Location permission
        let locMgr = CLLocationManager()
        let locStatus = locMgr.authorizationStatus
        // Only warn if user has explicitly denied (not if undetermined/first launch)
        if locStatus == .denied || locStatus == .restricted {
            warnings.append(
                DisclaimerCopy.Degradation.locationRevoked(personName: protectedPersonName)
            )
        }

        // 2. Battery level
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        if batteryLevel >= 0 && batteryLevel <= 0.10 && batteryState != .charging {
            warnings.append(
                DisclaimerCopy.Degradation.batteryLow(
                    personName: protectedPersonName,
                    level: Int(batteryLevel * 100)
                )
            )
        }

        // 3. Background refresh
        if UIApplication.shared.backgroundRefreshStatus == .denied {
            warnings.append(
                DisclaimerCopy.Degradation.backgroundRefreshDisabled(personName: protectedPersonName)
            )
        }

        // Update on main thread
        DispatchQueue.main.async { [weak self] in
            self?.activeWarnings = warnings
        }
    }

    // MARK: - Manual Triggers (called by AppCoordinator)

    /// Call when heartbeat indicates the protected person's device is offline.
    func reportDeviceOffline(personName: String, hours: Int) {
        let warning = DisclaimerCopy.Degradation.deviceOffline(
            personName: personName, hours: hours
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Replace existing offline warning if any
            self.activeWarnings.removeAll { $0.id == "device_offline" }
            self.activeWarnings.append(warning)
        }
    }

    /// Call when no guardian is on duty.
    func reportNoGuardianOnDuty() {
        let warning = DisclaimerCopy.Degradation.noGuardianOnDuty()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.activeWarnings.contains(where: { $0.id == "no_guardian_on_duty" }) {
                self.activeWarnings.append(warning)
            }
        }
    }

    /// Call when a guardian comes on duty.
    func clearNoGuardianWarning() {
        DispatchQueue.main.async { [weak self] in
            self?.activeWarnings.removeAll { $0.id == "no_guardian_on_duty" }
        }
    }

    /// Call when device comes back online.
    func clearDeviceOfflineWarning() {
        DispatchQueue.main.async { [weak self] in
            self?.activeWarnings.removeAll { $0.id == "device_offline" }
        }
    }
}
