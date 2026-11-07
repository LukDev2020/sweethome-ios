import SwiftUI
import ActivityKit
import CoreLocation
import CoreMotion
import UserNotifications

// MARK: - Rider setup (docs/rider-onboarding-plan.md §2)
//
// One job per screen, one big button, "Later" on everything but the rider notice:
//   where you ride → your crew → someone at home → SOS without looking →
//   permissions → plan & rider notice → ready (first shift)
// Shown after a rider signs up, from a crew / partner link, from Settings → Home
// screen → Rider, and from the rider home's "Finish setting up" card.

struct RiderSetupView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var step: RiderSetupStep
    // Where you ride
    @State private var city = ""
    @State private var platforms: Set<String> = []
    @State private var partnerName: String?
    @State private var shareWithPartner = false
    // Crew
    @State private var crewCode = ""
    @State private var crewName = ""
    @State private var crewError: String?
    @State private var crewBusy = false
    @State private var showCrewInvite = false
    // Someone at home
    @State private var showGuardianInvite = false
    // SOS without looking
    @AppStorage("lockscreen_card_enabled") private var lockCardOn = true
    @State private var showHandsFree = false
    // Permissions
    @State private var locationStatus = CLLocationManager().authorizationStatus
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var motionStatus = CMMotionActivityManager.authorizationStatus()
    // Plan & notice
    @AppStorage("rider_duty_version") private var dutyVersion = ""
    // Ready
    @State private var showShiftStart = false

    init(start: RiderSetupStep = .ride) {
        _step = State(initialValue: start)
    }

    private var dutyAgreed: Bool { dutyVersion == DisclaimerCopy.RiderDuty.version }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .background(Color(.systemBackground))
        // The button bar stays at the bottom behind the keyboard: floating up, it covered
        // the crew step's "Start crew" (a tap there pressed Next instead)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear(perform: prefill)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshPermissions() } }
        .sheet(isPresented: $showCrewInvite) {
            if let crew = coordinator.crew { CrewInviteSheet(crew: crew) }
        }
        .sheet(isPresented: $showGuardianInvite, onDismiss: { Task { await coordinator.fetchGuardians() } }) {
            InviteGuardianSheet().environmentObject(coordinator)
        }
        .sheet(isPresented: $showHandsFree) { HandsFreeSheet() }
        .sheet(isPresented: $showShiftStart, onDismiss: { if coordinator.isOnShift { coordinator.finishRiderSetup() } }) {
            ShiftStartSheet().environmentObject(coordinator)
        }
    }

    // MARK: Header / bottom

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(RiderSetupStep.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? RC.safe : Color(.separator).opacity(0.5))
                        .frame(height: 4)
                }
            }
            HStack {
                Label(lang.localized("rider.title"), systemImage: "bicycle")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(RC.safe)
                Spacer()
                Text(String(format: lang.localized("rider.setup.progress"), step.rawValue + 1, RiderSetupStep.allCases.count))
                    .font(.scaled(size: 13))
                    .foregroundStyle(.secondary)
            }
            Text(lang.localized("rider.setup.\(key(step)).title"))
                .font(.scaled(size: 26, weight: .bold))
                .foregroundStyle(RC.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(lang.localized("rider.setup.\(key(step)).why"))
                .font(.scaled(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func key(_ s: RiderSetupStep) -> String {
        switch s {
        case .ride: return "ride"
        case .crew: return "crew"
        case .home: return "home"
        case .sos: return "sos"
        case .permissions: return "permissions"
        case .plan: return "plan"
        case .ready: return "ready"
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if step == .ready {
                primaryButton(lang.localized("rider.setup.ready.start"), icon: "play.fill") { showShiftStart = true }
                    .accessibilityIdentifier("rider.setup.startShift")
                Button(lang.localized("rider.setup.ready.notNow")) { coordinator.finishRiderSetup() }
                    .font(.scaled(size: 15, weight: .medium))
                    .foregroundStyle(RC.ink)
                    .accessibilityIdentifier("rider.setup.notNow")
            } else {
                primaryButton(lang.localized(step == .plan && !dutyAgreed ? "rider.setup.agreeFirst" : "rider.setup.next"),
                              icon: nil, disabled: step == .plan && !dutyAgreed) { Task { await next() } }
                    .accessibilityIdentifier("rider.setup.next")
                HStack {
                    if step != .ride {
                        Button(lang.localized("rider.setup.back")) { withAnimation { step = RiderSetupStep(rawValue: step.rawValue - 1) ?? .ride } }
                    }
                    Spacer()
                    if step != .plan {
                        Button(lang.localized("rider.setup.later")) { withAnimation { advance() } }
                            .accessibilityIdentifier("rider.setup.later")
                    }
                }
                .font(.scaled(size: 15))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private func primaryButton(_ title: String, icon: String?, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.scaled(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 14).fill(disabled ? Color.gray.opacity(0.5) : RC.safe))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func advance() {
        if let nextStep = RiderSetupStep(rawValue: step.rawValue + 1) { step = nextStep }
    }

    private func next() async {
        if step == .ride { await saveRide() }
        withAnimation { advance() }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch step {
        case .ride: rideStep
        case .crew: crewStep
        case .home: homeStep
        case .sos: sosStep
        case .permissions: permissionsStep
        case .plan: planStep
        case .ready: readyStep
        }
    }

    // 1 — Where do you ride?
    private var rideStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(lang.localized("rider.setup.ride.city"), text: $city)
                .font(.scaled(size: 17))
                .textContentType(.addressCity)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))
            Text(lang.localized("rider.setup.ride.platforms"))
                .font(.scaled(size: 14, weight: .semibold))
            FlowChips(items: RiderPlatforms.forCountry(coordinator.currentUser?.countryCode ?? ""),
                      label: RiderPlatforms.name, selected: $platforms)
            if let partnerName {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(format: lang.localized("rider.setup.partner.joined"), partnerName), systemImage: "building.2")
                        .font(.scaled(size: 15, weight: .semibold))
                    Toggle(isOn: $shareWithPartner) {
                        Text(String(format: lang.localized("rider.setup.partner.share"), partnerName))
                            .font(.scaled(size: 14))
                    }
                    .tint(RC.safe)
                    Text(lang.localized("rider.setup.partner.shareNote"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            }
        }
    }

    // 2 — Your crew
    private var crewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let crew = coordinator.crew {
                doneRow(String(format: lang.localized("rider.setup.crew.in"), crew.name, crew.members.count))
                secondaryButton(lang.localized("rider.setup.crew.invite"), icon: "qrcode") { showCrewInvite = true }
            } else if let code = coordinator.pendingCrewCode {
                card {
                    Text(lang.localized("rider.setup.crew.invited")).font(.scaled(size: 15))
                    Text(code).font(.system(size: 30, weight: .bold, design: .monospaced)).kerning(4)
                    primaryButton(lang.localized("rider.crew.joinButton"), icon: "person.3.fill", disabled: crewBusy) {
                        Task { await joinCrew(code) }
                    }
                }
            } else {
                card {
                    Text(lang.localized("rider.setup.crew.joinTitle")).font(.scaled(size: 15, weight: .semibold))
                    TextField(lang.localized("rider.setup.crew.code"), text: $crewCode)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator)))
                        .onChange(of: crewCode) { _, v in
                            let cleaned = String(v.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(6))
                            if cleaned != v { crewCode = cleaned }
                        }
                    secondaryButton(lang.localized("rider.crew.joinButton"), icon: nil) { Task { await joinCrew(crewCode) } }
                        .disabled(crewCode.count != 6 || crewBusy)
                }
                card {
                    Text(lang.localized("rider.setup.crew.startTitle")).font(.scaled(size: 15, weight: .semibold))
                    TextField(lang.localized("rider.setup.crew.name"), text: $crewName)
                        .font(.scaled(size: 17))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator)))
                    secondaryButton(lang.localized("rider.setup.crew.start"), icon: nil) { Task { await createCrew() } }
                        .disabled(crewName.trimmingCharacters(in: .whitespaces).isEmpty || crewBusy)
                }
            }
            if let crewError { Text(crewError).font(.scaled(size: 13)).foregroundStyle(RC.alert) }
        }
    }

    // 3 — Someone at home
    private var homeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if coordinator.myGuardians.isEmpty {
                Label(lang.localized("rider.setup.home.none"), systemImage: "person.crop.circle.badge.questionmark")
                    .font(.scaled(size: 15))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.myGuardians) { g in doneRow(g.user.displayName) }
            }
            primaryButton(lang.localized(coordinator.myGuardians.isEmpty ? "rider.setup.home.invite" : "rider.setup.home.inviteMore"),
                          icon: "person.badge.plus") { showGuardianInvite = true }
            Text(lang.localized("rider.setup.home.rule"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await coordinator.fetchGuardians() }
    }

    // 4 — SOS without looking
    private var sosStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            card {
                Toggle(isOn: $lockCardOn) {
                    Label(lang.localized("rider.setup.sos.lockCard"), systemImage: "lock.rectangle.stack.fill")
                        .font(.scaled(size: 16, weight: .semibold))
                }
                .tint(RC.safe)
                .onChange(of: lockCardOn) { _, on in
                    if on {
                        coordinator.startLiveActivityIfNeeded()
                        coordinator.saveRiderProfile(.init(riderProfile: .init(milestones: ["lockCard": true])))
                    } else {
                        coordinator.liveActivityManager.endAllActivities()
                    }
                }
                Text(lang.localized("rider.setup.sos.lockCardWhy"))
                    .font(.scaled(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if lockCardOn && !ActivityAuthorizationInfo().areActivitiesEnabled {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { ExternalURL.open(url) }
                    } label: {
                        Label(lang.localized("lsc.disabledInSettings"), systemImage: "exclamationmark.triangle.fill")
                            .font(.scaled(size: 13)).foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            secondaryButton(lang.localized("rider.setup.sos.more"), icon: "hand.tap") { showHandsFree = true }
        }
        .onAppear {
            // The card is on by default: count it as set up when it can show
            if lockCardOn && ActivityAuthorizationInfo().areActivitiesEnabled {
                coordinator.saveRiderProfile(.init(riderProfile: .init(milestones: ["lockCard": true])))
            }
        }
    }

    // 5 — Permissions, in rider words
    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            permissionRow(icon: "location.fill", key: "location",
                          granted: locationStatus == .authorizedAlways,
                          partial: locationStatus == .authorizedWhenInUse) {
                coordinator.locationManager.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { refreshPermissions() }
            }
            permissionRow(icon: "bell.badge.fill", key: "notifications",
                          granted: notificationStatus == .authorized || notificationStatus == .provisional,
                          partial: false) {
                coordinator.pushService.registerForPushNotifications()
                UIApplication.shared.registerForRemoteNotifications()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { refreshPermissions() }
            }
            permissionRow(icon: "figure.fall", key: "motion",
                          granted: motionStatus == .authorized, partial: false) {
                CMMotionActivityManager().queryActivityStarting(from: Date().addingTimeInterval(-60), to: Date(), to: .main) { _, _ in
                    refreshPermissions()
                }
            }
        }
        .onAppear(perform: refreshPermissions)
    }

    private func permissionRow(icon: String, key: String, granted: Bool, partial: Bool, ask: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(RC.safe).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(lang.localized("rider.setup.perm.\(key)")).font(.scaled(size: 16, weight: .semibold))
                Text(lang.localized("rider.setup.perm.\(key).why")).font(.scaled(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if partial {
                    Text(lang.localized("rider.setup.perm.location.always")).font(.scaled(size: 12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(RC.safe)
            } else {
                Button(lang.localized(partial ? "rider.setup.perm.settings" : "rider.setup.perm.allow")) {
                    // The demo never asks for real permissions
                    if ExploreMode.blocks("permissions") { return }
                    if partial, let url = URL(string: UIApplication.openSettingsURLString) { ExternalURL.open(url) } else { ask() }
                }
                .font(.scaled(size: 14, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(RC.safe)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func refreshPermissions() {
        locationStatus = CLLocationManager().authorizationStatus
        motionStatus = CMMotionActivityManager.authorizationStatus()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { notificationStatus = settings.authorizationStatus }
        }
    }

    // 6 — Plan and the rider notice
    private var planStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            card {
                Label(lang.localized("rider.setup.plan.free"), systemImage: "gift.fill")
                    .font(.scaled(size: 17, weight: .bold)).foregroundStyle(RC.safe)
                ForEach(["crew", "shifts", "sos", "lockCard", "family"], id: \.self) { item in
                    Label(lang.localized("rider.setup.plan.item.\(item)"), systemImage: "checkmark")
                        .font(.scaled(size: 14))
                }
                Text(lang.localized("rider.setup.plan.more"))
                    .font(.scaled(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(lang.localized("rider.duty.title"), systemImage: "exclamationmark.shield.fill")
                    .font(.scaled(size: 16, weight: .bold)).foregroundStyle(RC.alert)
                ForEach(["volunteers", "emergency", "phone"], id: \.self) { p in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(String(format: lang.localized("rider.duty.\(p)"), coordinator.localEmergencyNumber))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.scaled(size: 14))
                }
                Button {
                    if !dutyAgreed {
                        ConsentLogger.shared.logRiderDuty()
                        dutyVersion = DisclaimerCopy.RiderDuty.version
                    }
                } label: {
                    Label(lang.localized("rider.duty.agree"), systemImage: dutyAgreed ? "checkmark.square.fill" : "square")
                        .font(.scaled(size: 15, weight: .semibold))
                        .foregroundStyle(dutyAgreed ? RC.safe : RC.ink)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rider.duty.agree")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).stroke(RC.alert.opacity(0.4)))
        }
    }

    // 7 — Ready
    private var readyStep: some View {
        let c = coordinator.riderChecklist
        return VStack(alignment: .leading, spacing: 10) {
            checkRow(done: c.crew, key: "crew") { step = .crew }
            checkRow(done: c.watcher, key: "watcher") { step = .home }
            checkRow(done: c.lockCard, key: "lockCard") { step = .sos }
            if !c.essentialsDone {
                Text(lang.localized("rider.setup.ready.partial"))
                    .font(.scaled(size: 13)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func checkRow(done: Bool, key: String, fix: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(done ? RC.safe : Color(.separator))
            Text(lang.localized("rider.setup.check.\(key)")).font(.scaled(size: 16))
            Spacer()
            if !done {
                Button(lang.localized("rider.setup.check.fix")) { withAnimation { fix() } }
                    .font(.scaled(size: 14, weight: .semibold))
                    .foregroundStyle(RC.safe)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    // MARK: Pieces

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func doneRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.scaled(size: 16, weight: .semibold))
            .foregroundStyle(RC.safe)
    }

    private func secondaryButton(_ title: String, icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.scaled(size: 16, weight: .semibold))
            .foregroundStyle(RC.safe)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 12).stroke(RC.safe.opacity(0.6)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func prefill() {
        city = coordinator.riderProfile?.city ?? coordinator.currentUser?.cityName ?? ""
        platforms = Set(coordinator.riderProfile?.platforms ?? [])
        refreshPermissions()
        Task {
            await coordinator.refreshCrew()
            if let code = coordinator.pendingSignupIntent?.partnerCode {
                partnerName = await coordinator.previewPartner(code: code)
            }
        }
    }

    private func saveRide() async {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        coordinator.saveRiderProfile(.init(useCase: "rider", homeStyle: HomeStyle.rider.rawValue,
                                           riderProfile: .init(city: trimmed.isEmpty ? nil : trimmed,
                                                               platforms: RiderPlatforms.all.filter(platforms.contains))))
        if let code = coordinator.pendingSignupIntent?.partnerCode, partnerName != nil {
            _ = await coordinator.joinPartner(code: code, shareStats: shareWithPartner)
            coordinator.pendingSignupIntent?.partnerCode = nil
        }
    }

    private func joinCrew(_ code: String) async {
        crewBusy = true
        crewError = nil
        do {
            try await coordinator.joinCrew(code: code)
            coordinator.pendingCrewCode = nil
        } catch {
            crewError = lang.localized("rider.crew.badCode")
        }
        crewBusy = false
    }

    private func createCrew() async {
        crewBusy = true
        crewError = nil
        do {
            try await coordinator.createCrew(name: crewName.trimmingCharacters(in: .whitespaces))
            showCrewInvite = coordinator.crew != nil
        } catch {
            crewError = lang.localized("rider.setup.crew.failed")
        }
        crewBusy = false
    }
}

/// Wrapping chips, multi-select.
struct FlowChips: View {
    let items: [String]
    let label: (String) -> String
    @Binding var selected: Set<String>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { id in
                let on = selected.contains(id)
                Button {
                    if on { selected.remove(id) } else { selected.insert(id) }
                } label: {
                    Text(label(id))
                        .font(.scaled(size: 15, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? .white : RC.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(on ? RC.safe : Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// On-device suggestion (no data leaves the phone): long cycling stretches on several
/// days this week → "Riding for work?". "Not for me" hides it for good.
struct RiderSuggestionCard: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(lang.localized("rider.suggest.title"), systemImage: "bicycle")
                .font(.scaled(size: 16, weight: .bold))
                .foregroundStyle(RC.ink)
            Text(lang.localized("rider.suggest.body"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(lang.localized("rider.suggest.yes")) {
                    coordinator.showRiderSuggestion = false
                    coordinator.beginRiderSetup(at: .ride)
                }
                .buttonStyle(.borderedProminent)
                .tint(RC.safe)
                Button(lang.localized("rider.suggest.no")) { coordinator.dismissRiderSuggestion() }
                    .buttonStyle(.bordered)
            }
            .font(.scaled(size: 14, weight: .semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(RC.safe.opacity(0.08)))
    }
}
