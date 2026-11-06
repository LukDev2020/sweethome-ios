import SwiftUI
import StoreKit

// MARK: - Post-Signup Setup Wizard
//
// Shown once after first signup. Collects:
//   Step 1: Email (account recovery)
//   Step 2: City (pre-filled from country)
//   Step 3: Biometric (Face ID / Touch ID)
//   Step 4: [Guardian only] Subscription plan
//   Step 5: Invite guidance (role-specific)

struct PostSignupWizardView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var email = ""
    @State private var cityName = ""
    @State private var isLoading = false

    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
    private let cream = Color(red: 252/255, green: 242/255, blue: 218/255)
    private let ink = Color.appInk
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    private var totalSteps: Int {
        wizardRole == .guardian ? 5 : 4
    }

    private var stepTitles: [String] {
        var titles = [lang.localized("wizard.step.email"), lang.localized("wizard.step.city"), lang.localized("wizard.step.security"), lang.localized("wizard.step.invite")]
        if wizardRole == .guardian {
            titles.insert(lang.localized("wizard.step.plan"), at: 3)
        }
        return titles
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            progressBar
                .padding(.top, 16)
                .padding(.bottom, 24)

            // Step content
            Group {
                switch currentStep {
                case 0: emailStep
                case 1: cityStep
                case 2: biometricStep
                case 3 where wizardRole == .guardian: paymentStep
                case 3: inviteStep
                case 4: inviteStep
                default: EmptyView()
                }
            }
            .frame(maxHeight: .infinity)

            // Bottom buttons
            bottomButtons
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .background(Color(.systemBackground))
        .onAppear {
            // Pre-fill city from country code
            if let country = coordinator.signupCountry {
                cityName = defaultCity(for: country.isoCode)
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                VStack(spacing: 4) {
                    Circle()
                        .fill(index <= currentStep ? navy : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                    Text(stepTitles[index])
                        .font(.scaled(size: 10))
                        .foregroundStyle(index <= currentStep ? ink : .secondary)
                }
            }
        }
    }

    // MARK: - Step 1: Email

    private var emailStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.scaled(size: 48))
                .foregroundStyle(navy.opacity(0.7))

            Text(lang.localized("wizard.email.title"))
                .font(.scaled(size: 22, weight: .bold))
                .foregroundStyle(ink)

            Text(lang.localized("wizard.email.subtitle"))
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            TextField("your@email.com", text: $email)
                .font(.scaled(size: 16))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)

            Spacer()
        }
    }

    // MARK: - Step 2: City

    private var cityStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "building.2")
                .font(.scaled(size: 48))
                .foregroundStyle(navy.opacity(0.7))

            Text(lang.localized("wizard.city.title"))
                .font(.scaled(size: 22, weight: .bold))
                .foregroundStyle(ink)

            Text(lang.localized("wizard.city.subtitle"))
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField(lang.localized("wizard.city.placeholder"), text: $cityName)
                .font(.scaled(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)

            Spacer()
        }
    }

    // MARK: - Step 3: Biometric

    private var biometricStep: some View {
        let biometric = BiometricAuthManager.shared

        return VStack(spacing: 16) {
            Spacer()

            Image(systemName: biometric.biometricIconName)
                .font(.scaled(size: 56))
                .foregroundStyle(navy.opacity(0.7))

            Text(String(format: lang.localized("wizard.biometric.title"), biometric.biometricName))
                .font(.scaled(size: 22, weight: .bold))
                .foregroundStyle(ink)

            Text(lang.localized("wizard.biometric.subtitle"))
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            VStack(spacing: 12) {
                Button {
                    try? biometric.enable()
                    biometric.hasShownPrompt = true
                    advanceStep()
                } label: {
                    Text(String(format: lang.localized("wizard.biometric.enable"), biometric.biometricName))
                        .font(.scaled(size: 15.5, weight: .medium))
                        .foregroundStyle(cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(navy)
                        )
                }

                Button {
                    biometric.hasShownPrompt = true
                    advanceStep()
                } label: {
                    Text(lang.localized("wizard.biometric.skip"))
                        .font(.scaled(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
    }

    // MARK: - Step 4: Payment (Guardian only)
    //
    // Prices, periods and any free trial come from the App Store products; trial
    // wording only when this Apple ID can still use the introductory offer. Each plan
    // is offered monthly, yearly and lifetime (one-time purchase).

    @State private var selectedProductId: String?
    @State private var purchaseInProgress = false
    @State private var purchaseSuccess = false
    @State private var showPrivacyPolicy = false
    @State private var showCancelSubscriptionHint = false

    private var paymentStep: some View {
        let store = coordinator.storeKitManager

        return ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "shield.checkered")
                    .font(.scaled(size: 48))
                    .foregroundStyle(safe.opacity(0.8))
                    .padding(.top, 8)

                Text(lang.localized("wizard.plan.title"))
                    .font(.scaled(size: 22, weight: .bold))
                    .foregroundStyle(ink)

                Text(lang.localized("wizard.plan.subtitle"))
                    .font(.scaled(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                if purchaseSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(safe)
                        Text(lang.localized("wizard.plan.subscribed"))
                            .font(.scaled(size: 15, weight: .medium))
                            .foregroundStyle(safe)
                    }
                    .padding(.top, 8)
                } else if store.products.isEmpty {
                    ProductsUnavailableView(
                        isLoading: store.isLoadingProducts || !store.productsLoadFailed,
                        accent: safe,
                        onRetry: { Task { await store.fetchProducts() } }
                    )
                    .padding(.horizontal, 8)
                } else {
                    VStack(spacing: 10) {
                        ForEach(store.products, id: \.id) { product in
                            productRow(product, isSelected: selectedProductId == product.id)
                        }
                    }
                    .padding(.horizontal, 8)

                    if let selectedId = selectedProductId,
                       let product = store.products.first(where: { $0.id == selectedId }) {
                        let pricing = store.pricing(for: product)
                        Button {
                            Task { await purchaseProduct(product) }
                        } label: {
                            HStack(spacing: 6) {
                                if purchaseInProgress {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(pricing.subscribeButtonTitle())
                                    .font(.scaled(size: 15, weight: .medium))
                                    .foregroundStyle(cream)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(purchaseInProgress ? safe.opacity(0.5) : safe)
                            )
                        }
                        .disabled(purchaseInProgress)
                        .padding(.horizontal, 8)

                        Text(pricing.legalText(planName: store.planDisplayName(for: store.planId(for: product))))
                            .font(.scaled(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                    }
                }

                if let error = store.errorMessage, !store.products.isEmpty {
                    Text(error)
                        .font(.scaled(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                SubscriptionLegalLinks(accent: navy) { showPrivacyPolicy = true }
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView().environmentObject(coordinator)
        }
        .alert(lang.localized("store.lifetime.purchased.title"), isPresented: $showCancelSubscriptionHint) {
            Button(lang.localized("guardian.billing.manage.subscription")) {
                Task {
                    await store.showManageSubscriptions()
                    advanceStep()
                }
            }
            Button(lang.localized("store.later"), role: .cancel) { advanceStep() }
        } message: {
            Text(lang.localized("store.lifetime.cancelSubscriptionHint"))
        }
        .task {
            if store.products.isEmpty {
                await store.fetchProducts()
            }
        }
    }

    private func productRow(_ product: Product, isSelected: Bool) -> some View {
        let store = coordinator.storeKitManager
        let pricing = store.pricing(for: product)
        return Button {
            selectedProductId = product.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(StoreKitManager.isLifetime(product.id)
                         ? String(format: lang.localized("store.lifetime.planName"), store.planDisplayName(for: store.planId(for: product)))
                         : store.planDisplayName(for: store.planId(for: product)))
                        .font(.scaled(size: 15, weight: .medium))
                        .foregroundStyle(ink)
                    Text(pricing.recurringPrice())
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                    if let intro = pricing.introSummary() {
                        Text(intro)
                            .font(.scaled(size: 12, weight: .medium))
                            .foregroundStyle(safe)
                    }
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? safe : .secondary)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(safe)
                        .font(.scaled(size: 16))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? safe.opacity(0.08) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? safe.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
    }

    private func purchaseProduct(_ product: Product) async {
        let store = coordinator.storeKitManager
        let hadRenewingSubscription = store.hasRenewingSubscription
        purchaseInProgress = true
        let success = await store.purchase(product)
        purchaseInProgress = false
        if success {
            purchaseSuccess = true
            // Apple doesn't cancel a running subscription when lifetime access is bought
            if StoreKitManager.isLifetime(product.id), hadRenewingSubscription || store.hasRenewingSubscription {
                showCancelSubscriptionHint = true
                return
            }
            // Auto-advance after a short delay
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            advanceStep()
        }
    }

    // MARK: - Step 5: Invite Guidance
    //
    // Both roles get both options: create a code (the invite carries my side)
    // or enter someone else's code (the shared InviteAcceptSheet decides).

    private var inviteStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: wizardRole == .guardian ? "person.badge.plus" : "person.2.wave.2")
                .font(.scaled(size: 48))
                .foregroundStyle(navy.opacity(0.7))

            Text(lang.localized(wizardRole == .guardian ? "wizard.invite.guardian.title" : "wizard.invite.protected.title"))
                .font(.scaled(size: 22, weight: .bold))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)

            Text(lang.localized(wizardRole == .guardian ? "wizard.invite.guardian.subtitle" : "wizard.invite.protected.subtitle"))
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if isLinked {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(safe)
                    Text(lang.localized("wizard.invite.linked"))
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(safe)
                }
            }

            if wizardRole == .guardian {
                enterCodeButton(prominent: true)
                generateInviteButton
            } else {
                generateInviteButton
                enterCodeButton(prominent: false)
            }

            Spacer()
        }
    }

    /// The role the last steps were laid out for. Accepting an invite in the
    /// wizard can change my role; the step list must not shift under me.
    @State private var lockedRole: UserRole?
    private var wizardRole: UserRole { lockedRole ?? coordinator.userRole }

    private var isLinked: Bool {
        !coordinator.myGuardians.isEmpty || !coordinator.protectedPersons.isEmpty
    }

    private func enterCodeButton(prominent: Bool) -> some View {
        Button {
            coordinator.presentInviteAccept()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                Text(lang.localized(prominent ? "wizard.invite.enterCode" : "wizard.invite.haveCode"))
            }
            .font(.scaled(size: 15, weight: .medium))
            .foregroundStyle(prominent ? cream : navy)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(prominent ? navy : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(navy.opacity(prominent ? 0 : 0.35), lineWidth: 1)
            )
        }
        .padding(.horizontal, 8)
        .accessibilityIdentifier("wizard.invite.enterCode")
    }

    @State private var generatedCode: String?
    @State private var generateError: String?

    private var generateInviteButton: some View {
        VStack(spacing: 12) {
            if let code = generatedCode {
                Text(code)
                    .font(.scaled(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(navy)
                    .padding(.vertical, 8)

                Text(lang.localized("wizard.invite.validFor"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.tertiary)

                Button {
                    let av = UIActivityViewController(activityItems: [
                        String(format: lang.localized("wizard.invite.shareMessage"), code)
                    ], applicationActivities: nil)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = scene.windows.first?.rootViewController {
                        root.present(av, animated: true)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text(lang.localized("wizard.invite.share"))
                    }
                    .font(.scaled(size: 15, weight: .medium))
                    .foregroundStyle(cream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(navy)
                    )
                }
                .padding(.horizontal, 8)
            } else {
                let prominent = wizardRole != .guardian
                Button {
                    Task { await generateCode() }
                } label: {
                    HStack(spacing: 6) {
                        if isLoading {
                            ProgressView()
                                .tint(prominent ? cream : navy)
                        }
                        Text(lang.localized("wizard.invite.generate"))
                    }
                    .font(.scaled(size: 15, weight: .medium))
                    .foregroundStyle(prominent ? cream : navy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(prominent ? navy : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(navy.opacity(prominent ? 0 : 0.35), lineWidth: 1)
                    )
                }
                .disabled(isLoading)
                .padding(.horizontal, 8)
            }

            if let error = generateError {
                Text(error)
                    .font(.scaled(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        HStack {
            // Skip / Back
            if currentStep > 0 && currentStep != 2 {
                Button(lang.localized("wizard.nav.back")) {
                    withAnimation { currentStep -= 1 }
                }
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Next / Skip / Done
            if currentStep == 2 {
                // Biometric step has its own buttons
                EmptyView()
            } else if currentStep == 3 && wizardRole == .guardian {
                // Payment step — skip option (Apple requires non-gated)
                if !purchaseSuccess {
                    Button(lang.localized("wizard.nav.later")) {
                        advanceStep()
                    }
                    .font(.scaled(size: 14))
                    .foregroundStyle(.secondary)
                }
            } else if currentStep == totalSteps - 1 {
                Button {
                    Task { await finishWizard() }
                } label: {
                    HStack(spacing: 4) {
                        Text(lang.localized("wizard.nav.start"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.scaled(size: 15, weight: .medium))
                    .foregroundStyle(cream)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(navy)
                    )
                }
                .disabled(isLoading)
            } else {
                HStack(spacing: 16) {
                    if currentStep == 0 && email.isEmpty {
                        Button(lang.localized("wizard.nav.skip")) {
                            advanceStep()
                        }
                        .font(.scaled(size: 14))
                        .foregroundStyle(.secondary)
                    }

                    Button {
                        advanceStep()
                    } label: {
                        HStack(spacing: 4) {
                            Text(lang.localized("wizard.nav.next"))
                            Image(systemName: "arrow.right")
                        }
                        .font(.scaled(size: 15, weight: .medium))
                        .foregroundStyle(cream)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(navy)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func advanceStep() {
        if currentStep + 1 >= 3, lockedRole == nil {
            lockedRole = coordinator.userRole
        }
        withAnimation { currentStep += 1 }
    }

    private func generateCode() async {
        isLoading = true
        generateError = nil
        do {
            let response: CreateInviteResponse = try await coordinator.apiClient.post(
                "/v1/invite/create",
                // The invite carries my side: a guardian's code asks the other
                // person to be protected, a protected person's asks for a guardian.
                body: CreateInviteRequest(inviterRole: wizardRole)
            )
            generatedCode = response.code
        } catch {
            generateError = lang.localized("wizard.invite.error.generate")
            #if DEBUG
            print("[Wizard] Failed to generate invite: \(error)")
            #endif
        }
        isLoading = false
    }

    private func finishWizard() async {
        isLoading = true

        // Save email and city to server
        var updates: [String: String] = [:]
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty && trimmedEmail.contains("@") {
            updates["email"] = trimmedEmail
        }
        let trimmedCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCity.isEmpty {
            updates["cityName"] = trimmedCity
        }

        if !updates.isEmpty {
            do {
                let _: SuccessResponse = try await coordinator.apiClient.put(
                    "/v1/user/me",
                    body: updates
                )
            } catch {
                #if DEBUG
                print("[Wizard] Failed to save profile: \(error)")
                #endif
            }
        }

        isLoading = false
        onComplete()
    }

    // MARK: - Helpers

    private func defaultCity(for countryCode: String) -> String {
        let map: [String: String] = [
            "CN": "上海", "HK": "香港", "TW": "台北", "JP": "东京",
            "KR": "首尔", "SG": "新加坡", "US": "New York", "CA": "Toronto",
            "GB": "London", "AU": "Sydney", "DE": "Berlin", "FR": "Paris",
        ]
        return map[countryCode] ?? ""
    }
}
