import Foundation

// MARK: - Crash Reporter
//
// Lightweight crash reporting for production monitoring.
// Captures uncaught exceptions and signal-based crashes,
// persists crash logs to disk, and uploads on next launch.
//
// For a safety-critical app, knowing when the app crashes is essential —
// a crash during SOS escalation could be life-threatening.

final class CrashReporter {

    static let shared = CrashReporter()

    private let crashLogDir: URL
    private let maxLogs = 20

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        crashLogDir = docs.appendingPathComponent("crash_logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: crashLogDir, withIntermediateDirectories: true)
    }

    // MARK: - Install Handlers

    func install() {
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handleException(exception)
        }

        // Signal handlers for SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP
        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP]
        for sig in signals {
            signal(sig) { signum in
                CrashReporter.shared.handleSignal(signum)
            }
        }
    }

    // MARK: - Handle Exception

    private func handleException(_ exception: NSException) {
        let report = CrashReport(
            type: "exception",
            name: exception.name.rawValue,
            reason: exception.reason ?? "unknown",
            callStack: exception.callStackSymbols,
            timestamp: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: deviceModel()
        )
        saveCrashReport(report)
    }

    // MARK: - Handle Signal

    private func handleSignal(_ signal: Int32) {
        let signalName: String
        switch signal {
        case SIGABRT: signalName = "SIGABRT"
        case SIGSEGV: signalName = "SIGSEGV"
        case SIGBUS:  signalName = "SIGBUS"
        case SIGFPE:  signalName = "SIGFPE"
        case SIGILL:  signalName = "SIGILL"
        case SIGTRAP: signalName = "SIGTRAP"
        default:      signalName = "SIG\(signal)"
        }

        let callStack = Thread.callStackSymbols

        let report = CrashReport(
            type: "signal",
            name: signalName,
            reason: "Signal \(signal) received",
            callStack: callStack,
            timestamp: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: deviceModel()
        )
        saveCrashReport(report)

        // Re-raise the signal so the system handles it normally
        Darwin.signal(signal, SIG_DFL)
        Darwin.raise(signal)
    }

    // MARK: - Save to Disk

    private func saveCrashReport(_ report: CrashReport) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        guard let data = try? encoder.encode(report) else { return }

        let filename = "crash_\(Int(report.timestamp.timeIntervalSince1970)).json"
        let fileURL = crashLogDir.appendingPathComponent(filename)

        // Synchronous write — we're in a crash handler, must be fast
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Upload Pending Crashes

    func uploadPendingCrashes(using apiClient: APIClient) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: crashLogDir, includingPropertiesForKeys: nil) else { return }

        let crashFiles = files.filter { $0.pathExtension == "json" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }

        for file in crashFiles {
            guard let data = try? Data(contentsOf: file),
                  let report = try? JSONDecoder().decode(CrashReport.self, from: data) else {
                try? fm.removeItem(at: file)
                continue
            }

            apiClient.postQueued("/v1/diagnostics/crash", body: report)

            // Remove after queueing
            try? fm.removeItem(at: file)
        }

        // Trim old logs if somehow accumulated
        if let remaining = try? fm.contentsOfDirectory(at: crashLogDir, includingPropertiesForKeys: nil),
           remaining.count > maxLogs {
            let sorted = remaining.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in sorted.prefix(remaining.count - maxLogs) {
                try? fm.removeItem(at: file)
            }
        }
    }

    // MARK: - Device Model

    private func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }
}

// MARK: - Crash Report Model

struct CrashReport: Codable {
    let type: String       // "exception" or "signal"
    let name: String       // Exception name or signal name
    let reason: String
    let callStack: [String]
    let timestamp: Date
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let deviceModel: String
}
