import SwiftUI

/// Reusable paywall overlay shown when a user tries to access a paid feature.
/// Usage: `.subscriptionGate(feature: "duty_schedule", coordinator: coordinator)`
struct SubscriptionGateView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let feature: String
    let featureName: String
    let onDismiss: () -> Void

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    private var requiredPlan: String {
        StoreKitManager.minimumPlan(for: feature)
    }

    private var planLabel: String {
        coordinator.storeKitManager.planDisplayName(for: requiredPlan)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(pro)

                Text(featureName)
                    .font(.scaled(size: 20, weight: .bold))
                    .foregroundStyle(ink)

                Text("此功能需要\(planLabel)或更高方案")
                    .font(.scaled(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                NavigationLink {
                    GuardianPlanBillingView()
                        .environmentObject(coordinator)
                } label: {
                    Text("查看方案")
                        .font(.scaled(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(pro)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button("稍后再说") {
                    onDismiss()
                }
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 20, y: 8)
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - View Modifier for inline gating

struct SubscriptionGateModifier: ViewModifier {
    @EnvironmentObject var coordinator: AppCoordinator
    let feature: String
    let featureName: String

    func body(content: Content) -> some View {
        if coordinator.storeKitManager.canAccessFeature(feature) {
            content
        } else {
            SubscriptionGateView(
                feature: feature,
                featureName: featureName,
                onDismiss: {}
            )
            .environmentObject(coordinator)
        }
    }
}

extension View {
    /// Gates this view behind a subscription feature check.
    /// Shows paywall if user's plan doesn't include the feature.
    func subscriptionGate(feature: String, featureName: String) -> some View {
        modifier(SubscriptionGateModifier(feature: feature, featureName: featureName))
    }
}
