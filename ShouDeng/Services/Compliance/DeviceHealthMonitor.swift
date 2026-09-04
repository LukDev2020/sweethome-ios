import Foundation
import UIKit
import CoreLocation
import UserNotifications
import Combine

// MARK: - Device Health Monitor
//
// From PDF section 4, "状态降级提示（最高优先级）":
//
//   "最可能导致败诉的场景，不是产品存在缺陷，
//    而是用户以为自己受到保护，实际上并没有。"
//
//   原则：宁可误报状态，不可漏报状态。
//         宁可打扰用户，不可让其误判。
//
// Monitors all degradation triggers from the PDF table:
//   - 定位权限降级或撤销
//   - 通知权限关闭
//   - 后台进程被终止
//   - 设备离线超过阈值
//   - 电量低于 15%
//   - 服务器端故障

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
    private var loggedDegradations: Set<String> = []

    // MARK: - Init

    init(protectedPersonName: String = "被守护者") {
        self.protectedPersonName = protectedPersonName
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
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Periodic check every 30 seconds
        checkTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluateConditions()
        }

        // Check immediately
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
        if locStatus == .denied || locStatus == .restricted {
            warnings.append(
                DisclaimerCopy.Degradation.locationRevoked(personName: protectedPersonName)
            )
            if !loggedDegradations.contains("permission") {
                loggedDegradations.insert("permission")
                ConsentLogger.shared.logDegradation("permission")
            }
        }

        // 2. Battery level — PDF threshold is 15%
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        if batteryLevel >= 0 && batteryLevel <= 0.15 && batteryState != .charging {
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

        // 4. Notification permission
        checkNotificationPermission { [weak self] isAuthorized in
            guard let self else { return }
            if !isAuthorized {
                warnings.append(
                    DisclaimerCopy.Degradation.notificationDisabled(personName: self.protectedPersonName)
                )
                if !self.loggedDegradations.contains("notification") {
                    self.loggedDegradations.insert("notification")
                    ConsentLogger.shared.logDegradation("permission")
                }
            }

            DispatchQueue.main.async {
                // Preserve manually-added warnings (offline, no guardian, server fault)
                let manualIds: Set<String> = ["device_offline", "no_guardian_on_duty", "server_fault"]
                let manualWarnings = self.activeWarnings.filter { manualIds.contains($0.id) }
                self.activeWarnings = warnings + manualWarnings
            }
        }
    }

    private func checkNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        }
    }

    // MARK: - Manual Triggers (called by AppCoordinator)

    func reportDeviceOffline(personName: String, hours: Int) {
        let warning = DisclaimerCopy.Degradation.deviceOffline(
            personName: personName, hours: hours
        )
        ConsentLogger.shared.logDegradation("offline")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeWarnings.removeAll { $0.id == "device_offline" }
            self.activeWarnings.append(warning)
        }
    }

    func reportNoGuardianOnDuty() {
        let warning = DisclaimerCopy.Degradation.noGuardianOnDuty()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.activeWarnings.contains(where: { $0.id == "no_guardian_on_duty" }) {
                self.activeWarnings.append(warning)
            }
        }
    }

    func reportServerFault() {
        let warning = DisclaimerCopy.Degradation.serverFault()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.activeWarnings.contains(where: { $0.id == "server_fault" }) {
                self.activeWarnings.append(warning)
            }
        }
    }

    func clearNoGuardianWarning() {
        DispatchQueue.main.async { [weak self] in
            self?.activeWarnings.removeAll { $0.id == "no_guardian_on_duty" }
        }
    }

    func clearDeviceOfflineWarning() {
        DispatchQueue.main.async { [weak self] in
            self?.activeWarnings.removeAll { $0.id == "device_offline" }
        }
    }

    func clearServerFaultWarning() {
        DispatchQueue.main.async { [weak self] in
            self?.activeWarnings.removeAll { $0.id == "server_fault" }
        }
    }
}
