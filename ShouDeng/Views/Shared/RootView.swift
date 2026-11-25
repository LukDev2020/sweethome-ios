import SwiftUI
import TipKit

struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var explore = ExploreModeController.shared
    #if DEBUG
    private var isScreenshotMode: Bool { ScreenshotCapture.isEnabled }
    #else
    private var isScreenshotMode: Bool { false }
    #endif

    var body: some View {
        if isScreenshotMode {
            #if DEBUG
            ScreenshotGalleryView()
            #endif
        } else if explore.isActive, let demo = explore.coordinator {
            // Explore Mode: real screens, demo coordinator, nothing leaves the phone
            DemoRootView(explore: explore, coordinator: demo)
        } else {
            AuthenticatedRootView()
                .onAppear {
                    // The real coordinator lives for the whole app
                    let real = coordinator
                    explore.onSetUpRealFamily = { real.showSignup = true }
                }
        }
    }
}

// MARK: - Authenticated Root View
// Separated so that coordinator observation doesn't interfere with screenshot mode.

private struct AuthenticatedRootView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    /// Version of the three disclaimer screens last confirmed; a new version shows them again
    @AppStorage("onboarding_copy_version") private var onboardingCopyVersion = ""
    // Read so the cover closes as soon as either is confirmed
    @AppStorage("guardian_duty_version") private var guardianDutyVersion = ""
    @AppStorage("terms_accepted_version") private var termsAcceptedVersion = ""
    @AppStorage("setupWizardComplete") private var setupWizardComplete = false
    @AppStorage("app_dark_mode") private var darkModeEnabled = false
    @AppStorage("ui_light_only_screen") private var lightOnlyScreen = false
    @ObservedObject private var biometric = BiometricAuthManager.shared
    @ObservedObject private var fontScale = FontScaleManager.shared
    @ObservedObject private var langManager = LanguageManager.shared
    @ObservedObject private var disguiseService = DisguiseModeService.shared
    @State private var showBiometricPrompt = false
    @ObservedObject private var explore = ExploreModeController.shared

    var body: some View {
        Group {
            if disguiseService.isDisguiseActive {
                // Disguise mode — show fake app interface
                switch disguiseService.currentDisguise {
                case .calculator:
                    DisguiseCalculatorView()
                case .weather:
                    DisguiseWeatherView()
                case .notes:
                    DisguiseNotesView()
                case .none:
                    EmptyView()
                }
            } else
            if ProcessInfo.processInfo.arguments.contains("-show-onboarding") {
                OnboardingView(isComplete: $onboardingComplete)
            } else if !onboardingComplete || onboardingCopyVersion != DisclaimerCopy.Onboarding.version {
                // D-05: Disclaimer onboarding before any auth/login
                OnboardingView(isComplete: $onboardingComplete)
                    .transition(.opacity)
            } else {
                switch coordinator.authState {
                case .unknown:
                    splashView
                case .loggedOut:
                    LoginView()
                        .sheet(isPresented: $coordinator.showSignup) {
                            SignupView()
                        }
                case .loggedIn:
                    Group {
                        if biometric.isEnabled && !biometric.isUnlocked {
                            BiometricGateView()
                        } else if coordinator.showRiderSetup {
                            // The setup after sign-up (the steps the chosen sides need), or
                            // the rider setup: a crew / partner link, Settings, the home card
                            RiderSetupView(steps: coordinator.setupSteps, start: coordinator.riderSetupStartStep)
                                .environmentObject(coordinator)
                        } else if showsSetupWizard {
                            PostSignupWizardView(onComplete: {
                                setupWizardComplete = true
                                coordinator.showSetupWizard = false
                            })
                            .environmentObject(coordinator)
                        } else {
                            // Banners take their own space above the screens instead of
                            // floating over the navigation bar title.
                            VStack(spacing: 0) {
                                // Two or more sides (work, my safety, family): switch the home's side
                                if coordinator.homeSides.count > 1 {
                                    HomeSideSwitch()
                                        .environmentObject(coordinator)
                                }
                                FamilyStatusBar()
                                    .environmentObject(coordinator)
                                betaBanner
                                DegradationBannerView()
                                    .environmentObject(coordinator)
                                SatelliteModeBanner()
                                    .environmentObject(coordinator)
                                switch coordinator.userRole {
                                case .protected_:
                                    ProtectedTabView()
                                case .guardian:
                                    GuardianTabView()
                                }
                            }
                            .sosOverlays(coordinator)
                            .alert(
                                LanguageManager.shared.localized("sos.confirmExternal.title"),
                                isPresented: Binding(
                                    get: { coordinator.pendingSOSConfirmation != nil },
                                    set: { if !$0 { coordinator.pendingSOSConfirmation = nil } }
                                )
                            ) {
                                Button(LanguageManager.shared.localized("sos.confirmExternal.send"), role: .destructive) {
                                    coordinator.confirmPendingSOS()
                                }
                                Button(LanguageManager.shared.localized("common.cancel"), role: .cancel) {
                                    coordinator.pendingSOSConfirmation = nil
                                }
                            } message: {
                                Text(LanguageManager.shared.localized("sos.confirmExternal.message"))
                            }
                            .sheet(isPresented: $showBiometricPrompt) {
                                BiometricEnablePromptView(isPresented: $showBiometricPrompt)
                            }
                            // Terms not agreed to (accounts from before the checkbox, or a
                            // Terms update), then a guardian's duties — once per version
                            .fullScreenCover(isPresented: complianceBinding, onDismiss: {
                                Task { await coordinator.syncConsentRecords() }
                            }) {
                                ComplianceGateView().environmentObject(coordinator)
                            }
                            .onAppear {
                                // After login, offer biometric setup if available (skip if wizard already handled it)
                                if biometric.isAvailable && !biometric.hasShownPrompt && !biometric.isEnabled && setupWizardComplete {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        showBiometricPrompt = true
                                    }
                                }
                            }
                        }
                    }
                    // Invite links, family circle, Settings, the setup wizard and the
                    // sign-up invite path all open the same confirmation sheet.
                    .sheet(isPresented: inviteSheetBinding, onDismiss: {
                        coordinator.pendingInviteCode = nil
                    }) {
                        InviteAcceptSheet(initialCode: coordinator.pendingInviteCode)
                            .environmentObject(coordinator)
                    }
                }
            }
        }
        .preferredColorScheme(darkModeEnabled ? .dark : .light)
        .id("\(fontScale.level.rawValue)-\(langManager.current.rawValue)")
        // Login, Face ID gate and setup wizard are drawn light only: tell the app root
        .onChange(of: onLightOnlyScreen, initial: true) { _, light in lightOnlyScreen = light }
    }

    /// Screens designed light (cream background, navy and brand-blue text)
    private var onLightOnlyScreen: Bool {
        guard case .loggedIn = coordinator.authState else { return true }
        if biometric.isEnabled && !biometric.isUnlocked { return true }
        return showsSetupWizard
    }

    /// After sign-up. Also on a phone that finished the wizard for an earlier account,
    /// when the person left the demo to invite the people they added there.
    private var showsSetupWizard: Bool {
        coordinator.showSetupWizard && (!setupWizardComplete || !explore.inviteHandoff.isEmpty)
    }

    private var complianceBinding: Binding<Bool> {
        Binding(
            get: {
                _ = (guardianDutyVersion, termsAcceptedVersion) // re-evaluate when either changes
                return ComplianceGateView.isNeeded(role: coordinator.userRole, isDemo: coordinator.isDemo)
            },
            set: { _ in } // closes when everything needed is confirmed
        )
    }

    private var inviteSheetBinding: Binding<Bool> {
        Binding(
            get: {
                InviteSheetGate.isPresented(
                    requested: coordinator.showInviteAccept,
                    authState: coordinator.authState,
                    biometricLocked: biometric.isEnabled && !biometric.isUnlocked
                )
            },
            set: { if !$0 { coordinator.showInviteAccept = false } }
        )
    }

    // MARK: - Beta Banner

    @ViewBuilder
    private var betaBanner: some View {
        #if BETA
        BetaBanner() // TestFlight builds only (BuildChannel.swift)
        #endif
    }

    // MARK: - Splash

    private var splashView: some View {
        VStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(LanguageManager.shared.current.brandName)
                .font(.scaled(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Family status bar

/// The orange bar at the top of the app: the family's state in one line.
/// Guardian: "Everyone's safe · watching over 2" / "Mom hasn't checked in" / "Mom needs help".
/// Protected person: "3 family members are watching over you" / "SOS in progress".
/// Turns red when someone needs help; tapping it goes straight there.
struct FamilyStatusBar: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let ink = Color.inkSolid // on the fixed lamp-orange status bar
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    private enum Level { case calm, attention, urgent }

    private struct Status {
        let level: Level
        let icon: String
        let text: String
        var action: (() -> Void)? = nil
    }

    private var status: Status {
        coordinator.userRole == .guardian ? guardianStatus : protectedStatus
    }

    private var guardianStatus: Status {
        let persons = coordinator.protectedPersons
        if let sos = persons.first(where: { coordinator.guardianSOS[$0.id] != nil || $0.activeSOS != nil }) {
            let id = sos.id
            return Status(level: .urgent, icon: "exclamationmark.triangle.fill",
                          text: String(format: lang.localized("status.guardian.sos"), sos.user.displayName),
                          action: { coordinator.pendingAlertPersonId = id })
        }
        let late = persons.filter { $0.isOverdue || $0.status == .overdue || $0.status == .alert }
        if let first = late.first {
            let text = late.count == 1
                ? String(format: lang.localized("status.guardian.overdue"), first.user.displayName)
                : String(format: lang.localized("status.guardian.overdueMore"), first.user.displayName, late.count - 1)
            return Status(level: .attention, icon: "clock.badge.exclamationmark", text: text)
        }
        if persons.isEmpty {
            return Status(level: .calm, icon: "person.badge.plus", text: lang.localized("status.guardian.none"),
                          action: { coordinator.presentInviteAccept() })
        }
        return Status(level: .calm, icon: "checkmark.shield.fill",
                      text: String(format: lang.localized("status.guardian.allSafe"), persons.count))
    }

    private var protectedStatus: Status {
        // Watch back: a guardian I look after called SOS
        if let sos = coordinator.protectedPersons.first(where: { coordinator.guardianSOS[$0.id] != nil || $0.activeSOS != nil }) {
            let id = sos.id
            return Status(level: .urgent, icon: "exclamationmark.triangle.fill",
                          text: String(format: lang.localized("status.guardian.sos"), sos.user.displayName),
                          action: { coordinator.pendingAlertPersonId = id })
        }
        // A duress-concealed SOS must look ended
        if coordinator.activeSOSEvent != nil, !coordinator.sosConcealed {
            return Status(level: .urgent, icon: "sos", text: lang.localized("status.protected.sos"),
                          action: { coordinator.isSOSScreenPresented = true })
        }
        if coordinator.isTrackingPaused {
            return Status(level: .attention, icon: "location.slash.fill", text: lang.localized("status.protected.paused"))
        }
        let count = coordinator.myGuardians.count
        if count == 0 {
            return Status(level: .calm, icon: "person.badge.plus", text: lang.localized("status.protected.none"),
                          action: { coordinator.presentInviteAccept() })
        }
        return Status(level: .calm, icon: "shield.fill",
                      text: lang.localized("status.protected.guarded", count: count))
    }

    var body: some View {
        let s = status
        let background: Color = s.level == .urgent ? alert : lamp
        let foreground: Color = s.level == .urgent ? .white : ink
        Button {
            StatusBarTip().invalidate(reason: .actionPerformed)
            s.action?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: s.icon)
                    .font(.scaled(size: 14, weight: .semibold))
                Text(s.text)
                    .font(.scaled(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if s.action != nil {
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(background.ignoresSafeArea(edges: .top))
        }
        .buttonStyle(.plain)
        // Not .disabled: that greys the whole bar out when it has nothing to open
        .allowsHitTesting(s.action != nil)
        .appTip(coordinator.userRole == .guardian && s.level != .calm && s.action != nil
                    ? AppTips.available(StatusBarTip()) : nil, arrowEdge: .top)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(s.level == .urgent ? .isHeader : [])
    }
}


/// Top of the home for someone with two or more sides: "Work" (rides or drives for
/// work, with family care), "My safety" (or "Rider" for a pure rider), "My family".
/// Only the screens change: fall detection, location, SOS keep running on every side,
/// and family SOS alerts arrive on every side. A shift brings Work up, its end My safety.
struct HomeSideSwitch: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    private var familyAlert: Bool { !coordinator.guardianSOS.isEmpty }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(coordinator.homeSides, id: \.self) { side in
                segment(side)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.sideSwitch")
    }

    @ViewBuilder private func segment(_ side: HomeSide) -> some View {
        switch side {
        case .work:
            button(.work, icon: coordinator.workKind == "driver" ? "car.fill" : "bicycle",
                   title: lang.localized(coordinator.workKind == "driver" ? "roles.switch.driver" : "roles.switch.work"),
                   alert: false, onShift: coordinator.isOnShift)
        case .me:
            let rider = coordinator.familyHomeStyle == HomeStyle.rider.rawValue
            button(.me, icon: rider ? "bicycle" : "shield.fill",
                   title: lang.localized(rider ? "roles.switch.rider" : "roles.switch.me"),
                   alert: coordinator.activeSOSEvent != nil, onShift: false)
        case .family:
            button(.family, icon: "person.2.fill",
                   title: lang.localized("roles.switch.family") + (coordinator.protectedPersons.isEmpty ? "" : " · \(coordinator.protectedPersons.count)"),
                   alert: familyAlert, onShift: false)
        }
    }

    private func button(_ side: HomeSide, icon: String, title: String, alert: Bool, onShift: Bool) -> some View {
        let selected = coordinator.currentHomeSide == side
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { coordinator.switchHome(to: side) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.scaled(size: 12, weight: .semibold))
                Text(title).font(.scaled(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                if alert {
                    // Someone's SOS on that side: visible from the other side too
                    Circle().fill(Color(red: 0.79, green: 0.42, blue: 0.38)).frame(width: 7, height: 7)
                        .accessibilityLabel(lang.localized("roles.switch.sos"))
                } else if onShift {
                    // A shift is running
                    Circle().fill(Color(red: 0.25, green: 0.56, blue: 0.43)).frame(width: 7, height: 7)
                        .accessibilityLabel(lang.localized("roles.switch.onShift"))
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Capsule().fill(selected ? Color(.systemBackground) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("home.side.\(side.rawValue)")
    }
}

/// Settings (looked after): ride or drive for work as well — a "Work" side on the home.
/// Not shown to a pure rider (Home screen → Rider already is the work home).
struct WorkRoleSettingsRow: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        if coordinator.isProtectedSide && coordinator.familyHomeStyle != HomeStyle.rider.rawValue {
            SettingsDivider()
            SettingsToggleRow(icon: "bicycle", tint: SettingsTint.safe,
                              title: lang.localized("settings.workRole"),
                              subtitle: lang.localized("settings.workRole.desc"),
                              isOn: Binding(
                get: { coordinator.hasWorkRole },
                set: { on in
                    coordinator.setWorkRole(on)
                    // First time: where you ride, crew, the rider notice
                    if on && !coordinator.riderSetupDone { coordinator.beginRiderSetup(at: .ride) }
                }
            ))
            .accessibilityIdentifier("settings.workRole")
        }
    }
}

/// Settings (both sides): turn the home's side switch on or off. Off keeps the side on
/// screen, after saying what stops if that's the family side.
struct BothRolesSettingsRow: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var confirmOff = false

    var body: some View {
        SettingsToggleRow(icon: "arrow.left.arrow.right", tint: SettingsTint.safe,
                          title: lang.localized("settings.bothRoles"),
                          subtitle: lang.localized("settings.bothRoles.desc"),
                          isOn: Binding(
            get: { coordinator.hasBothRoles },
            set: { on in if on { coordinator.setBothRoles(true) } else { confirmOff = true } }
        ))
        .accessibilityIdentifier("settings.bothRoles")
        .alert(lang.localized("settings.bothRoles"), isPresented: $confirmOff) {
            Button(lang.localized("settings.bothRoles.offConfirm"), role: .destructive) {
                coordinator.setBothRoles(false)
            }
            Button(lang.localized("settings.action.cancel"), role: .cancel) {}
        } message: {
            Text(lang.localized("settings.bothRoles.offWarning"))
        }
    }
}
