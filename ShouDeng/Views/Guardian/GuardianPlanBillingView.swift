import SwiftUI
import StoreKit

// MARK: - Plan & Billing
//
// Subscription page:
//   - Free / 单人关注版 (single) / 家庭版 (family); 机构 / 社区版 (ultimate) is contact-us only
//   - SOS with SMS fallback and voice escalation is free on every plan (fair use)
//   - Plan IDs match StoreKitManager and backend PLANS
//   - Prices, periods, trials and the yearly saving all come from the App Store
//     products (never hardcoded); while they load / if they fail: spinner / Retry
//   - Monthly / Yearly / Lifetime (one-time purchase) toggle; buying lifetime while a
//     subscription renews → hint + Manage Subscriptions (Apple doesn't cancel it)
//   - Paid through the App Store (in-app purchase) only
//   - Per-product auto-renewal terms + Terms of Use (EULA) and Privacy Policy links
//   - Feature comparison table
//   - Only guardians pay

struct GuardianPlanBillingView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var billingCycle: BillingCycle = .monthly
    @State private var selectedPlan: PlanTier = .single
    @State private var restoreResult: StoreKitManager.RestoreResult?
    @State private var showPaymentSuccess = false
    @State private var showPrivacyPolicy = false
    @State private var showCancelSubscriptionHint = false

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let accent = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let warm = Color(red: 232/255, green: 165/255, blue: 72/255)

    enum BillingCycle: String, CaseIterable {
        case monthly, yearly, lifetime
    }

    enum PlanTier: String {
        case single, family
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
        .navigationTitle(langManager.localized("guardian.billing.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await coordinator.storeKitManager.fetchProducts()
            await coordinator.storeKitManager.refreshSubscriptionStatus()
        }
        .alert(langManager.localized("guardian.billing.restore.purchase"), isPresented: Binding(
            get: { restoreResult != nil }, set: { if !$0 { restoreResult = nil } }
        )) {
            Button(langManager.localized("guardian.billing.ok")) {}
        } message: {
            Text(restoreMessage)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView().environmentObject(coordinator)
        }
        .alert(langManager.localized("guardian.billing.subscribe.success.title"), isPresented: $showPaymentSuccess) {
            Button(langManager.localized("guardian.billing.ok")) {}
        } message: {
            Text(langManager.localized("guardian.billing.subscribe.success.message"))
        }
        .alert(langManager.localized("store.lifetime.purchased.title"), isPresented: $showCancelSubscriptionHint) {
            Button(langManager.localized("guardian.billing.manage.subscription")) {
                Task { await coordinator.storeKitManager.showManageSubscriptions() }
            }
            Button(langManager.localized("store.later"), role: .cancel) {}
        } message: {
            Text(langManager.localized("store.lifetime.cancelSubscriptionHint"))
        }
    }

    private var restoreMessage: String {
        switch restoreResult {
        case .restored:
            return langManager.localized("guardian.billing.restore.success")
        case .ownedByOtherAccount:
            return langManager.localized("store.error.ownedByOtherAccount")
        case .failed where coordinator.storeKitManager.purchasedPlanId != nil:
            return langManager.localized("guardian.billing.restore.success")
        case .failed:
            return coordinator.storeKitManager.errorMessage ?? langManager.localized("guardian.billing.restore.none")
        case .nothingToRestore, .none:
            return langManager.localized("guardian.billing.restore.none")
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .font(.scaled(size: 36))
                .foregroundStyle(accent)
                .padding(.top, 12)

            Text(langManager.localized("guardian.billing.hero.title"))
                .font(.scaled(size: 22, weight: .bold))
                .foregroundStyle(ink)

            Text(langManager.localized("guardian.billing.hero.subtitle"))
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)

            // Safety floor: never behind the paywall
            Label(langManager.localized("guardian.billing.safetyFloor"), systemImage: "sos.circle.fill")
                .font(.scaled(size: 12))
                .foregroundStyle(safe)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Current Plan Banner

    @ViewBuilder
    private var currentPlanBanner: some View {
        if let lifetime = coordinator.storeKitManager.lifetimePlanId {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.scaled(size: 18))
                    .foregroundStyle(safe)
                Text(String(format: langManager.localized("store.lifetime.current"),
                            coordinator.storeKitManager.planDisplayName(for: lifetime)))
                    .font(.scaled(size: 14, weight: .semibold))
                    .foregroundStyle(ink)
                Spacer()
            }
            .padding(14)
            .background(safe.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        if let status = coordinator.storeKitManager.subscriptionStatus, status.isActive {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.scaled(size: 18))
                    .foregroundStyle(safe)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: langManager.localized("guardian.billing.current.plan"), coordinator.storeKitManager.planDisplayName(for: status.planId)))
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundStyle(ink)
                    if let expires = status.expiresDate {
                        Text(String(format: langManager.localized("guardian.billing.valid.until"), expires.formatted(.dateTime.year().month().day())))
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
                        Text(cycleTitle(cycle))
                            .font(.scaled(size: 14, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if cycle == .yearly, let percent = coordinator.storeKitManager.yearlySavingsPercent {
                            Text(String(format: langManager.localized("store.save.percent"), percent))
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

    private func cycleTitle(_ cycle: BillingCycle) -> String {
        switch cycle {
        case .monthly: return langManager.localized("guardian.billing.monthly")
        case .yearly: return langManager.localized("guardian.billing.yearly")
        case .lifetime: return langManager.localized("store.cycle.lifetime")
        }
    }

    private var periodLabel: String {
        switch billingCycle {
        case .monthly: return langManager.localized("guardian.billing.per.month")
        case .yearly: return langManager.localized("guardian.billing.per.year")
        case .lifetime: return langManager.localized("store.period.oneTime")
        }
    }

    private func product(forPlan plan: String) -> Product? {
        let p = coordinator.storeKitManager.products(forPlan: plan)
        switch billingCycle {
        case .monthly: return p.monthly
        case .yearly: return p.yearly
        case .lifetime: return p.lifetime
        }
    }

    /// "Current" for the cycle shown: a lifetime card is current when lifetime access to
    /// this plan (or a better one) is owned; a subscription card when the plan is in effect.
    private func isCurrent(_ plan: String) -> Bool {
        let store = coordinator.storeKitManager
        if billingCycle == .lifetime {
            guard let owned = store.lifetimePlanId else { return false }
            return StoreKitManager.betterPlan(owned, plan) == owned
        }
        return store.purchasedPlanId == plan
    }

    // MARK: - Plan Cards

    @ViewBuilder
    private var planCards: some View {
        let store = coordinator.storeKitManager
        if store.products.isEmpty {
            ProductsUnavailableView(
                isLoading: store.isLoadingProducts || !store.productsLoadFailed,
                accent: accent,
                onRetry: { Task { await store.fetchProducts() } }
            )
        } else {
            VStack(spacing: 12) {
                if billingCycle == .lifetime, store.hasRenewingSubscription {
                    Label(langManager.localized("store.lifetime.subscriptionNote"), systemImage: "info.circle")
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                singlePlanCard
                familyPlanCard
            }
        }
    }

    private var singlePlanCard: some View {
        let product = product(forPlan: "single")
        let isCurrent = isCurrent("single")

        return PlanCardView(
            planName: langManager.localized("guardian.billing.plan.single"),
            subtitle: langManager.localized("guardian.billing.plan.single.subtitle"),
            icon: "person.fill.checkmark",
            iconColor: safe,
            product: product,
            pricing: product.map { coordinator.storeKitManager.pricing(for: $0) },
            period: periodLabel,
            isCurrent: isCurrent,
            isSelected: selectedPlan == .single && !isCurrent,
            isPopular: false,
            accentColor: safe,
            benefits: [
                ("person.fill.checkmark", langManager.localized("guardian.billing.benefit.1.protected")),
                ("person.2", langManager.localized("guardian.billing.benefit.3.guardians")),
                ("clock.arrow.circlepath", langManager.localized("guardian.billing.benefit.90d.timeline")),
                ("calendar.badge.clock", langManager.localized("guardian.billing.benefit.duty")),
                ("doc.richtext", langManager.localized("guardian.billing.benefit.pdf")),
            ],
            onSelect: { selectedPlan = .single },
            onSubscribe: { subscribeToPlan("single", product: product) },
            isLoading: coordinator.storeKitManager.isLoading
        )
    }

    private var familyPlanCard: some View {
        let product = product(forPlan: "family")
        let isCurrent = isCurrent("family")

        return PlanCardView(
            planName: langManager.localized("guardian.billing.plan.family"),
            subtitle: langManager.localized("guardian.billing.plan.family.subtitle"),
            icon: "house.fill",
            iconColor: accent,
            product: product,
            pricing: product.map { coordinator.storeKitManager.pricing(for: $0) },
            period: periodLabel,
            isCurrent: isCurrent,
            isSelected: selectedPlan == .family && !isCurrent,
            isPopular: true,
            accentColor: accent,
            benefits: [
                ("person.3.fill", langManager.localized("guardian.billing.benefit.4.protected")),
                ("person.fill.badge.plus", langManager.localized("guardian.billing.benefit.unlimited.guardians")),
                ("clock.arrow.circlepath", langManager.localized("guardian.billing.benefit.180d.timeline")),
                ("calendar.badge.clock", langManager.localized("guardian.billing.benefit.duty")),
                ("doc.richtext", langManager.localized("guardian.billing.benefit.pdf")),
                ("chart.bar.fill", langManager.localized("guardian.billing.benefit.dashboard")),
                ("map.fill", langManager.localized("guardian.billing.benefit.gpx")),
            ],
            onSelect: { selectedPlan = .family },
            onSubscribe: { subscribeToPlan("family", product: product) },
            isLoading: coordinator.storeKitManager.isLoading
        )
    }

    private func subscribeToPlan(_ planId: String, product: Product?) {
        guard let product else {
            Task { await coordinator.storeKitManager.fetchProducts() }
            return
        }
        Task {
            let store = coordinator.storeKitManager
            let hadRenewingSubscription = store.hasRenewingSubscription
            let success = await store.purchase(product)
            if success {
                await coordinator.fetchSubscription()
                // Apple doesn't cancel a running subscription when lifetime access is bought
                if StoreKitManager.isLifetime(product.id), hadRenewingSubscription || store.hasRenewingSubscription {
                    showCancelSubscriptionHint = true
                } else {
                    showPaymentSuccess = true
                }
            }
        }
    }

    // MARK: - Payment Info Section

    private var paymentMethodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(langManager.localized("guardian.billing.payment.method"))
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
                    Text(langManager.localized("guardian.billing.via.appstore"))
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(ink)
                    Text(langManager.localized("guardian.billing.payment.support"))
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
            Text(langManager.localized("guardian.billing.comparison"))
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Header row
            HStack(spacing: 0) {
                Text(langManager.localized("guardian.billing.feature"))
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(langManager.localized("guardian.billing.free"))
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
                Text(langManager.localized("guardian.billing.single"))
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(safe)
                    .frame(width: 40)
                Text(langManager.localized("guardian.billing.family"))
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 40)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider().padding(.horizontal, 12)

            comparisonRow(langManager.localized("guardian.billing.row.guardians"), free: "1", single: "3", family: "∞")
            comparisonRow(langManager.localized("guardian.billing.row.protected"), free: "1", single: "1", family: "4")
            comparisonRow(langManager.localized("guardian.billing.row.timeline"), free: "24h", single: langManager.localized("guardian.billing.90days"), family: langManager.localized("guardian.billing.180days"))
            comparisonRow(langManager.localized("guardian.billing.row.sos"), free: true, single: true, family: true)
            comparisonRow(langManager.localized("guardian.billing.row.checkin"), free: true, single: true, family: true)
            comparisonRow(langManager.localized("guardian.billing.row.duty"), free: false, single: true, family: true)
            // Safety floor: SMS fallback and voice escalation on every plan (fair use)
            comparisonRow(langManager.localized("guardian.billing.row.voice"), free: true, single: true, family: true)
            comparisonRow(langManager.localized("guardian.billing.row.sms"), free: true, single: true, family: true)
            comparisonRow(langManager.localized("guardian.billing.row.pdf"), free: false, single: true, family: true)
            comparisonRow(langManager.localized("guardian.billing.row.gpx"), free: false, single: false, family: true)
            comparisonRow(langManager.localized("guardian.billing.row.dashboard"), free: false, single: false, family: true)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func comparisonRow(_ feature: String, free: String, single: String, family: String) -> some View {
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func comparisonRow(_ feature: String, free: Bool, single: Bool, family: Bool) -> some View {
        HStack(spacing: 0) {
            Text(feature)
                .font(.scaled(size: 12))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            checkmark(free, color: .secondary).frame(width: 40)
            checkmark(single, color: safe).frame(width: 40)
            checkmark(family, color: accent).frame(width: 40)
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
                Text(langManager.localized("guardian.billing.custom.plan"))
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
            }
            Text(langManager.localized("guardian.billing.custom.description"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: "mailto:support@shoudeng.app?subject=定制方案咨询") {
                    ExternalURL.open(url)
                }
            } label: {
                Text(langManager.localized("guardian.billing.contact.us"))
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
                        ExternalURL.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gear")
                            .font(.scaled(size: 12))
                        Text(langManager.localized("guardian.billing.manage.subscription"))
                            .font(.scaled(size: 13))
                    }
                    .foregroundStyle(accent)
                }
            }

            // Restore
            Button {
                Task {
                    restoreResult = await coordinator.storeKitManager.restorePurchases()
                    await coordinator.fetchSubscription()
                }
            } label: {
                Text(langManager.localized("guardian.billing.restore.purchase"))
                    .font(.scaled(size: 13))
                    .foregroundStyle(.secondary)
            }
            .disabled(coordinator.storeKitManager.isLoading)

            // Legal (per-product renewal terms are on each card)
            SubscriptionLegalLinks(accent: accent) { showPrivacyPolicy = true }
        }
    }
}

// MARK: - Products unavailable (loading / failed)

/// Shown instead of plan cards until the App Store products load. Never shows a price.
struct ProductsUnavailableView: View {
    @ObservedObject private var langManager = LanguageManager.shared
    let isLoading: Bool
    let accent: Color
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView()
                Text(langManager.localized("store.loading.plans"))
                    .font(.scaled(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "wifi.exclamationmark")
                    .font(.scaled(size: 28))
                    .foregroundStyle(.secondary)
                Text(langManager.localized("store.error.loadPlans"))
                    .font(.scaled(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: onRetry) {
                    Text(langManager.localized("store.retry"))
                        .font(.scaled(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(accent)
                        .clipShape(Capsule())
                }
                .accessibilityIdentifier("store.retry")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Terms of Use / Privacy Policy links

/// Required on every paywall (App Store guideline 3.1.2): Terms of Use (Apple's standard
/// EULA — the app has no custom one) and the Privacy Policy (in-app).
struct SubscriptionLegalLinks: View {
    @ObservedObject private var langManager = LanguageManager.shared
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    let accent: Color
    let onPrivacyPolicy: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                ExternalURL.open(Self.termsOfUseURL)
            } label: {
                Text(langManager.localized("store.link.terms"))
                    .underline()
            }
            Text("·").foregroundStyle(.tertiary)
            Button(action: onPrivacyPolicy) {
                Text(langManager.localized("store.link.privacy"))
                    .underline()
            }
        }
        .font(.scaled(size: 12))
        .foregroundStyle(accent)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Plan Card Component

private struct PlanCardView: View {
    @ObservedObject var langManager = LanguageManager.shared
    let planName: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let product: Product?
    let pricing: SubscriptionPricing?
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
                        Text(langManager.localized("guardian.billing.recommended"))
                            .font(.scaled(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accentColor)
                            .clipShape(Capsule())
                    }
                }

                // Price (from the App Store product)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(product?.displayPrice ?? "—")
                        .font(.scaled(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                    Text(period)
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let intro = pricing?.introSummary() {
                        Text(intro)
                            .font(.scaled(size: 12, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
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
                            Text(langManager.localized("guardian.billing.current"))
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
                                Text(pricing?.subscribeButtonTitle() ?? langManager.localized("guardian.billing.subscribe.now"))
                                    .font(.scaled(size: 15, weight: .semibold))
                                    .multilineTextAlignment(.center)
                            }
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isLoading || product == nil)

                    if let pricing {
                        Text(pricing.legalText(planName: planName))
                            .font(.scaled(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
