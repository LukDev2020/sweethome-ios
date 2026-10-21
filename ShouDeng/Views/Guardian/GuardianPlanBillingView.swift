import SwiftUI
import StoreKit

// MARK: - Plan & Billing
//
// Subscription page aligned with pricing doc:
//   - Free / 单人关注版 (single) ¥10/月 / 家庭版 (family) ¥30/月 / 企业版 (ultimate) ¥128/月
//   - Plan IDs match StoreKitManager and backend PLANS
//   - Monthly / Yearly toggle (yearly saves ~20%)
//   - Payment methods: Apple Pay, Credit Card, Alipay, WeChat Pay, PayPal
//   - Feature comparison table
//   - Only guardians pay

struct GuardianPlanBillingView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var billingCycle: BillingCycle = .monthly
    @State private var selectedPlan: PlanTier = .single
    @State private var showRestoreAlert = false
    @State private var showPaymentSheet = false
    @State private var showPaymentSuccess = false

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let accent = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let warm = Color(red: 232/255, green: 165/255, blue: 72/255)

    enum BillingCycle: String, CaseIterable {
        case monthly = "月付"
        case yearly = "年付"
    }

    enum PlanTier: String {
        case single, family, ultimate
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroSection
                currentPlanBanner
                billingToggle
                planCards
                paymentMethodSection
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
        .alert("订阅成功", isPresented: $showPaymentSuccess) {
            Button("确定") {}
        } message: {
            Text("您已成功订阅，守护功能已全面开启！")
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .font(.scaled(size: 36))
                .foregroundStyle(accent)
                .padding(.top, 12)

            Text("守护，不止一种方式")
                .font(.scaled(size: 22, weight: .bold))
                .foregroundStyle(ink)

            Text("仅守护者需要付费 · 按家庭计费")
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Current Plan Banner

    @ViewBuilder
    private var currentPlanBanner: some View {
        if let status = coordinator.storeKitManager.subscriptionStatus, status.isActive {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.scaled(size: 18))
                    .foregroundStyle(safe)
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前方案：\(coordinator.storeKitManager.planDisplayName(for: status.planId))")
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundStyle(ink)
                    if let expires = status.expiresDate {
                        Text("有效期至 \(expires.formatted(.dateTime.year().month().day()))")
                            .font(.scaled(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(safe.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(safe.opacity(0.3), lineWidth: 1)
            )
        }
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
                            .font(.scaled(size: 14, weight: .medium))
                        if cycle == .yearly {
                            Text("省20%")
                                .font(.scaled(size: 12, weight: .bold))
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
            singlePlanCard
            familyPlanCard
            ultimatePlanCard
        }
    }

    private var singlePlanCard: some View {
        let single = coordinator.storeKitManager.products(forPlan: "single")
        let product = billingCycle == .monthly ? single.monthly : single.yearly
        let isCurrent = coordinator.storeKitManager.purchasedPlanId == "single"

        return PlanCardView(
            planName: "单人关注版",
            subtitle: "守护你最重要的人",
            icon: "person.fill.checkmark",
            iconColor: safe,
            price: product?.displayPrice ?? (billingCycle == .monthly ? "¥10" : "¥96"),
            usdPrice: billingCycle == .monthly ? "$1.49" : "$14.99",
            period: billingCycle == .monthly ? "/月" : "/年",
            isCurrent: isCurrent,
            isSelected: selectedPlan == .single && !isCurrent,
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
            onSelect: { selectedPlan = .single },
            onSubscribe: { subscribeToPlan("single", product: product) },
            isLoading: coordinator.storeKitManager.isLoading
        )
    }

    private var familyPlanCard: some View {
        let family = coordinator.storeKitManager.products(forPlan: "family")
        let product = billingCycle == .monthly ? family.monthly : family.yearly
        let isCurrent = coordinator.storeKitManager.purchasedPlanId == "family"

        return PlanCardView(
            planName: "家庭版",
            subtitle: "全家人的安全网",
            icon: "house.fill",
            iconColor: accent,
            price: product?.displayPrice ?? (billingCycle == .monthly ? "¥30" : "¥288"),
            usdPrice: billingCycle == .monthly ? "$4.99" : "$49.99",
            period: billingCycle == .monthly ? "/月" : "/年",
            isCurrent: isCurrent,
            isSelected: selectedPlan == .family && !isCurrent,
            isPopular: true,
            accentColor: accent,
            benefits: [
                ("person.3.fill", "守护最多 4 位家人"),
                ("person.fill.badge.plus", "无限守护者"),
                ("clock.arrow.circlepath", "180 天守护时间线"),
                ("calendar.badge.clock", "值班排班表"),
                ("phone.arrow.up.right", "SOS 语音呼叫升级"),
                ("message.fill", "短信回退通知"),
                ("doc.richtext", "事件报告 PDF 导出"),
                ("chart.bar.fill", "家庭安全仪表板"),
                ("map.fill", "位置轨迹 GPX 导出"),
            ],
            onSelect: { selectedPlan = .family },
            onSubscribe: { subscribeToPlan("family", product: product) },
            isLoading: coordinator.storeKitManager.isLoading
        )
    }

    private var ultimatePlanCard: some View {
        let ultimate = coordinator.storeKitManager.products(forPlan: "ultimate")
        let product = billingCycle == .monthly ? ultimate.monthly : ultimate.yearly
        let isCurrent = coordinator.storeKitManager.purchasedPlanId == "ultimate"

        return PlanCardView(
            planName: "企业版",
            subtitle: "无限守护，全面覆盖",
            icon: "building.2.fill",
            iconColor: warm,
            price: product?.displayPrice ?? (billingCycle == .monthly ? "¥128" : "¥1,228"),
            usdPrice: billingCycle == .monthly ? "$19.99" : "$199.99",
            period: billingCycle == .monthly ? "/月" : "/年",
            isCurrent: isCurrent,
            isSelected: selectedPlan == .ultimate && !isCurrent,
            isPopular: false,
            accentColor: warm,
            benefits: [
                ("person.3.fill", "无限被守护者"),
                ("person.fill.badge.plus", "无限守护者"),
                ("clock.arrow.circlepath", "365 天守护时间线"),
                ("calendar.badge.clock", "值班排班表"),
                ("phone.arrow.up.right", "SOS 语音呼叫升级"),
                ("message.fill", "短信回退通知"),
                ("doc.richtext", "事件报告 PDF 导出"),
                ("chart.bar.fill", "家庭安全仪表板"),
                ("map.fill", "位置轨迹 GPX 导出"),
                ("headphones", "专属客服经理"),
            ],
            onSelect: { selectedPlan = .ultimate },
            onSubscribe: { subscribeToPlan("ultimate", product: product) },
            isLoading: coordinator.storeKitManager.isLoading
        )
    }

    private func subscribeToPlan(_ planId: String, product: Product?) {
        guard let product else { return }
        Task {
            let success = await coordinator.storeKitManager.purchase(product)
            if success {
                await coordinator.fetchSubscription()
                showPaymentSuccess = true
            }
        }
    }

    // MARK: - Payment Info Section

    private var paymentMethodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("支付方式")
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(ink)

            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                    .font(.scaled(size: 22))
                    .foregroundStyle(ink)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("通过 App Store 订阅")
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(ink)
                    Text("支持 Apple Pay、信用卡、借记卡、Apple ID 余额")
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.scaled(size: 16))
                    .foregroundStyle(safe)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Feature Comparison

    private var featureComparison: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("方案对比")
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Header row
            HStack(spacing: 0) {
                Text("功能")
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("免费")
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
                Text("单人")
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(safe)
                    .frame(width: 40)
                Text("家庭")
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 40)
                Text("企业")
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(warm)
                    .frame(width: 40)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider().padding(.horizontal, 12)

            comparisonRow("守护者", free: "1", single: "3", family: "∞", ultimate: "∞")
            comparisonRow("被守护者", free: "1", single: "1", family: "4", ultimate: "∞")
            comparisonRow("时间线", free: "24h", single: "90天", family: "180天", ultimate: "365天")
            comparisonRow("SOS 求助", free: true, single: true, family: true, ultimate: true)
            comparisonRow("报平安", free: true, single: true, family: true, ultimate: true)
            comparisonRow("值班排班", free: false, single: true, family: true, ultimate: true)
            comparisonRow("语音升级", free: false, single: true, family: true, ultimate: true)
            comparisonRow("短信回退", free: false, single: false, family: true, ultimate: true)
            comparisonRow("PDF 导出", free: false, single: true, family: true, ultimate: true)
            comparisonRow("GPX 导出", free: false, single: false, family: true, ultimate: true)
            comparisonRow("仪表板", free: false, single: false, family: true, ultimate: true)
            comparisonRow("优先客服", free: false, single: false, family: false, ultimate: true)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func comparisonRow(_ feature: String, free: String, single: String, family: String, ultimate: String) -> some View {
        HStack(spacing: 0) {
            Text(feature)
                .font(.scaled(size: 12))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(free)
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 40)
            Text(single)
                .font(.scaled(size: 12, weight: .medium))
                .foregroundStyle(safe)
                .frame(width: 40)
            Text(family)
                .font(.scaled(size: 12, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 40)
            Text(ultimate)
                .font(.scaled(size: 12, weight: .medium))
                .foregroundStyle(warm)
                .frame(width: 40)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func comparisonRow(_ feature: String, free: Bool, single: Bool, family: Bool, ultimate: Bool) -> some View {
        HStack(spacing: 0) {
            Text(feature)
                .font(.scaled(size: 12))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            checkmark(free, color: .secondary).frame(width: 40)
            checkmark(single, color: safe).frame(width: 40)
            checkmark(family, color: accent).frame(width: 40)
            checkmark(ultimate, color: warm).frame(width: 40)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func checkmark(_ on: Bool, color: Color) -> some View {
        Image(systemName: on ? "checkmark" : "minus")
            .font(.scaled(size: 11, weight: .semibold))
            .foregroundStyle(on ? color : Color(.systemGray4))
    }

    // MARK: - Enterprise CTA

    private var enterpriseCTA: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .font(.scaled(size: 16))
                    .foregroundStyle(ink.opacity(0.6))
                Text("需要定制方案？")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
            }
            Text("超大型组织、特殊需求或批量折扣，请联系我们获取专属报价")
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: "mailto:support@shoudeng.app?subject=定制方案咨询") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("联系我们")
                    .font(.scaled(size: 14, weight: .medium))
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
                    .font(.scaled(size: 13))
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
                            .font(.scaled(size: 12))
                        Text("管理订阅")
                            .font(.scaled(size: 13))
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
                    .font(.scaled(size: 13))
                    .foregroundStyle(.secondary)
            }
            .disabled(coordinator.storeKitManager.isLoading)

            // Legal
            Text("订阅费用将通过您的 Apple ID 账户扣款，支持 Apple Pay、信用卡、借记卡及 Apple ID 余额。除非在当前订阅期结束前至少 24 小时关闭自动续订，否则订阅将自动续订。")
                .font(.scaled(size: 12))
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
    let usdPrice: String
    let period: String
    let isCurrent: Bool
    let isSelected: Bool
    let isPopular: Bool
    let accentColor: Color
    let benefits: [(icon: String, text: String)]
    let onSelect: () -> Void
    let onSubscribe: () -> Void
    let isLoading: Bool

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    var body: some View {
        Button(action: { if !isCurrent { onSelect() } }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: icon)
                                .font(.scaled(size: 15))
                                .foregroundStyle(iconColor)
                            Text(planName)
                                .font(.scaled(size: 17, weight: .bold))
                                .foregroundStyle(ink)
                        }
                        Text(subtitle)
                            .font(.scaled(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isPopular {
                        Text("推荐")
                            .font(.scaled(size: 12, weight: .bold))
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
                        .font(.scaled(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                    Text(period)
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(usdPrice + period)
                        .font(.scaled(size: 13))
                        .foregroundStyle(.tertiary)
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
                                .font(.scaled(size: 12))
                                .foregroundStyle(accentColor)
                                .frame(width: 20)
                            Text(benefit.text)
                                .font(.scaled(size: 13))
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
                                .font(.scaled(size: 13))
                            Text("当前方案")
                                .font(.scaled(size: 14, weight: .semibold))
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
                                    .font(.scaled(size: 15, weight: .semibold))
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
                    .stroke(
                        isCurrent
                            ? accentColor.opacity(0.5)
                            : (isSelected ? accentColor.opacity(0.8) : Color.clear),
                        lineWidth: isCurrent || isSelected ? 2 : 0
                    )
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}
