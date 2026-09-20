import Foundation
import UIKit

// MARK: - Payment Method Manager
//
// Handles non-IAP payment methods: Alipay, WeChat Pay, Credit Card, PayPal.
// Apple IAP remains in StoreKitManager. This service creates payment intents
// via the backend and handles confirmation callbacks.
//
// Flow:
//   1. User selects plan + payment method in UI
//   2. createPaymentIntent → backend returns clientSecret / payUrl
//   3. For Alipay/WeChat: open payment URL via universal link
//   4. For Credit Card: present Stripe-style card form
//   5. For PayPal: redirect to PayPal checkout
//   6. App receives callback → confirmPayment → backend verifies → subscription activated

enum PaymentMethod: String, CaseIterable, Codable, Identifiable {
    case applePay = "apple_pay"
    case creditCard = "credit_card"
    case alipay = "alipay"
    case wechatPay = "wechat_pay"
    case paypal = "paypal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .applePay: return "Apple Pay"
        case .creditCard: return "银行卡"
        case .alipay: return "支付宝"
        case .wechatPay: return "微信支付"
        case .paypal: return "PayPal"
        }
    }

    var iconName: String {
        switch self {
        case .applePay: return "apple.logo"
        case .creditCard: return "creditcard.fill"
        case .alipay: return "a.circle.fill"
        case .wechatPay: return "message.fill"
        case .paypal: return "p.circle.fill"
        }
    }
}

final class PaymentMethodManager: ObservableObject {

    @MainActor @Published var selectedMethod: PaymentMethod = .applePay
    @MainActor @Published var isProcessing = false
    @MainActor @Published var errorMessage: String?
    @MainActor @Published var paymentSuccess = false

    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Create Payment Intent

    @MainActor
    func createPayment(planId: String, billingCycle: String) async -> Bool {
        isProcessing = true
        errorMessage = nil
        paymentSuccess = false

        do {
            let method = selectedMethod
            let response: PaymentIntentResponse = try await apiClient.post(
                "/v1/payment/create-intent",
                body: PaymentIntentRequest(
                    planId: planId,
                    billingCycle: billingCycle,
                    paymentMethod: method.rawValue
                )
            )

            switch method {
            case .applePay, .creditCard:
                let confirmed = await confirmStripePayment(clientSecret: response.clientSecret)
                isProcessing = false
                paymentSuccess = confirmed
                return confirmed

            case .alipay, .wechatPay, .paypal:
                if let urlString = response.payUrl, let url = URL(string: urlString) {
                    await UIApplication.shared.open(url)
                }
                // Payment confirmation happens via deep link callback;
                // keep isProcessing true until deep link confirms/cancels
                return true
            }
        } catch {
            errorMessage = "支付创建失败：\(error.localizedDescription)"
            isProcessing = false
            return false
        }
    }

    // MARK: - Confirm Stripe Payment (Apple Pay / Credit Card)

    private func confirmStripePayment(clientSecret: String) async -> Bool {
        // TODO: Integrate Stripe iOS SDK
        // STPPaymentHandler.shared().confirmPayment(...)
        do {
            let response: PaymentConfirmResponse = try await apiClient.post(
                "/v1/payment/confirm",
                body: PaymentConfirmRequest(clientSecret: clientSecret)
            )
            return response.success
        } catch {
            await MainActor.run { errorMessage = "支付确认失败" }
            return false
        }
    }

    // MARK: - Handle Deep Link Callback (Alipay / WeChat / PayPal)

    @MainActor
    func handlePaymentCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let orderId = components.queryItems?.first(where: { $0.name == "order_id" })?.value else {
            return
        }

        isProcessing = true
        do {
            let response: PaymentConfirmResponse = try await apiClient.post(
                "/v1/payment/verify-callback",
                body: PaymentCallbackRequest(orderId: orderId)
            )
            paymentSuccess = response.success
            if !response.success {
                errorMessage = "支付验证失败，请联系客服"
            }
        } catch {
            errorMessage = "支付验证失败"
        }
        isProcessing = false
    }
}

// MARK: - Request / Response Types

struct PaymentIntentRequest: Codable {
    let planId: String
    let billingCycle: String
    let paymentMethod: String
}

struct PaymentIntentResponse: Codable {
    let clientSecret: String
    let payUrl: String?
    let orderId: String
}

struct PaymentConfirmRequest: Codable {
    let clientSecret: String
}

struct PaymentCallbackRequest: Codable {
    let orderId: String
}

struct PaymentConfirmResponse: Codable {
    let success: Bool
    let planId: String?
    let expiresAt: Date?
}
