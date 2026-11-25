import SwiftUI
import ActivityKit

// MARK: - Settings building blocks (both roles)
//
// Settings is grouped by what each part does, top to bottom: who you are and your
// plan, display and language, the features ShouDeng is known for (the lock screen
// card), then one group per job (SOS, automatic protection, tools, family, account,
// data, about). Every group is a titled card of rows; each row has a coloured icon,
// so a group can be found by colour as well as by name.

enum SettingsTint {
    static let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    static let sos = Color(red: 196/255, green: 69/255, blue: 60/255)
    static let amber = Color(red: 222/255, green: 146/255, blue: 40/255)
    static let pro = Color(red: 107/255, green: 92/255, blue: 165/255)
    static let blue = Color(red: 46/255, green: 112/255, blue: 190/255)
    static let gray = Color(red: 128/255, green: 128/255, blue: 136/255)
}

/// A titled group of rows on one card
struct SettingsSection<Content: View>: View {
    let title: String?
    var footer: String? = nil
    @ViewBuilder let content: () -> Content

    init(_ title: String?, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .settingsCard()
            if let footer {
                Text(footer)
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

extension View {
    /// The card a settings group sits on
    func settingsCard(padding: CGFloat = 12) -> some View {
        self
            .padding(.horizontal, padding)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// White symbol on a rounded square of the group's colour
struct SettingsIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint))
            .accessibilityHidden(true)
    }
}

/// Icon, title (and a line under it), a value and a chevron. The label of a Button or
/// NavigationLink, or on its own for a fixed value.
struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueColor: Color = .secondary
    var chevron = true
    var titleColor: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.scaled(size: 15))
                    .foregroundStyle(titleColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.scaled(size: 13))
                    .foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

/// Icon, title (and a line under it) and a switch
struct SettingsToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                SettingsIcon(systemName: icon, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.scaled(size: 15))
                    if let subtitle {
                        Text(subtitle)
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(SettingsTint.safe)
        .padding(.vertical, 7)
    }
}

/// The hairline between rows, starting under the title (not under the icon)
struct SettingsDivider: View {
    var body: some View { Divider().padding(.leading, 40) }
}

/// Log out / Delete account: red text, centred, on their own card
struct SettingsDestructiveButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.scaled(size: 15, weight: .medium))
                .foregroundStyle(SettingsTint.sos)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.settingsRow)
    }
}

// MARK: - Profile header

/// Photo, name, role · city, and the plan in effect. Tap to edit the profile.
struct SettingsProfileHeader: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    let onEdit: () -> Void

    private var isGuardian: Bool { coordinator.userRole == .guardian }
    private var tint: Color { isGuardian ? SettingsTint.pro : SettingsTint.safe }

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                AvatarView(user: coordinator.currentUser, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(coordinator.currentUser?.displayName ?? lang.localized("settings.profile.notSet"))
                        .font(.scaled(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(roleLine)
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    planChip
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.settingsRow)
        .settingsCard(padding: 14)
        .accessibilityIdentifier("settings.profile")
    }

    private var roleLine: String {
        let role = lang.localized(isGuardian ? "guardian.settings.role.guardian" : "protected.settings.role.protected")
        guard let city = coordinator.currentUser?.cityName, !city.isEmpty else { return role }
        return "\(role) · \(city)"
    }

    private var planChip: some View {
        let store = coordinator.storeKitManager
        let paid = store.activePlanId != "free"
        return Text(paid ? store.planDisplayName(for: store.activePlanId)
                         : lang.localized("guardian.settings.subscription.free"))
            .font(.scaled(size: 11, weight: .semibold))
            .foregroundStyle(paid ? tint : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(paid ? tint.opacity(0.14) : Color(.tertiarySystemFill)))
    }
}

// MARK: - Plan

/// The plan, at the top of Settings for both roles.
///   - Paying: the plan, renewal, seats used, and a way to add people or manage it.
///   - Covered by someone in the family: whose plan it is and the seats.
///   - Free guardian: what the plan adds, the starting price from the App Store, one
///     button into the paywall, and that SOS stays free.
///   - Free person looked after: ask their family to start it (or start it themselves).
struct SettingsPlanCard: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var showInviteGuardian = false
    /// DEBUG gallery only: draw the no-plan card of this role
    var debugFreeRole: UserRole? = nil

    private var store: StoreKitManager { coordinator.storeKitManager }
    private var isGuardian: Bool { (debugFreeRole ?? coordinator.userRole) == .guardian }
    private var tint: Color { isGuardian ? SettingsTint.pro : SettingsTint.safe }

    var body: some View {
        content
            .settingsCard(padding: 14)
            .sheet(isPresented: $showInviteGuardian) {
                InviteGuardianView().environmentObject(coordinator)
            }
            .task {
                await store.refreshSubscriptionStatus()
                if store.products.isEmpty { await store.fetchProducts() }
            }
            .accessibilityIdentifier("settings.plan")
    }

    @ViewBuilder private var content: some View {
        if debugFreeRole != nil {
            if isGuardian { freeGuardian } else { freeProtected }
        } else if let status = store.subscriptionStatus, status.isActive {
            paid(title: store.planDisplayName(for: status.planId),
                 detail: status.expiresDate.map {
                     String(format: lang.localized("guardian.settings.subscription.expiresAt"),
                            $0.formatted(.dateTime.year().month().day()))
                 },
                 manage: true)
        } else if let payer = store.coveredByName {
            paid(title: store.planDisplayName(for: store.activePlanId),
                 detail: String(format: lang.localized("household.coveredBy"), payer),
                 manage: false)
        } else if store.activePlanId != "free" {
            // Lifetime, or the sample family's plan
            paid(title: store.planDisplayName(for: store.activePlanId),
                 detail: store.lifetimePlanId != nil ? lang.localized("store.cycle.lifetime") : nil,
                 // Only whoever bought it manages it
                 manage: store.lifetimePlanId != nil || store.purchasedPlanId != nil)
        } else if isGuardian {
            freeGuardian
        } else {
            freeProtected
        }
    }

    private func paid(title: String, detail: String?, manage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                SettingsIcon(systemName: "checkmark.seal.fill", tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.scaled(size: 16, weight: .semibold))
                    if let detail {
                        Text(detail).font(.scaled(size: 12)).foregroundStyle(.secondary)
                    }
                    if let seats = seatsLine {
                        Text(seats).font(.scaled(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if manage {
                NavigationLink {
                    GuardianPlanBillingView().environmentObject(coordinator)
                } label: {
                    Text(lang.localized(store.purchasedPlanId == "seats" ? "plan.addPeople" : "guardian.settings.subscription.manage"))
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.12)))
                }
                .buttonStyle(.settingsRow)
            }
        }
        .padding(.vertical, 8)
    }

    private var seatsLine: String? {
        guard let h = store.household, h.planId != "free", h.maxGuardians >= 0, h.maxProtected >= 0 else { return nil }
        return String(format: lang.localized("household.seats"), h.guardians, h.maxGuardians, h.protected, h.maxProtected)
    }

    /// "From $4.99 / month": the App Store price of the smallest family (1 + 1)
    private var startingPrice: String? {
        store.seatProduct(for: SeatConfig(protected: 1, guardians: 1, dual: false), period: .monthly)?.displayPrice
    }

    private var freeGuardian: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.badge.gearshape.fill")
                    .font(.scaled(size: 18))
                    .foregroundStyle(tint)
                Text(lang.localized("plan.free.title"))
                    .font(.scaled(size: 17, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(["plan.benefit.history", "plan.benefit.reports", "plan.benefit.family"], id: \.self) { key in
                    Label(lang.localized(key), systemImage: "checkmark")
                        .font(.scaled(size: 13))
                        .foregroundStyle(.primary)
                }
            }
            .labelStyle(PlanBenefitLabelStyle(tint: tint))
            if let price = startingPrice {
                Text(String(format: lang.localized("plan.free.from"), price))
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                GuardianPlanBillingView().environmentObject(coordinator)
            } label: {
                Text(lang.localized("plan.free.cta"))
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 11).fill(tint))
            }
            .buttonStyle(.settingsRow)
            .accessibilityIdentifier("settings.plan.choose")
            Label(lang.localized("plan.free.floor"), systemImage: "sos.circle")
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    private var freeProtected: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "house.fill")
                    .font(.scaled(size: 18))
                    .foregroundStyle(tint)
                Text(lang.localized("plan.protected.title"))
                    .font(.scaled(size: 17, weight: .bold))
            }
            Text(lang.localized("plan.protected.desc"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if coordinator.myGuardians.isEmpty {
                Button { showInviteGuardian = true } label: {
                    primaryLabel(lang.localized("plan.protected.invite"))
                }
                .buttonStyle(.settingsRow)
            } else {
                // The person's own message, sent from their own phone (Messages, WeChat…)
                ShareLink(item: lang.localized("plan.protected.askMessage")) {
                    primaryLabel(lang.localized("plan.protected.ask"))
                }
                .buttonStyle(.settingsRow)
                .accessibilityIdentifier("settings.plan.ask")
            }
            NavigationLink {
                GuardianPlanBillingView().environmentObject(coordinator)
            } label: {
                Text(lang.localized("plan.protected.self"))
                    .font(.scaled(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.settingsRow)
            Label(lang.localized("plan.free.floor"), systemImage: "sos.circle")
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title)
            .font(.scaled(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 11).fill(tint))
    }
}

#if DEBUG
/// `-settings-free-plan`: both no-plan cards on one screen
struct SettingsPlanCardGallery: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsPlanCard(debugFreeRole: .guardian)
                    SettingsPlanCard(debugFreeRole: .protected_)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}
#endif

private struct PlanBenefitLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.scaled(size: 12, weight: .bold)).foregroundStyle(tint)
            configuration.title
        }
    }
}

// MARK: - Display and language

/// Language as buttons in each language's own name (findable whatever language the
/// app is in now), text size as four samples, and dark mode.
struct SettingsDisplaySection: View {
    @ObservedObject private var lang = LanguageManager.shared
    @ObservedObject private var fontScale = FontScaleManager.shared
    @AppStorage("app_dark_mode") private var darkMode = false
    let tint: Color

    var body: some View {
        SettingsSection(lang.localized("settings.section.display")) {
            VStack(alignment: .leading, spacing: 8) {
                rowTitle("globe", lang.localized("settings.language") + languageHint)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        let selected = lang.current == language
                        Button { lang.choose(language) } label: {
                            HStack(spacing: 4) {
                                if selected { Image(systemName: "checkmark").font(.scaled(size: 11, weight: .bold)) }
                                Text(language.nativeName)
                                    .font(.scaled(size: 14, weight: selected ? .semibold : .regular))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(selected ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(selected ? tint : Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("settings.language.\(language.rawValue)")
                    }
                }
            }
            .padding(.vertical, 10)

            SettingsDivider()

            VStack(alignment: .leading, spacing: 8) {
                rowTitle("textformat.size", lang.localized("settings.fontsize"))
                HStack(spacing: 8) {
                    ForEach(FontScaleLevel.allCases, id: \.self) { level in
                        let selected = fontScale.level == level
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { fontScale.level = level }
                        } label: {
                            VStack(spacing: 3) {
                                Text("Aa")
                                    .font(.system(size: 13 * level.scale, weight: .semibold))
                                    .frame(height: 30)
                                Text(level.label)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(selected ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(selected ? tint : Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(level.label)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                Text(lang.localized("settings.fontsize.hint"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)

            SettingsDivider()

            SettingsToggleRow(icon: darkMode ? "moon.fill" : "sun.max.fill",
                              tint: darkMode ? .indigo : SettingsTint.amber,
                              title: lang.localized("settings.darkMode", fallback: "Dark Mode"),
                              isOn: $darkMode)
        }
    }

    /// "Language" in English too when the app is in another language
    private var languageHint: String { lang.current == .english ? "" : " · Language" }

    private func rowTitle(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: icon, tint: SettingsTint.blue)
            Text(title).font(.scaled(size: 15))
        }
    }
}

// MARK: - Lock screen card (featured)

/// The lock screen card as it looks now, its switch, and the way into customising it
struct LockScreenCardFeature: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage("lockscreen_card_enabled") private var enabled = true
    @State private var style = LockScreenCardStyle.stored

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsToggleRow(icon: "lock.rectangle.stack.fill", tint: SettingsTint.safe,
                              title: lang.localized("settings.lockscreen"),
                              subtitle: lang.localized("settings.lockscreen.desc"),
                              isOn: $enabled)
                .onChange(of: enabled) { _, on in
                    if on {
                        coordinator.startLiveActivityIfNeeded()
                    } else {
                        coordinator.liveActivityManager.endAllActivities()
                    }
                }

            LockScreenCardPreview(style: style)
                .opacity(enabled ? 1 : 0.45)

            // Live Activities switched off for the app in iOS Settings: no card can appear
            if enabled && !ActivityAuthorizationInfo().areActivitiesEnabled {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { ExternalURL.open(url) }
                } label: {
                    Label(lang.localized("lsc.disabledInSettings"), systemImage: "exclamationmark.triangle.fill")
                        .font(.scaled(size: 12))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
            if coordinator.isDemo {
                Text(lang.localized("lsc.demoNote"))
                    .font(.scaled(size: 11))
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                LockScreenCardSettingsView().environmentObject(coordinator)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lang.localized("lsc.customize")).font(.scaled(size: 14, weight: .semibold))
                        Text(lang.localized("lsc.customize.detail")).font(.scaled(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.scaled(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(SettingsTint.safe)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(SettingsTint.safe.opacity(0.10)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.settingsRow)
            .accessibilityIdentifier("settings.lockscreen.customize")
        }
        .padding(.vertical, 8)
        // Back from Customize: show the style just chosen
        .onAppear { style = LockScreenCardStyle.stored }
    }
}
