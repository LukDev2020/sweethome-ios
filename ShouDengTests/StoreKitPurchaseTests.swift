import XCTest
import StoreKit
import StoreKitTest
@testable import ShouDeng

/// Paywall wording, account binding and server sync of StoreKitManager.
/// The StoreKitTest cases run against ShouDeng/StoreKit/ShouDeng.storekit.
@MainActor
final class StoreKitPurchaseTests: XCTestCase {

    private var savedLanguage: AppLanguage!

    override func setUp() async throws {
        savedLanguage = LanguageManager.shared.current
        LanguageManager.shared.current = .english
        StubURLProtocol.reset()
    }

    override func tearDown() async throws {
        LanguageManager.shared.current = savedLanguage
        StubURLProtocol.reset()
    }

    // MARK: - appAccountToken

    func testAppAccountTokenMatchesTheBackend() {
        // Same vector as shoudeng-backend/functions/src/__tests__/payment.apple.test.ts
        XCTAssertEqual(StoreKitManager.appAccountToken(for: "user-123").uuidString.lowercased(),
                       "2596f80f-e7ad-5757-8688-47d61878a0b9")
        XCTAssertNotEqual(StoreKitManager.appAccountToken(for: "a"), StoreKitManager.appAccountToken(for: "b"))
    }

    func testTransactionsOfAnotherAccountAreNotMine() {
        let manager = StoreKitManager(apiClient: stubClient(), observeTransactions: false)
        manager.setAccount("alice")
        XCTAssertTrue(manager.belongsToCurrentAccount(appAccountToken: StoreKitManager.appAccountToken(for: "alice"), originalID: 1))
        XCTAssertFalse(manager.belongsToCurrentAccount(appAccountToken: StoreKitManager.appAccountToken(for: "bob"), originalID: 1))
        XCTAssertTrue(manager.belongsToCurrentAccount(appAccountToken: nil, originalID: 1), "older purchases have no token")
    }

    // MARK: - Wording

    private let monthly = SubscriptionPricing.Period(value: 1, unit: .month)
    private let week = SubscriptionPricing.Period(value: 1, unit: .week)

    func testNoIntroOfferMeansNoTrialWording() {
        let pricing = SubscriptionPricing(displayPrice: "$1.49", period: monthly, introOffer: nil)
        XCTAssertEqual(pricing.subscribeButtonTitle(), "Subscribe · $1.49 per month")
        XCTAssertNil(pricing.introSummary())
        let legal = pricing.legalText(planName: "Individual")
        XCTAssertTrue(legal.hasPrefix("Individual: $1.49 per month."), legal)
        XCTAssertTrue(legal.contains("24 hours"), legal)
        XCTAssertFalse(legal.lowercased().contains("trial"), legal)
    }

    func testFreeTrialWordingUsesTheOffer() {
        let pricing = SubscriptionPricing(displayPrice: "$14.99", period: .init(value: 1, unit: .year),
                                          introOffer: .init(mode: .freeTrial, displayPrice: "$0.00", period: week, periodCount: 1))
        XCTAssertEqual(pricing.subscribeButtonTitle(), "Try free for 1 week")
        XCTAssertEqual(pricing.introSummary(), "Free for 1 week")
        let legal = pricing.legalText(planName: "Family")
        XCTAssertTrue(legal.hasPrefix("Family: free for 1 week, then $14.99 per year."), legal)
    }

    func testPaidIntroOfferWording() {
        let pricing = SubscriptionPricing(displayPrice: "$4.99", period: monthly,
                                          introOffer: .init(mode: .payAsYouGo, displayPrice: "$0.99", period: monthly, periodCount: 3))
        XCTAssertEqual(pricing.introSummary(), "$0.99 per month for the first 3 months")
        XCTAssertEqual(pricing.subscribeButtonTitle(), "Subscribe · $0.99 per month for the first 3 months")
        XCTAssertTrue(pricing.legalText(planName: "Family").contains("then $4.99 per month"))
    }

    func testWordingIsLocalized() {
        LanguageManager.shared.current = .chinese
        let pricing = SubscriptionPricing(displayPrice: "¥12", period: monthly, introOffer: nil)
        XCTAssertEqual(pricing.subscribeButtonTitle(), "订阅 · 每月 ¥12")
        LanguageManager.shared.current = .french
        // Foundation puts a no-break space between number and unit in French
        XCTAssertEqual(SubscriptionPricing.duration(week).replacingOccurrences(of: "\u{00A0}", with: " "), "1 semaine")
    }

    func testYearlySavingsComeFromPrices() {
        // ShouDeng.storekit (A tier, USD): 2.99/22.99, 5.99/49.99 → 35.9%, 30.5%
        let pairs: [(monthly: Decimal, yearly: Decimal)] = [(2.99, 22.99), (5.99, 49.99)]
        XCTAssertEqual(SubscriptionPricing.yearlySavingsPercent(pairs), 30)
        XCTAssertNil(SubscriptionPricing.yearlySavingsPercent([(10, 115)]), "4% is too little to advertise")
        XCTAssertNil(SubscriptionPricing.yearlySavingsPercent([]))
    }

    func testLifetimeWording() {
        let pricing = SubscriptionPricing(lifetimePrice: "$99.99")
        XCTAssertTrue(pricing.isLifetime)
        XCTAssertNil(pricing.introSummary(), "no trial on a one-time purchase")
        XCTAssertEqual(pricing.subscribeButtonTitle(), "Buy lifetime access · $99.99")
        XCTAssertEqual(pricing.recurringPrice(), "$99.99 one-time")
        let legal = pricing.legalText(planName: "Family")
        XCTAssertTrue(legal.hasPrefix("Family, lifetime access: a one-time payment of $99.99"), legal)
        XCTAssertTrue(legal.contains("not a subscription"), legal)
    }

    func testBetterPlanPicksTheHigherTier() {
        XCTAssertEqual(StoreKitManager.betterPlan("single", "family"), "family")
        XCTAssertEqual(StoreKitManager.betterPlan("family", "single"), "family")
        XCTAssertEqual(StoreKitManager.betterPlan(nil, "single"), "single")
        XCTAssertNil(StoreKitManager.betterPlan(nil, nil))
        XCTAssertTrue(StoreKitManager.isLifetime("com.shoudeng.app.family.lifetime"))
        XCTAssertFalse(StoreKitManager.productIds.contains { $0.contains("ultimate") }, "ultimate is not sold in the app")
    }

    // MARK: - StoreKitTest

    /// One session per process: a second SKTestSession resets the environment under the first.
    private static var sharedSession: SKTestSession?

    private static func newSession() throws -> SKTestSession {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ShouDeng/StoreKit/ShouDeng.storekit")
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        sharedSession = session
        return session
    }

    private func makeSession() async throws -> SKTestSession {
        var session: SKTestSession
        if let existing = Self.sharedSession {
            session = existing
            session.resetToDefaultState()
            session.disableDialogs = true
            session.clearTransactions()
        } else {
            session = try Self.newSession()
        }
        // Both settle asynchronously in the StoreKit daemon: wait until the previous
        // test's purchases are gone, the products load and the intro offer is available again.
        // On a freshly created simulator the first session sometimes never serves
        // products; a new session does.
        for attempt in 0..<300 {
            if attempt > 0, attempt % 50 == 0,
               ((try? await Product.products(for: StoreKitManager.productIds).count) ?? 0) == 0 {
                session = try Self.newSession()
            }
            var hasEntitlement = false
            for await _ in Transaction.currentEntitlements { hasEntitlement = true; break }
            let products = (try? await Product.products(for: StoreKitManager.productIds)) ?? []
            let eligible = await products.first?.subscription?.isEligibleForIntroOffer ?? false
            if !hasEntitlement && eligible && products.count == StoreKitManager.productIds.count { return session }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("StoreKit test session did not reset")
        return session
    }

    /// Purchases show up in currentEntitlements a moment after buyProduct returns: buy,
    /// then wait until StoreKit reports it.
    private func buy(_ session: SKTestSession, _ productID: String,
                     options: Set<Product.PurchaseOption> = []) async throws {
        _ = try await session.buyProduct(identifier: productID, options: options)
        for _ in 0..<100 {
            var owned = false
            for await result in Transaction.currentEntitlements {
                if case .verified(let t) = result, t.productID == productID { owned = true }
            }
            if owned { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("\(productID) purchase never showed up")
    }

    private func stubClient() -> APIClient {
        APIClient(config: .init(baseURL: "https://api.test"), offlineQueue: OfflineQueue(fileURL: nil),
                  sessionConfiguration: StubURLProtocol.session())
    }

    private func json(_ s: String) -> Data { Data(s.utf8) }

    /// One end-to-end pass on a fresh session (StoreKitTest's reset between test methods
    /// settles asynchronously and unreliably, so the purchase-dependent steps share one test).
    func testPurchaseFlowAgainstTheStoreKitConfiguration() async throws {
        let session = try await makeSession()
        StubURLProtocol.handler = { _ in (200, self.json(#"{"success":true,"restored":true}"#)) }
        let alice = StoreKitManager(apiClient: stubClient())
        alice.setAccount("alice")

        // Before any purchase: products, eligibility, trial wording, yearly saving
        await alice.fetchProducts()
        XCTAssertEqual(alice.products.count, 6)
        XCTAssertFalse(alice.productsLoadFailed)
        XCTAssertTrue(alice.isEligibleForIntroOffer)
        XCTAssertEqual(alice.yearlySavingsPercent, 30)
        let lifetime = try XCTUnwrap(alice.products(forPlan: "family").lifetime)
        XCTAssertEqual(lifetime.type, .nonConsumable)
        XCTAssertEqual(lifetime.displayPrice, "$129.99")
        XCTAssertTrue(alice.pricing(for: lifetime).isLifetime)
        XCTAssertNil(alice.pricing(for: lifetime).introOffer)
        let single = try XCTUnwrap(alice.products(forPlan: "single").monthly)
        let pricing = alice.pricing(for: single)
        XCTAssertEqual(pricing.introOffer?.mode, .freeTrial)
        XCTAssertEqual(pricing.introOffer?.period, .init(value: 3, unit: .day))
        XCTAssertEqual(pricing.subscribeButtonTitle(), "Try free for 3 days")

        // Alice subscribes (purchases carry her appAccountToken)
        try await buy(session, "com.shoudeng.app.family.yearly",
                      options: [.appAccountToken(StoreKitManager.appAccountToken(for: "alice"))])
        await alice.refreshSubscriptionStatus()
        XCTAssertEqual(alice.purchasedPlanId, "family")

        XCTAssertNil(alice.lifetimePlanId)

        // Lifetime single on top of the family subscription: family stays in effect, the
        // subscription keeps renewing (Apple doesn't cancel it → the paywall says so)
        try await buy(session, "com.shoudeng.app.single.lifetime",
                      options: [.appAccountToken(StoreKitManager.appAccountToken(for: "alice"))])
        await alice.refreshSubscriptionStatus()
        XCTAssertEqual(alice.lifetimePlanId, "single")
        XCTAssertEqual(alice.purchasedPlanId, "family")
        XCTAssertTrue(alice.hasRenewingSubscription)

        // Login sync sends the entitlements' JWS (subscription + lifetime) to the server
        StubURLProtocol.reset()
        StubURLProtocol.handler = { _ in (200, self.json(#"{"success":true,"restored":true}"#)) }
        let result = await alice.syncEntitlementsWithServer()
        XCTAssertEqual(result, .restored)
        let restore = try XCTUnwrap(StubURLProtocol.requests.last { $0.path == "/v1/payment/restore" })
        XCTAssertEqual(restore.method, "POST")
        let body = try JSONDecoder().decode(RestorePurchaseRequest.self, from: try XCTUnwrap(restore.body))
        XCTAssertEqual(body.signedTransactions.count, 2)
        XCTAssertEqual(body.signedTransactions.first?.split(separator: ".").count, 3, "a JWS")

        // Not eligible any more → no trial wording (StoreKitTest doesn't reliably update
        // eligibility after a test purchase, so the ineligible case is checked directly)
        let ineligible = SubscriptionPricing(product: single, eligibleForIntroOffer: false)
        XCTAssertNil(ineligible.introOffer)
        XCTAssertEqual(ineligible.subscribeButtonTitle(), "Subscribe · $2.99 per month")

        // Bob signs in on the same Apple ID: Alice's subscription is not his plan
        let bob = StoreKitManager(apiClient: stubClient())
        bob.setAccount("bob")
        await bob.refreshSubscriptionStatus()
        XCTAssertNil(bob.purchasedPlanId)
        let bobSync = await bob.syncEntitlementsWithServer()
        XCTAssertEqual(bobSync, .restored, "sent anyway; the server decides whose it is")
    }

    func testServerRefusingTheSubscriptionLocksItLocally() async {
        StubURLProtocol.handler = { _ in
            (409, self.json(#"{"error":"linked elsewhere","code":"SUBSCRIPTION_OWNED_BY_OTHER_ACCOUNT"}"#))
        }
        let manager = StoreKitManager(apiClient: stubClient(), observeTransactions: false)
        manager.setAccount("bob")
        XCTAssertTrue(manager.belongsToCurrentAccount(appAccountToken: nil, originalID: 42))
        let result = await manager.sendEntitlements([(jws: "h.p.s", originalID: 42)])
        XCTAssertEqual(result, .ownedByOtherAccount)
        XCTAssertFalse(manager.belongsToCurrentAccount(appAccountToken: nil, originalID: 42),
                       "token-less purchase the server gave to another account unlocks nothing here")
        XCTAssertTrue(manager.belongsToCurrentAccount(appAccountToken: nil, originalID: 43))
        manager.setAccount("carol")
        XCTAssertTrue(manager.belongsToCurrentAccount(appAccountToken: nil, originalID: 42), "reset per account")
    }

    func testRestoreWithNothingOnTheServer() async {
        StubURLProtocol.handler = { _ in (200, self.json(#"{"success":true,"restored":false}"#)) }
        let manager = StoreKitManager(apiClient: stubClient(), observeTransactions: false)
        manager.setAccount("alice")
        let result = await manager.sendEntitlements([(jws: "h.p.s", originalID: 1)])
        XCTAssertEqual(result, .nothingToRestore)
    }

    func testNothingToSyncSendsNothing() async {
        let manager = StoreKitManager(apiClient: stubClient(), observeTransactions: false)
        manager.setAccount("alice")
        let result = await manager.sendEntitlements([])
        XCTAssertEqual(result, .nothingToRestore)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.path == "/v1/payment/restore" })
    }
}
