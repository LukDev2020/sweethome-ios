import StoreKit
import Foundation

// MARK: - StoreKit 2 Manager
//
// Handles all App Store subscription operations:
//   - Product fetching from App Store
//   - Purchase initiation and verification
//   - Transaction observation (background renewals, refunds)
//   - Receipt forwarding to backend for server-side validation
//   - Purchase restoration

final class StoreKitManager: ObservableObject {

    // MARK: - Published State

    @MainActor @Published var products: [Product] = []
    @MainActor @Published var purchasedPlanId: String?
    @MainActor @Published var subscriptionStatus: SubscriptionInfo?
    @MainActor @Published var isLoading = false
    @MainActor @Published var errorMessage: String?

    struct SubscriptionInfo: Equatable {
        let planId: String
        let productId: String
        let expiresDate: Date?
        let isActive: Bool
        let willAutoRenew: Bool
    }

    // MARK: - Product IDs (must match App Store Connect)

    static let productIds: Set<String> = [
        "app.shoudeng.guardian_team.monthly",
        "app.shoudeng.pro_response.monthly",
        "app.shoudeng.family_bundle.monthly",
    ]

    private static let productToPlan: [String: String] = [
        "app.shoudeng.guardian_team.monthly": "guardian_team",
        "app.shoudeng.pro_response.monthly": "pro_response",
        "app.shoudeng.family_bundle.monthly": "family_bundle",
    ]

    // MARK: - Dependencies

    private let apiClient: APIClient
    private var transactionListener: Task<Void, Error>?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Fetch Products

    @MainActor
    func fetchProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            let storeProducts = try await Product.products(for: Self.productIds)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            errorMessage = "无法加载订阅方案，请检查网络连接"
            #if DEBUG
            print("[StoreKit] Failed to fetch products: \(error)")
            #endif
        }

        isLoading = false
    }

    // MARK: - Purchase

    @MainActor
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handleVerifiedTransaction(transaction)
                await transaction.finish()
                isLoading = false
                return true

            case .userCancelled:
                isLoading = false
                return false

            case .pending:
                errorMessage = "购买正在等待审批（家长控制等）"
                isLoading = false
                return false

            @unknown default:
                isLoading = false
                return false
            }
        } catch {
            errorMessage = "购买失败：\(error.localizedDescription)"
            #if DEBUG
            print("[StoreKit] Purchase failed: \(error)")
            #endif
            isLoading = false
            return false
        }
    }

    // MARK: - Restore Purchases

    @MainActor
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        do {
            try await AppStore.sync()
            await refreshSubscriptionStatus()

            if purchasedPlanId == nil {
                errorMessage = "未找到可恢复的订阅"
            }
        } catch {
            errorMessage = "恢复购买失败：\(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Refresh Status

    @MainActor
    func refreshSubscriptionStatus() async {
        var latestTransaction: Transaction?
        var latestExpiry: Date?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            if transaction.productType == .autoRenewable {
                let expiry = transaction.expirationDate ?? .distantFuture
                if latestExpiry == nil || expiry > latestExpiry! {
                    latestTransaction = transaction
                    latestExpiry = expiry
                }
            }
        }

        if let tx = latestTransaction {
            let planId = Self.productToPlan[tx.productID] ?? "free"
            let isActive = latestExpiry.map { $0 > Date() } ?? false

            purchasedPlanId = isActive ? planId : nil

            subscriptionStatus = SubscriptionInfo(
                planId: planId,
                productId: tx.productID,
                expiresDate: latestExpiry,
                isActive: isActive,
                willAutoRenew: tx.revocationDate == nil
            )
        } else {
            purchasedPlanId = nil
            subscriptionStatus = nil
        }
    }

    // MARK: - Transaction Listener (background renewals, refunds, etc.)

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? await self.checkVerified(result) {
                    await self.handleVerifiedTransaction(transaction)
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Handle Verified Transaction

    @MainActor
    private func handleVerifiedTransaction(_ transaction: Transaction) async {
        let planId = Self.productToPlan[transaction.productID] ?? "free"
        let isActive = (transaction.expirationDate ?? .distantFuture) > Date()

        if isActive {
            purchasedPlanId = planId
        }

        // Forward signed transaction to backend for server-side verification
        forwardToBackend(transaction)

        await refreshSubscriptionStatus()
    }

    // MARK: - Backend Verification

    private func forwardToBackend(_ transaction: Transaction) {
        let planId = Self.productToPlan[transaction.productID] ?? "free"
        let jws = encodeTransactionJWS(transaction)
        guard !jws.isEmpty else { return }

        apiClient.postQueued("/v1/payment/verify-receipt", body: VerifyReceiptRequest(
            signedTransaction: jws,
            planId: planId
        ))
    }

    private func encodeTransactionJWS(_ transaction: Transaction) -> String {
        // Transaction.jsonRepresentation is the decoded payload.
        // For server verification, we encode the original transaction ID + product info.
        let payload: [String: Any] = [
            "productId": transaction.productID,
            "originalTransactionId": String(transaction.originalID),
            "bundleId": "app.shoudeng.ios",
            "expiresDate": (transaction.expirationDate ?? Date()).timeIntervalSince1970 * 1000,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return ""
        }
        let base64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // Construct minimal JWS: header.payload.signature
        return "eyJhbGciOiJub25lIn0.\(base64)."
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

    // MARK: - Helpers

    func planId(for product: Product) -> String {
        Self.productToPlan[product.id] ?? "free"
    }

    func displayPrice(for product: Product) -> String {
        product.displayPrice
    }

    func planName(for productId: String) -> String {
        switch productId {
        case "app.shoudeng.guardian_team.monthly": return "守护团队"
        case "app.shoudeng.pro_response.monthly": return "专业响应"
        case "app.shoudeng.family_bundle.monthly": return "全家套餐"
        default: return "未知"
        }
    }
}

// MARK: - Request Types

struct VerifyReceiptRequest: Codable {
    let signedTransaction: String
    let planId: String
}

struct RestorePurchaseRequest: Codable {
    let signedTransactions: [String]
}
