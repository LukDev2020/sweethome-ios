import SwiftUI
import StoreKit

// MARK: - Plan & Billing
//
// Redesigned subscription page:
//   - Monthly / Yearly toggle
//   - Duo (双人守护) and Family (家庭守护) plan cards with benefits
//   - Feature comparison table
//   - Restore purchases
//   - Manage subscription (App Store link)

struct GuardianPlanBillingView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var billingCycle: BillingCycle = .monthly
    @State private var showRestoreAlert = false

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let accent = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let warm = Color(red: 232/255, green: 165/255, blue: 72/255)

    enum BillingCycle: String, CaseIterable {
        case monthly = "月付"
        case yearly = "年付"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroSection
                billingToggle
                planCards
                featureComparison
                enterpriseCTA
                footerSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("选择方案")
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

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 36))
                .foregroundStyle(accent)
                .padding(.top, 12)

            Text("守护，不止一种方式")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ink)

            Text("选择适合您家庭的守护方案")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            ForEach(BillingCycle.allCases, id: \.self) { cycle in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { billingCycle = cycle }
                } label: {
                    HStack(spacing: 4) {
                        Text(cycle.rawValue)
                            .font(.system(size: 14, weight: .medium))
                        if cycle == .yearly {
                            Text("省20%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(warm)
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(billingCycle == cycle ? .white : ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        billingCycle == cycle
                            ? AnyShapeStyle(accent)
                            : AnyShapeStyle(Color.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Plan Cards

    private var planCards: some View {
        VStack(spacing: 12) {
            duoPlanCard
            familyPlanCard
            familyPlusPlanCard
        }
    }

    private var duoPlanCard: some View {
        let duo = coordinator.storeKitManager.duoProducts()
        let product = billingCycle == .monthly ? duo.monthly : duo.yearly
        let isCurrent = coordinator.storeKitManager.purchasedPlanId == "duo"

        return PlanCardView(
            planName: "双人守护",
            subtitle: "守护你最重要的人",
            icon: "person.2.fill",
            iconColor: safe,
            price: product?.displayPrice ?? (billingCycle == .monthly ? "¥18" : "¥168"),
            period: billingCycle == .monthly ? "/月" : "/年",
            isCurrent: isCurrent,
            isPopular: false,
            accentColor: safe,
            benefits: [
                ("person.fill.checkmark", "守护 1 位家人"),
                ("person.2", "最多 3 位守护者"),
                ("clock.arrow.circlepath", "90 天守护时间线"),
                ("calendar.badge.clock", "值班排班表"),
                ("phone.arrow.up.right", "SOS 语音呼叫升级"),
                ("doc.richtext", "事件报告 PDF 导出"),
            ],
            onSubscribe: {
                guard let product else { return }
                Task {
                    let success = await coordinator.storeKitManager.purchase(product)
                    if success { await coordinator.fetchSubscription() }
                }
            },
            isLoading: coordinator.storeKitManager.isLoading
        )
    }

    private var familyPlanCard: some View {
        let family = coordinator.storeKitManager.familyProducts()
        let product = billingCycle == .monthly ? family.monthly : family.yearly
        let isCurrent = coordinator.storeKitManager.purchasedPlanId == "family"

        return PlanCardView(
            planName: "家庭守护",
            subtitle: "全家人的安全网",
            icon: "house.fill",
            iconColor: accent,
            price: product?.displayPrice ?? (billingCycle == .monthly ? "¥38" : "¥358"),
            period: billingCycle == .monthly ? "/月" : "/年",
            isCurrent: isCurrent,
            isPopular: true,
            accentColor: accent,
            benefits: [
                ("person.3.fill", "守护最多 4 位家人"),
                ("person.fill.badge.plus", "无限守护者"),
                ("clock.arrow.circlepath", "90 天守护时间线"),
                ("calendar.badge.clock", "值班排班表"),
                ("phone.arrow.up.right", "SOS 语音呼叫升级"),
                ("message.fill", "短信回退通知"),
                ("doc.richtext", "事件报告 PDF 导出"),
                ("chart.bar.fill", "家庭安全仪表板"),
            ],
            onSubscribe: {
                guard let product else { return }
                Task {
                    let success = await coordinator.storeKitManager.purchase(product)
                    if success { await coordinator.fetchSubscription() }
                }
            },
            isLoading: coordinator.storeKitManager.isLoading
        )
    }

    private var familyPlusPlanCard: some View {
        let fp = coordinator.storeKitManager.familyPlusProducts()
        let product = billingCycle == .monthly ? fp.monthly : fp.yearly
        let isCurrent = coordinator.storeKitManager.purchasedPlanId == "familyplus"

        return PlanCardView(
            planName: "家庭守护+",
            subtitle: "大家庭的全面守护",
            icon: "person.3.sequence.fill",
            iconColor: warm,
            price: product?.displayPrice ?? (billingCycle == .monthly ? "¥58" : "¥548"),
            period: billingCycle == .monthly ? "/月" : "/年",
            isCurrent: isCurrent,
            isPopular: false,
            accentColor: warm,
            benefits: [
                ("person.3.fill", "守护最多 8 位家人"),
                ("person.fill.badge.plus", "无限守护者"),
                ("clock.arrow.circlepath", "180 天守护时间线"),
                ("calendar.badge.clock", "值班排班表"),
                ("phone.arrow.up.right", "SOS 语音呼叫升级"),
                ("message.fill", "短信回退通知"),
                ("doc.richtext", "事件报告 PDF 导出"),
                ("chart.bar.fill", "家庭安全仪表板"),
                ("map.fill", "位置轨迹 GPX 导出"),
                ("headphones", "优先客服支持"),
            ],
            onSubscribe: {
                guard let product else { return }
                Task {
                    let success = await coordinator.storeKitManager.purchase(product)
                    if success { await coordinator.fetchSubscription() }
                }
            },
            isLoading: coordinator.storeKitManager.isLoading
        )
    }

    // MARK: - Feature Comparison

    private var featureComparison: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("方案对比")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Header row
            HStack(spacing: 0) {
                Text("功能")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("免费")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
                Text("双人")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(safe)
                    .frame(width: 40)
                Text("家庭")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 40)
                Text("家庭+")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(warm)
                    .frame(width: 40)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider().padding(.horizontal, 12)

            comparisonRow("守护者", free: "1", duo: "3", family: "∞", plus: "∞")
            comparisonRow("被守护者", free: "1", duo: "1", family: "4", plus: "8")
            comparisonRow("时间线", free: "24h", duo: "90天", family: "90天", plus: "180天")
            comparisonRow("SOS 求助", free: true, duo: true, family: true, plus: true)
            comparisonRow("报平安", free: true, duo: true, family: true, plus: true)
            comparisonRow("值班排班", free: false, duo: true, family: true, plus: true)
            comparisonRow("语音升级", free: false, duo: true, family: true, plus: true)
            comparisonRow("短信回退", free: false, duo: false, family: true, plus: true)
            comparisonRow("PDF 导出", free: false, duo: true, family: true, plus: true)
            comparisonRow("GPX 导出", free: false, duo: false, family: false, plus: true)
            comparisonRow("仪表板", free: false, duo: false, family: true, plus: true)
            comparisonRow("优先客服", free: false, duo: false, family: false, plus: true)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func comparisonRow(_ feature: String, free: String, duo: String, family: String, plus: String) -> some View {
        HStack(spacing: 0) {
            Text(feature)
                .font(.system(size: 11))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(free)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 40)
            Text(duo)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(safe)
                .frame(width: 40)
            Text(family)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 40)
            Text(plus)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(warm)
                .frame(width: 40)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func comparisonRow(_ feature: String, free: Bool, duo: Bool, family: Bool, plus: Bool) -> some View {
        HStack(spacing: 0) {
            Text(feature)
                .font(.system(size: 11))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            checkmark(free, color: .secondary).frame(width: 40)
            checkmark(duo, color: safe).frame(width: 40)
            checkmark(family, color: accent).frame(width: 40)
            checkmark(plus, color: warm).frame(width: 40)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func checkmark(_ on: Bool, color: Color) -> some View {
        Image(systemName: on ? "checkmark" : "minus")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(on ? color : Color(.systemGray4))
    }

    // MARK: - Enterprise CTA

    private var enterpriseCTA: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(ink.opacity(0.6))
                Text("超过 8 人？")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
            }
            Text("养老院、社区组织等大型团体，我们提供定制方案与批量折扣")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {} label: {
                Text("联系我们")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(accent.opacity(0.4), lineWidth: 1)
                    )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            // Error
            if let error = coordinator.storeKitManager.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Manage subscription (for existing subscribers)
            if coordinator.storeKitManager.subscriptionStatus?.isActive == true {
                Button {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gear")
                            .font(.system(size: 12))
                        Text("管理订阅")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(accent)
                }
            }

            // Restore
            Button {
                Task {
                    await coordinator.storeKitManager.restorePurchases()
                    showRestoreAlert = true
                }
            } label: {
                Text("恢复购买")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .disabled(coordinator.storeKitManager.isLoading)

            // Legal
            Text("订阅将通过您的 Apple ID 账户扣款。除非在当前订阅期结束前至少 24 小时关闭自动续订，否则订阅将自动续订。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }
}

// MARK: - Plan Card Component

private struct PlanCardView: View {
    let planName: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let price: String
    let period: String
    let isCurrent: Bool
    let isPopular: Bool
    let accentColor: Color
    let benefits: [(icon: String, text: String)]
    let onSubscribe: () -> Void
    let isLoading: Bool

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 15))
                            .foregroundStyle(iconColor)
                        Text(planName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(ink)
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isPopular {
                    Text("推荐")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accentColor)
                        .clipShape(Capsule())
                }
            }

            // Price
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(price)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Text(period)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Divider
            Rectangle()
                .fill(Color(.separator).opacity(0.3))
                .frame(height: 1)

            // Benefits
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(benefits.enumerated()), id: \.offset) { _, benefit in
                    HStack(spacing: 8) {
                        Image(systemName: benefit.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(accentColor)
                            .frame(width: 20)
                        Text(benefit.text)
                            .font(.system(size: 13))
                            .foregroundStyle(ink)
                    }
                }
            }

            // CTA
            if isCurrent {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                        Text("当前方案")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(accentColor)
                    .padding(.vertical, 12)
                    Spacer()
                }
                .background(accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Button(action: onSubscribe) {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("立即订阅")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .background(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isLoading)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrent ? accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}
