import SwiftUI
import StoreKit

// MARK: - Per-person paywall and the Seats page (docs/pricing/SEATS.md)
//
// One screen for both: buying (new) and changing seats later (manage).
//   - Steppers (and a number field) for the people looked after and the people looking
//     after; "I'm looked after too" for the payer; monthly / yearly.
//   - The price shown is the App Store price of the level the seats land on (the
//     product's displayPrice, in the local currency); the per-person prices beside the
//     steppers are shown only in US dollars, where they are the list prices.
//   - Buying: the level's product (with the app account token), then the seats are
//     sent to the server (PUT /v1/payment/seats). Changing: the same, and when the
//     level stays the same only the seats are sent. Fewer seats than people already in
//     the family is refused: remove someone first.
//   - SOS, silent SOS and tracker detection are free on every plan (said at the top).

struct SeatPaywallView: View {
    enum Mode: Equatable {
        /// No per-person plan yet
        case new
        /// Changing the seats of the per-person plan
        case manage
    }

    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    var mode: Mode = .new
    /// Off where the screen already has a title (the setup after sign-up)
    var showsHeader = true
    /// More people looked after than now (an invite that needs a seat)
    var addProtected = 0
    /// Someone else in the family already pays (their name): said at the top
    var coveredBy: String? = nil
    /// Bought or changed
    var onDone: (() -> Void)? = nil

    @State private var config = SeatConfig(protected: 1, guardians: 1, dual: false)
    @State private var period: SeatPricing.Period = .monthly
    @State private var started = false
    @State private var busy = false
    @State private var message: String?
    @State private var showPrivacyPolicy = false
    @State private var restoreResult: StoreKitManager.RestoreResult?

    private var store: StoreKitManager { coordinator.storeKitManager }
    private var pricing: SeatPricing { store.seatPricing }
    private var product: Product? { store.seatProduct(for: config, period: period) }

    private let ink = Color.appInk
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 165/255, blue: 61/255)
    private let navy = Color(red: 20/255, green: 36/255, blue: 58/255)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if showsHeader { header }
                if let coveredBy { coveredBanner(coveredBy) }
                periodPicker
                protectedSection
                guardiansSection
                totalCard
                actionButton
                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(red: 251/255, green: 248/255, blue: 241/255).ignoresSafeArea())
        .navigationTitle(lang.localized(mode == .manage ? "seats.nav.title" : "guardian.billing.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showPrivacyPolicy) { PrivacyPolicyView().environmentObject(coordinator) }
        .alert(lang.localized("guardian.billing.restore.purchase"), isPresented: Binding(
            get: { restoreResult != nil }, set: { if !$0 { restoreResult = nil } }
        )) {
            Button(lang.localized("guardian.billing.ok")) {}
        } message: {
            Text(lang.localized(restoreResult == .restored ? "guardian.billing.restore.success" : "guardian.billing.restore.none"))
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lang.localized(mode == .manage ? "seats.manage.title" : "seats.title"))
                .font(.scaled(size: 22, weight: .bold))
                .foregroundStyle(ink)
            Label(lang.localized("seats.safetyFloor"), systemImage: "sos.circle.fill")
                .font(.scaled(size: 13))
                .foregroundStyle(safe)
        }
        .padding(.bottom, 4)
    }

    private var periodPicker: some View {
        Picker("", selection: $period) {
            Text(lang.localized("seats.period.monthly")).tag(SeatPricing.Period.monthly)
            Text(lang.localized("seats.period.yearly")).tag(SeatPricing.Period.yearly)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("seats.period")
    }

    private var protectedSection: some View {
        card {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.localized("seats.protected.title")).font(.scaled(size: 16, weight: .semibold)).foregroundStyle(ink)
                    Text(unitLine(lang.localized("seats.protected.desc"), price: { $0.protected }))
                        .font(.scaled(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                CountStepper(value: $config.protected, range: 1...pricing.max.protected, label: lang.localized("seats.protected.title"))
                    .accessibilityIdentifier("seats.protected")
            }
            capNote(config.protected, cap: pricing.caps.protected)
            Text(lang.localized("seats.included.protected"))
                .font(.scaled(size: 12)).foregroundStyle(ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var guardiansSection: some View {
        card {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.localized("seats.guardians.title")).font(.scaled(size: 16, weight: .semibold)).foregroundStyle(ink)
                    Text(guardiansLine).font(.scaled(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                CountStepper(value: $config.guardians, range: 1...pricing.max.guardians, label: lang.localized("seats.guardians.title"))
                    .accessibilityIdentifier("seats.guardians")
            }
            capNote(config.guardians, cap: pricing.caps.guardians)
            Text(lang.localized("seats.included.guardian"))
                .font(.scaled(size: 12)).foregroundStyle(ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle(isOn: $config.dual) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.localized("seats.dual.title")).font(.scaled(size: 15, weight: .semibold)).foregroundStyle(ink)
                    Text(unitLine(lang.localized("seats.dual.desc"), price: { $0.dual }, plus: true))
                        .font(.scaled(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(safe)
            .accessibilityIdentifier("seats.dual")
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(breakdown)
                .font(.scaled(size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                if let product {
                    Text(store.pricing(for: product).recurringPrice())
                        .font(.scaled(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("seats.total")
                    Spacer()
                    Text(String(format: lang.localized("seats.perDay"), perDay(product)))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                } else if store.isLoadingProducts || !started {
                    ProgressView().tint(.white)
                    Text(lang.localized("seats.loading")).font(.scaled(size: 13)).foregroundStyle(.white.opacity(0.8))
                } else {
                    Text(lang.localized("store.error.loadPlans")).font(.scaled(size: 13)).foregroundStyle(.white)
                    Spacer()
                    Button(lang.localized("seats.retry")) { Task { await store.fetchProducts() } }
                        .font(.scaled(size: 13, weight: .semibold)).foregroundStyle(lamp)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(navy))
    }

    private var actionButton: some View {
        VStack(spacing: 8) {
            Button {
                Task { await apply() }
            } label: {
                HStack(spacing: 6) {
                    if busy { ProgressView().tint(navy) }
                    Text(actionTitle)
                }
                .font(.scaled(size: 16, weight: .semibold))
                .foregroundStyle(navy)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 13).fill(lamp.opacity(actionDisabled ? 0.45 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(actionDisabled)
            .accessibilityIdentifier("seats.subscribe")
            if let message {
                Text(message)
                    .font(.scaled(size: 13))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("seats.message")
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text(lang.localized("seats.later"))
                .font(.scaled(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let product {
                Text(store.pricing(for: product).legalText(planName: store.planDisplayName(for: "seats")))
                    .font(.scaled(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(lang.localized("guardian.billing.restore.purchase")) {
                Task {
                    restoreResult = await store.restorePurchases()
                    await coordinator.fetchSubscription()
                }
            }
            .font(.scaled(size: 13)).foregroundStyle(.secondary)
            SubscriptionLegalLinks(accent: navy) { showPrivacyPolicy = true }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func coveredBanner(_ payer: String) -> some View {
        Label(String(format: lang.localized("seats.coveredBy"), payer.isEmpty ? lang.localized("seats.someone") : payer),
              systemImage: "house.fill")
            .font(.scaled(size: 14, weight: .semibold))
            .foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(safe.opacity(0.1)))
    }

    // MARK: Pieces

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 231/255, green: 225/255, blue: 212/255)))
    }

    @ViewBuilder private func capNote(_ count: Int, cap: Int) -> some View {
        if count > cap {
            Text(String(format: lang.localized("seats.cap.over"), cap + 1, cap))
                .font(.scaled(size: 12)).foregroundStyle(safe)
        } else if count == cap {
            Text(lang.localized("seats.cap.at")).font(.scaled(size: 12)).foregroundStyle(safe)
        }
    }

    /// Per-person prices are list prices in US dollars: shown only there
    private var showsUnitPrices: Bool {
        (product?.priceFormatStyle.currencyCode ?? "USD") == "USD"
    }

    private func dollars(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }

    private func unitLine(_ text: String, price: (SeatPricing.Prices) -> Int, plus: Bool = false) -> String {
        guard showsUnitPrices else { return text }
        let cents = price(pricing.prices[period])
        let amount = plus ? "+" + dollars(cents) : String(format: lang.localized("seats.each"), dollars(cents))
        return String(format: lang.localized(period == .monthly ? "seats.unit.month" : "seats.unit.year"), text, amount)
    }

    private var guardiansLine: String {
        guard showsUnitPrices else { return lang.localized("seats.perPerson") }
        let p = pricing.prices[period]
        return String(format: lang.localized("seats.guardians.desc"), dollars(p.firstGuardian), dollars(p.extraGuardian))
    }

    private var breakdown: String {
        var parts = [String(format: lang.localized("seats.breakdown.protected"), config.protected),
                     String(format: lang.localized("seats.breakdown.guardians"), config.guardians)]
        if config.dual { parts.append(lang.localized("seats.breakdown.dual")) }
        return parts.joined(separator: " · ")
    }

    private func perDay(_ product: Product) -> String {
        let days: Decimal = period == .monthly ? 30 : 365
        return (product.price / days).formatted(product.priceFormatStyle)
    }

    private var unchanged: Bool {
        mode == .manage && store.seats?.chosen == config && store.currentSeatProductId == product?.id
    }

    private var actionDisabled: Bool { busy || product == nil || unchanged }

    private var actionTitle: String {
        if mode == .manage { return lang.localized(unchanged ? "seats.current" : "seats.update") }
        return product.map { store.pricing(for: $0).subscribeButtonTitle() } ?? lang.localized("seats.subscribe")
    }

    // MARK: Actions

    private func load() async {
        guard !started else { return }
        // Start from the family as it is (and the seats paid for, when changing them)
        if mode == .manage, let chosen = store.seats?.chosen ?? store.seats?.paidFor {
            config = chosen
            if let id = store.currentSeatProductId, let level = pricing.level(of: id) { period = level.period }
        } else {
            let h = store.household
            let protectedNow = coordinator.isGuardianSide ? coordinator.protectedPersons.count : (h?.protected ?? 0)
            config = SeatConfig(protected: max(protectedNow, 1), guardians: max(h?.guardians ?? 1, 1),
                                dual: coordinator.hasBothRoles)
        }
        if addProtected > 0 { config.protected = min(config.protected + addProtected, pricing.max.protected) }
        started = true
        await store.refreshSeatPricing()
        if store.products.isEmpty { await store.fetchProducts() }
    }

    private func apply() async {
        guard let product else { return }
        busy = true
        message = nil
        defer { busy = false }
        // The same level: only the seats change
        if store.currentSeatProductId != product.id {
            guard await store.purchase(product) else {
                message = store.errorMessage
                return
            }
            // The server learns of the purchase before it is asked to keep the seats
            _ = await store.syncEntitlementsWithServer()
        }
        switch await store.updateSeats(config) {
        case .success:
            await store.refreshHousehold()
            message = lang.localized("seats.updated")
            onDone?()
        case .failure(.inUse(let protectedCount, let guardians)):
            message = String(format: lang.localized("seats.inUse"), protectedCount, guardians)
        case .failure(.notPaid):
            // Bought, not confirmed yet: kept on the phone and sent again on refresh
            message = lang.localized("seats.confirming")
            onDone?()
        case .failure:
            message = lang.localized("seats.failed")
        }
    }
}

// MARK: - Count stepper: − n +, the number can also be typed

private struct CountStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            round("minus") { value = max(range.lowerBound, value - 1) }
                .disabled(value <= range.lowerBound)
                .accessibilityLabel(LanguageManager.shared.localized("seats.decrease"))
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.scaled(size: 17, weight: .semibold).monospacedDigit())
                .frame(width: 42, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
                .focused($focused)
                .accessibilityLabel(label)
                .onChange(of: text) { _, new in
                    let digits = new.filter(\.isNumber)
                    if digits != new { text = digits; return }
                    // Kept within the range as it's typed; empty while typing is fine
                    if let n = Int(digits) { value = min(max(n, range.lowerBound), range.upperBound) }
                }
                .onChange(of: focused) { _, isFocused in if !isFocused { text = "\(value)" } }
            round("plus") { value = min(range.upperBound, value + 1) }
                .disabled(value >= range.upperBound)
                .accessibilityLabel(LanguageManager.shared.localized("seats.increase"))
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { _, v in if !focused { text = "\(v)" } }
    }

    private func round(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Circle().stroke(Color(.separator)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
