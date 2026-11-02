import SwiftUI
import StoreKit

// MARK: - Build Channel
//
// TestFlight vs App Store. Decided at compile time: the `Beta` build configuration
// (Release + SWIFT_ACTIVE_COMPILATION_CONDITIONS = BETA) is archived for TestFlight,
// `Release` for the App Store (docs/ops/RELEASE.md). Nothing below `#if BETA` is
// compiled into a Release binary.
//
// In a Beta build, SOS is simulated by default so testers don't alarm their families;
// they can opt in to real SOS in Settings. As a safety net, a Beta binary installed from
// the App Store (production AppTransaction) behaves like Release: real SOS, no banner.

final class BuildChannel: ObservableObject {
    static let shared = BuildChannel()

    /// UserDefaults key of the TestFlight "real SOS" switch (default off).
    static let realSOSKey = "beta.realSOSEnabled"

    #if BETA
    static let isBetaBuild = true
    #else
    static let isBetaBuild = false
    #endif

    /// A Beta binary that the App Store installed — never treat it as a test build.
    @Published private(set) var isAppStoreInstall = false

    private init() {}

    /// Beta-only UI and behaviour (banner, simulated SOS, developer switches) is active.
    var betaFeaturesActive: Bool { Self.isBetaBuild && !isAppStoreInstall }

    /// SOS is simulated (no server call, nobody is notified).
    var simulatesSOS: Bool {
        betaFeaturesActive && !UserDefaults.standard.bool(forKey: Self.realSOSKey)
    }

    /// Reads the install's App Store environment (Beta builds only; cached by StoreKit).
    func refreshInstallEnvironment() async {
        guard Self.isBetaBuild else { return }
        if case .verified(let transaction)? = try? await AppTransaction.shared,
           transaction.environment == .production {
            await MainActor.run { isAppStoreInstall = true }
        }
    }
}

#if BETA

// MARK: - TestFlight banner

struct BetaBanner: View {
    @ObservedObject private var channel = BuildChannel.shared
    @AppStorage(BuildChannel.realSOSKey) private var realSOS = false

    var body: some View {
        if channel.betaFeaturesActive {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                    .font(.caption)
                Text("TestFlight 测试版")
                    .font(.caption.bold())
                Text(realSOS ? "· 真实 SOS 已开启，会通知家人" : "· SOS/跌倒升级走模拟通道")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(realSOS ? Color.red : Color.orange)
            .accessibilityIdentifier("beta.banner")
        }
    }
}

// MARK: - TestFlight developer settings

struct BetaDeveloperPanel: View {
    @ObservedObject private var channel = BuildChannel.shared
    @AppStorage(BuildChannel.realSOSKey) private var realSOS = false

    var body: some View {
        if channel.betaFeaturesActive {
            VStack(alignment: .leading, spacing: 8) {
                Text("TestFlight 开发者选项")
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                Toggle(isOn: $realSOS) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("真实 SOS（会通知家人）")
                            .font(.scaled(size: 13, weight: .medium))
                        Text("关闭时 SOS 只在本机模拟，不会发送推送、短信或电话。Real SOS: guardians get push, SMS and calls.")
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.red)
                .accessibilityIdentifier("beta.realSOS")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
        }
    }
}

#endif
