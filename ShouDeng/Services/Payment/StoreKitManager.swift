import StoreKit
import Foundation
import CryptoKit
import UIKit

// MARK: - StoreKit 2 Manager
//
// Handles all App Store subscription operations:
//   - Product fetching from App Store (+ intro-offer eligibility)
//   - Purchase initiation (with the account's appAccountToken) and verification
//   - Transaction observation (background renewals, refunds)
//   - Receipt forwarding to backend for server-side validation
//   - Purchase restoration, and syncing current entitlements to the server at login
//
// Plans sold in the app (docs/pricing/PRICING.md): single (单人关注版) and family (家庭版),
// each monthly / yearly (auto-renewing, one subscription group) or lifetime (one-time,
// non-consumable). ultimate (机构 / 社区版) is contact-us only; its products still map to a
// plan so an existing purchase resolves. SMS fallback and voice escalation are free.
// Plan IDs and product IDs must match App Store Connect and PLANS in
// shoudeng-backend/functions/src/services/payment.ts.

final class StoreKitManager: ObservableObject {

    // MARK: - Published State

    @MainActor @Published var products: [Product] = []
    /// Plan in effect: the better of an active subscription and a lifetime purchase
    @MainActor @Published var purchasedPlanId: String?
    @MainActor @Published var subscriptionStatus: SubscriptionInfo?
    /// Plan of a lifetime (one-time) purchase on this account, if any
    @MainActor @Published var lifetimePlanId: String?
    /// A purchase / restore is in progress
    @MainActor @Published var isLoading = false
    @MainActor @Published var isLoadingProducts = false
    /// Products could not be loaded (network, App Store unavailable) — show Retry, never a made-up price
    @MainActor @Published var productsLoadFailed = false
    /// The Apple ID hasn't used an introductory offer in this subscription group yet
    @MainActor @Published var isEligibleForIntroOffer = false
    @MainActor @Published var errorMessage: String?

    struct SubscriptionInfo: Equatable {
        let planId: String
        let productId: String
        let expiresDate: Date?
        let isActive: Bool
        let willAutoRenew: Bool
    }

    enum RestoreResult: Equatable {
        case restored
        case nothingToRestore
        /// The App Store subscription already unlocks another Lantern Care account
        case ownedByOtherAccount
        case failed
    }

    // MARK: - Product IDs (must match App Store Connect)

    /// Products offered on the paywall
    static let productIds: Set<String> = [
        "com.shoudeng.app.single.monthly",
        "com.shoudeng.app.single.yearly",
        "com.shoudeng.app.single.lifetime",
        "com.shoudeng.app.family.monthly",
        "com.shoudeng.app.family.yearly",
        "com.shoudeng.app.family.lifetime",
    ]

    /// One-time (non-consumable) purchases: no expiry, not in the subscription group
    static let lifetimeProductIds: Set<String> = [
        "com.shoudeng.app.single.lifetime",
        "com.shoudeng.app.family.lifetime",
    ]

    /// Every product that grants a plan, including ones no longer sold (ultimate)
    private static let productToPlan: [String: String] = [
        "com.shoudeng.app.single.monthly": "single",
        "com.shoudeng.app.single.yearly": "single",
        "com.shoudeng.app.single.lifetime": "single",
        "com.shoudeng.app.family.monthly": "family",
        "com.shoudeng.app.family.yearly": "family",
        "com.shoudeng.app.family.lifetime": "family",
        "com.shoudeng.app.ultimate.monthly": "ultimate",
        "com.shoudeng.app.ultimate.yearly": "ultimate",
    ]

    private static let planRank: [String: Int] = ["free": 0, "single": 1, "family": 2, "ultimate": 3]

    /// The better of two plans (nil = none)
    static func betterPlan(_ a: String?, _ b: String?) -> String? {
        guard let a else { return b }
        guard let b else { return a }
        return (planRank[b] ?? 0) > (planRank[a] ?? 0) ? b : a
    }

    // MARK: - Dependencies

    private let apiClient: APIClient
    private var transactionListener: Task<Void, Error>?
    /// false in Explore Mode: the sample family's plan is set directly, never read from StoreKit
    private let usesStoreKit: Bool
    /// Signed-in account; purchases carry its appAccountToken
    @MainActor private(set) var accountId: String?
    /// Subscriptions (originalID) the server says belong to another account
    @MainActor private var foreignOriginalIds: Set<UInt64> = []

    /// - Parameter observeTransactions: false for Explore Mode (no StoreKit side effects)
    init(apiClient: APIClient, observeTransactions: Bool = true) {
        self.apiClient = apiClient
        self.usesStoreKit = observeTransactions
        if observeTransactions {
            transactionListener = listenForTransactions()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Account

    /// Namespace of the appAccountToken (UUID v5 of the user id). The backend derives the
    /// same value (appAccountTokenFor in services/payment.ts) — change both together.
    private static let appAccountTokenNamespace = UUID(uuidString: "8c5e3f7a-2b1d-4e6f-9a0c-3d7b5e1f4a28")!

    /// The token every purchase of this account carries, so the server can tell
    /// whose subscription a transaction is (one subscription unlocks one account).
    static func appAccountToken(for userId: String) -> UUID {
        var data = withUnsafeBytes(of: appAccountTokenNamespace.uuid) { Data($0) }
        data.append(Data(userId.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Called on login (user id) and logout (nil). A different account starts from a clean slate.
    @MainActor
    func setAccount(_ userId: String?) {
        guard userId != accountId else { return }
        accountId = userId
        foreignOriginalIds = []
        if userId == nil {
            purchasedPlanId = nil
            lifetimePlanId = nil
            subscriptionStatus = nil
        }
    }

    /// Whether a transaction is this account's: its appAccountToken is ours, or it has
    /// none (older purchases) and the server hasn't said it belongs to someone else.
    @MainActor
    func belongsToCurrentAccount(_ transaction: Transaction) -> Bool {
        belongsToCurrentAccount(appAccountToken: transaction.appAccountToken, originalID: transaction.originalID)
    }

    @MainActor
    func belongsToCurrentAccount(appAccountToken: UUID?, originalID: UInt64) -> Bool {
        if let token = appAccountToken {
            guard let accountId else { return false }
            return token == Self.appAccountToken(for: accountId)
        }
        return !foreignOriginalIds.contains(originalID)
    }

    // MARK: - Fetch Products

    @MainActor
    func fetchProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        productsLoadFailed = false
        errorMessage = nil

        do {
            let storeProducts = try await Product.products(for: Self.productIds)
            products = storeProducts.sorted { $0.price < $1.price }
            productsLoadFailed = storeProducts.isEmpty
            if let subscription = storeProducts.first(where: { $0.subscription != nil })?.subscription {
                isEligibleForIntroOffer = await subscription.isEligibleForIntroOffer
            }
        } catch {
            productsLoadFailed = true
            #if DEBUG
            print("[StoreKit] Failed to fetch products: \(error)")
            #endif
        }
        if productsLoadFailed {
            errorMessage = LanguageManager.shared.localized("store.error.loadPlans")
        }

        isLoadingProducts = false
    }

    // MARK: - Product Accessors

    @MainActor
    func products(forPlan planId: String) -> (monthly: Product?, yearly: Product?, lifetime: Product?) {
        let m = products.first { $0.id == "com.shoudeng.app.\(planId).monthly" }
        let y = products.first { $0.id == "com.shoudeng.app.\(planId).yearly" }
        let l = products.first { $0.id == "com.shoudeng.app.\(planId).lifetime" }
        return (m, y, l)
    }

    static func isLifetime(_ productId: String) -> Bool { lifetimeProductIds.contains(productId) }

    /// An auto-renewing subscription that will charge again — Apple doesn't cancel it
    /// when someone buys lifetime access.
    @MainActor
    var hasRenewingSubscription: Bool {
        guard let status = subscriptionStatus else { return false }
        return status.isActive && status.willAutoRenew
    }

    /// Apple's Manage Subscriptions sheet (cancel the subscription after buying lifetime).
    @MainActor
    func showManageSubscriptions() async {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        if let scene {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
                await refreshSubscriptionStatus()
                return
            } catch {
                #if DEBUG
                print("[StoreKit] Manage subscriptions sheet failed: \(error)")
                #endif
            }
        }
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            await UIApplication.shared.open(url)
        }
    }

    /// Price, period and (when this Apple ID is eligible) introductory offer of a product.
    @MainActor
    func pricing(for product: Product) -> SubscriptionPricing {
        SubscriptionPricing(product: product, eligibleForIntroOffer: isEligibleForIntroOffer)
    }

    /// Yearly saving vs. 12 × monthly, in whole percent, across all plans (the smallest,
    /// so "Save N%" is true for every plan). nil until products load or when below 5%.
    @MainActor
    var yearlySavingsPercent: Int? {
        let pairs = ["single", "family"].compactMap { plan -> (monthly: Decimal, yearly: Decimal)? in
            let p = products(forPlan: plan)
            guard let m = p.monthly?.price, let y = p.yearly?.price else { return nil }
            return (m, y)
        }
        return SubscriptionPricing.yearlySavingsPercent(pairs)
    }

    // MARK: - Purchase

    @MainActor
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        errorMessage = nil

        var options: Set<Product.PurchaseOption> = []
        if let accountId {
            options.insert(.appAccountToken(Self.appAccountToken(for: accountId)))
        }

        do {
            let result = try await product.purchase(options: options)

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handleVerifiedTransaction(transaction, jws: verification.jwsRepresentation)
                await transaction.finish()
                isLoading = false
                return true

            case .userCancelled:
                isLoading = false
                return false

            case .pending:
                errorMessage = LanguageManager.shared.localized("store.error.pending")
                isLoading = false
                return false

            @unknown default:
                isLoading = false
                return false
            }
        } catch {
            errorMessage = String(format: LanguageManager.shared.localized("store.error.purchase"), error.localizedDescription)
            #if DEBUG
            print("[StoreKit] Purchase failed: \(error)")
            #endif
            isLoading = false
            return false
        }
    }

    // MARK: - Restore Purchases

    @MainActor
    @discardableResult
    func restorePurchases() async -> RestoreResult {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
        } catch {
            errorMessage = String(format: LanguageManager.shared.localized("store.error.restore"), error.localizedDescription)
            return .failed
        }
        await refreshSubscriptionStatus()
        let result = await syncEntitlementsWithServer()

        switch result {
        case .ownedByOtherAccount:
            errorMessage = LanguageManager.shared.localized("store.error.ownedByOtherAccount")
        case .nothingToRestore:
            errorMessage = LanguageManager.shared.localized("store.error.nothingToRestore")
        case .failed:
            // The App Store restored it on this device; the server catches up at next login
            if purchasedPlanId == nil {
                errorMessage = LanguageManager.shared.localized("store.error.nothingToRestore")
            }
        case .restored:
            break
        }
        return result
    }

    // MARK: - Server Sync

    /// Send every current entitlement (signed JWS) to the server, so it knows about
    /// subscriptions bought on another device, restored, or renewed while offline.
    /// Called at login and after Restore. Never prompts for an Apple ID sign-in.
    @MainActor
    @discardableResult
    func syncEntitlementsWithServer() async -> RestoreResult {
        guard usesStoreKit, accountId != nil else { return .nothingToRestore }
        var entitlements: [(jws: String, originalID: UInt64)] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productType == .autoRenewable || Self.isLifetime(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            entitlements.append((result.jwsRepresentation, transaction.originalID))
        }
        return await sendEntitlements(entitlements)
    }

    /// POST /v1/payment/restore with the given entitlements (separate for tests).
    @MainActor
    func sendEntitlements(_ entitlements: [(jws: String, originalID: UInt64)]) async -> RestoreResult {
        guard !entitlements.isEmpty else { return .nothingToRestore }
        do {
            let response: RestorePurchaseResponse = try await apiClient.postReportingCode(
                "/v1/payment/restore",
                body: RestorePurchaseRequest(signedTransactions: entitlements.map(\.jws))
            )
            return response.restored == true ? .restored : .nothingToRestore
        } catch let error as APIServerError where error.code == "SUBSCRIPTION_OWNED_BY_OTHER_ACCOUNT" {
            // Don't unlock features here that another account paid for
            foreignOriginalIds.formUnion(entitlements.map(\.originalID))
            await refreshSubscriptionStatus()
            return .ownedByOtherAccount
        } catch {
            #if DEBUG
            print("[StoreKit] Entitlement sync failed: \(error)")
            #endif
            return .failed
        }
    }

    // MARK: - Refresh Status

    @MainActor
    func refreshSubscriptionStatus() async {
        guard usesStoreKit else { return }
        var latestTransaction: Transaction?
        var latestExpiry: Date?
        var lifetime: String?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            // Refunded / revoked / superseded transactions, and other accounts' purchases, unlock nothing
            guard transaction.revocationDate == nil,
                  !transaction.isUpgraded,
                  belongsToCurrentAccount(transaction) else { continue }

            if Self.isLifetime(transaction.productID) {
                lifetime = Self.betterPlan(lifetime, Self.productToPlan[transaction.productID])
                continue
            }
            guard transaction.productType == .autoRenewable else { continue }

            let expiry = transaction.expirationDate ?? .distantFuture
            if latestExpiry == nil || expiry > latestExpiry! {
                latestTransaction = transaction
                latestExpiry = expiry
            }
        }

        lifetimePlanId = lifetime
        if let tx = latestTransaction {
            let planId = Self.productToPlan[tx.productID] ?? "free"
            let isActive = latestExpiry.map { $0 > Date() } ?? false
            var willAutoRenew = false
            if let status = await tx.subscriptionStatus,
               case .verified(let renewal) = status.renewalInfo {
                willAutoRenew = renewal.willAutoRenew
            }

            purchasedPlanId = Self.betterPlan(isActive ? planId : nil, lifetime)

            subscriptionStatus = SubscriptionInfo(
                planId: planId,
                productId: tx.productID,
                expiresDate: latestExpiry,
                isActive: isActive,
                willAutoRenew: willAutoRenew
            )
        } else {
            purchasedPlanId = lifetime
            subscriptionStatus = nil
        }
    }

    // MARK: - Transaction Listener (background renewals, refunds, etc.)

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.checkVerified(result) {
                    await self.handleVerifiedTransaction(transaction, jws: result.jwsRepresentation)
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Handle Verified Transaction

    @MainActor
    private func handleVerifiedTransaction(_ transaction: Transaction, jws: String) async {
        // Another account's renewal (same Apple ID, different sign-in) is none of ours
        guard accountId != nil, belongsToCurrentAccount(transaction) else {
            await refreshSubscriptionStatus()
            return
        }
        let planId = Self.productToPlan[transaction.productID] ?? "free"
        let isActive = transaction.revocationDate == nil
            && (transaction.expirationDate ?? .distantFuture) > Date()

        if isActive {
            purchasedPlanId = Self.betterPlan(purchasedPlanId, planId)
        }

        // Refunds too: the server records them (and Apple's notification confirms it)
        forwardToBackend(jws: jws)
        await refreshSubscriptionStatus()
    }

    // MARK: - Backend Verification

    /// Sends Apple's signed transaction (JWS) to the backend, which derives
    /// the plan from the signed product ID.
    private func forwardToBackend(jws: String) {
        guard !jws.isEmpty else { return }
        apiClient.postQueued("/v1/payment/verify-receipt", body: VerifyReceiptRequest(
            signedTransaction: jws
        ))
    }

    // MARK: - Verification Helper

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    // MARK: - Feature Gating

    /// Every plan, free included: SOS with SMS fallback and voice escalation (fair use).
    static let safetyFloor: Set<String> = ["basic_sos", "checkin", "sms_fallback", "voice_call_escalation"]

    /// Features available per plan tier. Must match backend PLANS definition.
    private static let planFeatures: [String: Set<String>] = [
        "free": safetyFloor,
        "single": safetyFloor.union(["duty_schedule", "export_pdf"]),
        "family": safetyFloor.union(["duty_schedule", "export_pdf", "family_dashboard", "location_history_export"]),
        "ultimate": safetyFloor.union(["duty_schedule", "export_pdf", "family_dashboard", "location_history_export",
                                       "priority_support"]),
    ]

    private static let planLimits: [String: (maxGuardians: Int, maxProtected: Int)] = [
        "free": (1, 1),
        "single": (3, 1),
        "family": (-1, 4),    // -1 = unlimited
        "ultimate": (-1, -1),
    ]

    private static let planTimelineDays: [String: Int] = [
        "free": 1,
        "single": 90,
        "family": 180,
        "ultimate": 365,
    ]

    /// Current active plan ID (defaults to "free")
    @MainActor
    var activePlanId: String {
        purchasedPlanId ?? "free"
    }

    /// Check if user's plan includes a specific feature
    @MainActor
    func canAccessFeature(_ feature: String) -> Bool {
        let plan = activePlanId
        return Self.planFeatures[plan]?.contains(feature) ?? false
    }

    /// Minimum plan tier required for a feature
    static func minimumPlan(for feature: String) -> String {
        for tier in ["single", "family", "ultimate"] {
            if planFeatures[tier]?.contains(feature) == true {
                return tier
            }
        }
        return "ultimate"
    }

    /// Guardian count limit for current plan (-1 = unlimited)
    @MainActor
    var maxGuardians: Int {
        Self.planLimits[activePlanId]?.maxGuardians ?? 1
    }

    /// Protected person count limit for current plan (-1 = unlimited)
    @MainActor
    var maxProtected: Int {
        Self.planLimits[activePlanId]?.maxProtected ?? 1
    }

    /// Timeline retention days for current plan
    @MainActor
    var timelineDays: Int {
        Self.planTimelineDays[activePlanId] ?? 1
    }

    // MARK: - Helpers

    func planId(for product: Product) -> String {
        Self.productToPlan[product.id] ?? "free"
    }

    func planName(for productId: String) -> String {
        planDisplayName(for: Self.productToPlan[productId] ?? "free")
    }

    func planDisplayName(for planId: String) -> String {
        switch planId {
        case "single", "family", "ultimate": return LanguageManager.shared.localized("guardian.billing.plan.\(planId)")
        default: return LanguageManager.shared.localized("guardian.billing.free")
        }
    }
}

// MARK: - Request Types

struct VerifyReceiptRequest: Codable {
    let signedTransaction: String
}

struct RestorePurchaseRequest: Codable {
    let signedTransactions: [String]
}

struct RestorePurchaseResponse: Decodable {
    let success: Bool?
    let restored: Bool?
}

// MARK: - Pricing & paywall wording

/// Price, billing period and (when the Apple ID is eligible) introductory offer of a
/// subscription product as plain values, plus the paywall wording built from them.
/// Trial wording appears only when there is an offer this Apple ID can use.
struct SubscriptionPricing: Equatable {
    enum Unit: Equatable { case day, week, month, year }
    enum OfferMode: Equatable { case freeTrial, payAsYouGo, payUpFront }

    struct Period: Equatable {
        let value: Int
        let unit: Unit
    }

    struct IntroOffer: Equatable {
        let mode: OfferMode
        /// Price per period (pay as you go) or for the whole offer (pay up front); "0" for trials
        let displayPrice: String
        let period: Period
        let periodCount: Int
    }

    let displayPrice: String
    let period: Period
    /// nil when there is none or the Apple ID already used one in this group
    let introOffer: IntroOffer?
    /// One-time purchase (lifetime access): no period, no renewal, no intro offer
    let isLifetime: Bool

    init(displayPrice: String, period: Period, introOffer: IntroOffer?) {
        self.displayPrice = displayPrice
        self.period = period
        self.introOffer = introOffer
        self.isLifetime = false
    }

    /// A one-time (lifetime) purchase
    init(lifetimePrice: String) {
        self.displayPrice = lifetimePrice
        self.period = Period(value: 1, unit: .year)
        self.introOffer = nil
        self.isLifetime = true
    }

    init(product: Product, eligibleForIntroOffer: Bool) {
        let subscription = product.subscription
        self.isLifetime = subscription == nil
        self.displayPrice = product.displayPrice
        self.period = subscription.map { Self.period($0.subscriptionPeriod) } ?? Period(value: 1, unit: .month)
        if !isLifetime, eligibleForIntroOffer, let offer = subscription?.introductoryOffer {
            let mode: OfferMode
            if offer.paymentMode == .freeTrial { mode = .freeTrial }
            else if offer.paymentMode == .payUpFront { mode = .payUpFront }
            else { mode = .payAsYouGo }
            self.introOffer = IntroOffer(mode: mode, displayPrice: offer.displayPrice,
                                         period: Self.period(offer.period), periodCount: max(1, offer.periodCount))
        } else {
            self.introOffer = nil
        }
    }

    private static func period(_ p: Product.SubscriptionPeriod) -> Period {
        switch p.unit {
        case .day: return Period(value: p.value, unit: .day)
        case .week: return Period(value: p.value, unit: .week)
        case .month: return Period(value: p.value, unit: .month)
        case .year: return Period(value: p.value, unit: .year)
        @unknown default: return Period(value: p.value, unit: .month)
        }
    }

    // MARK: Wording

    /// "1 week", "7 days", "1 an" — localized, with correct plurals.
    static func duration(_ period: Period, times count: Int = 1, lang: LanguageManager = .shared) -> String {
        let n = period.value * max(1, count)
        var components = DateComponents()
        switch period.unit {
        case .day: components.day = n
        case .week: components.weekOfMonth = n
        case .month: components.month = n
        case .year: components.year = n
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
        formatter.maximumUnitCount = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: lang.current.rawValue)
        formatter.calendar = calendar
        return formatter.string(from: components) ?? "\(n)"
    }

    /// "$1.49 per month" / "every 3 months"
    static func recurring(_ price: String, every period: Period, lang: LanguageManager = .shared) -> String {
        guard period.value == 1 else {
            return String(format: lang.localized("store.price.perPeriod"), price, duration(period, lang: lang))
        }
        switch period.unit {
        case .day: return String(format: lang.localized("store.price.perDay"), price)
        case .week: return String(format: lang.localized("store.price.perWeek"), price)
        case .month: return String(format: lang.localized("store.price.perMonth"), price)
        case .year: return String(format: lang.localized("store.price.perYear"), price)
        }
    }

    /// "$1.49 per month", or "$39.99 one-time" for lifetime
    func recurringPrice(lang: LanguageManager = .shared) -> String {
        if isLifetime { return String(format: lang.localized("store.price.oneTime"), displayPrice) }
        return Self.recurring(displayPrice, every: period, lang: lang)
    }

    /// "Free for 1 week" / "$0.99 per month for 3 months" / "$2.99 for 3 months"
    func introSummary(lang: LanguageManager = .shared) -> String? {
        guard let offer = introOffer else { return nil }
        let total = Self.duration(offer.period, times: offer.periodCount, lang: lang)
        switch offer.mode {
        case .freeTrial:
            return String(format: lang.localized("store.intro.free"), total)
        case .payAsYouGo:
            return String(format: lang.localized("store.intro.paid"),
                          Self.recurring(offer.displayPrice, every: offer.period, lang: lang), total)
        case .payUpFront:
            return String(format: lang.localized("store.intro.paid"), offer.displayPrice, total)
        }
    }

    /// Purchase button: "Start 1-week free trial" only when eligible, else "Subscribe · $1.49 per month".
    func subscribeButtonTitle(lang: LanguageManager = .shared) -> String {
        if isLifetime { return String(format: lang.localized("store.cta.buyLifetime"), displayPrice) }
        if let offer = introOffer, offer.mode == .freeTrial {
            return String(format: lang.localized("store.cta.freeTrial"),
                          Self.duration(offer.period, times: offer.periodCount, lang: lang))
        }
        if let summary = introSummary(lang: lang) {
            return String(format: lang.localized("store.cta.subscribe"), summary)
        }
        return String(format: lang.localized("store.cta.subscribe"), recurringPrice(lang: lang))
    }

    /// Auto-renewal disclosure for this product (App Store guideline 3.1.2).
    func legalText(planName: String, lang: LanguageManager = .shared) -> String {
        if isLifetime { return String(format: lang.localized("store.legal.lifetime"), planName, displayPrice) }
        let recurring = recurringPrice(lang: lang)
        guard let offer = introOffer, let summary = introSummary(lang: lang) else {
            return String(format: lang.localized("store.legal.renewal"), planName, recurring)
        }
        if offer.mode == .freeTrial {
            return String(format: lang.localized("store.legal.trial"), planName,
                          Self.duration(offer.period, times: offer.periodCount, lang: lang), recurring)
        }
        return String(format: lang.localized("store.legal.intro"), planName, summary, recurring)
    }

    /// Yearly saving vs. 12 × monthly in whole percent — the smallest across the given
    /// plans, rounded down, so the badge is true for each. nil when below 5% or unknown.
    static func yearlySavingsPercent(_ pairs: [(monthly: Decimal, yearly: Decimal)]) -> Int? {
        let savings = pairs.compactMap { pair -> Decimal? in
            let fullYear = pair.monthly * 12
            guard fullYear > 0 else { return nil }
            return (fullYear - pair.yearly) / fullYear * 100
        }
        guard let smallest = savings.min() else { return nil }
        var value = smallest
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        let percent = NSDecimalNumber(decimal: rounded).intValue
        return percent >= 5 ? percent : nil
    }
}
