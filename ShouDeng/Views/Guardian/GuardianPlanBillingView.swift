import SwiftUI
import StoreKit

// MARK: - Screen B6: Plan & Billing
//
// Design from shoudeng-full-design.html:
//   - Current plan card with line items & monthly total
//   - "What this money did this month" panel
//   - Upsell for family package
//   - StoreKit 2 purchase integration

struct GuardianPlanBillingView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    @State private var showRestoreAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 2) {
                    Text("方案与账单")
                        .font(.system(size: 20, weight: .bold))
                    Text("按被守护的人计费")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Current subscription status
                currentPlanCard

                // Available plans
                if !coordinator.storeKitManager.products.isEmpty {
                    plansList
                }

                // Value recap
                valueRecapPanel

                // Restore purchases
                restoreButton

                // Error message
                if let error = coordinator.storeKitManager.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("方案与账单")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await coordinator.storeKitManager.fetchProducts()
            await coordinator.storeKitManager.refreshSubscriptionStatus()
        }
        .alert("恢复购买", isPresented: $showRestoreAlert) {
            Button("确定") {}
        } message: {
            Text(coordinator.storeKitManager.purchasedPlanId != nil
                 ? "已恢复您的订阅"
                 : "未找到可恢复的订阅")
        }
    }

    // MARK: - Current Plan Card

    private var currentPlanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status = coordinator.storeKitManager.subscriptionStatus, status.isActive {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(safe)
                    Text(coordinator.storeKitManager.planName(for: status.productId))
                        .font(.system(size: 14, weight: .semibold))
                }

                if let expires = status.expiresDate {
                    Text("有效期至 \(expires.formatted(.dateTime.year().month().day()))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                if status.willAutoRenew {
                    Text("自动续订已开启")
                        .font(.system(size: 11))
                        .foregroundStyle(safe)
                }
            } else {
                HStack {
                    Image(systemName: "gift")
                        .foregroundStyle(.secondary)
                    Text("免费版")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text("升级获得更强大的守护功能")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Plans List

    private var plansList: some View {
        VStack(spacing: 8) {
            ForEach(coordinator.storeKitManager.products, id: \.id) { product in
                planCard(product)
            }
        }
    }

    private func planCard(_ product: Product) -> some View {
        let planId = coordinator.storeKitManager.planId(for: product)
        let isCurrentPlan = coordinator.storeKitManager.purchasedPlanId == planId

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.storeKitManager.planName(for: product.id))
                        .font(.system(size: 14, weight: .semibold))
                    Text(planDescription(planId))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(product.displayPrice)
                        .font(.system(size: 15, weight: .bold, design: .serif))
                    Text("/月")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if isCurrentPlan {
                Text("当前方案")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(safe)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(safe.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                Button {
                    Task {
                        let success = await coordinator.storeKitManager.purchase(product)
                        if success {
                            await coordinator.fetchSubscription()
                        }
                    }
                } label: {
                    Text("订阅")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(pro)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(coordinator.storeKitManager.isLoading)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentPlan ? safe.opacity(0.5) : Color(.separator).opacity(0.3), lineWidth: isCurrentPlan ? 2 : 1)
        )
    }

    private func planDescription(_ planId: String) -> String {
        switch planId {
        case "guardian_team": return "无限守护者 · 90天时间线 · 值班表 · PDF导出"
        case "pro_response": return "语音呼叫升级 · 短信回退 · 优先支持"
        case "family_bundle": return "全部Pro功能 · 最多4位被守护者 · 家庭仪表板"
        default: return ""
        }
    }

    // MARK: - Value Recap

    private var valueRecapPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本月这笔钱做了什么")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            valueRow("响应中心待命", value: "720 小时")
            valueRow("失联预警拦截", value: "3 次")
            valueRow("覆盖的时区缺口", value: "每日 4 小时")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func valueRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Restore Button

    private var restoreButton: some View {
        Button {
            Task {
                await coordinator.storeKitManager.restorePurchases()
                showRestoreAlert = true
            }
        } label: {
            Text("恢复购买")
                .font(.system(size: 13))
                .foregroundStyle(pro)
        }
        .disabled(coordinator.storeKitManager.isLoading)
        .padding(.top, 4)
    }
}
