import SwiftUI

// MARK: - How to use: the guide list
//
// Opened from the "?" / "How to use" button on every home (protected, guardian,
// rider). Built to work in a hurry:
//  - the top is an emergency strip with the real actions (hold for SOS, call family,
//    call the local emergency number, open an incoming alert), no reading needed;
//  - under it the guides for emergencies, as large tiles;
//  - a search box that matches titles, steps and everyday words ("hospital", "fall");
//  - the other guides grouped by situation.
// A guide plays by itself on open (TutorialGuideView) and ends with "Do it now".

struct TutorialCenterView: View {
    let role: TutorialRole
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var path: [String] = []

    private var guides: [TutorialGuide] { TutorialCatalog.guides(for: role) }
    private var results: [TutorialGuide] { guides.filter { $0.matches(query) } }
    private var tint: Color { role == .guardian ? SettingsTint.pro : SettingsTint.safe }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if query.isEmpty {
                        TutorialEmergencyStrip(role: role, close: dismiss)
                        urgentGuides
                        ForEach(TutorialCategory.allCases.filter { $0 != .emergency }, id: \.self) { cat in
                            guideList(lang.localized(cat.titleKey), guides.filter { $0.category == cat })
                        }
                    } else if results.isEmpty {
                        noResults
                    } else {
                        guideList(String(format: lang.localized("tut.search.count"), results.count), results)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: lang.localized("tut.search.prompt"))
            .navigationTitle(lang.localized("tut.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.localized("common.done")) { dismiss() }
                        .accessibilityIdentifier("tutorial.close")
                }
            }
            .navigationDestination(for: String.self) { id in
                if let guide = TutorialCatalog.guide(id) {
                    TutorialGuideView(guide: guide, role: role, closeCenter: dismiss)
                }
            }
        }
        .tint(tint)
        .onAppear {
            TutorialContext.emergencyNumber = coordinator.localEmergencyNumber
            TutorialContext.policeNumber = coordinator.localPoliceNumber
        }
    }

    /// Emergency guides as big tiles: one tap plays the guide
    private var urgentGuides: some View {
        let list = guides.filter { $0.category == .emergency }
        return VStack(alignment: .leading, spacing: 8) {
            Text(lang.localized("tut.cat.emergency"))
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(list) { g in
                    Button { path.append(g.id) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: g.icon)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(g.tint)
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(g.tint.opacity(0.8))
                            }
                            Text(lang.localized(g.titleKey))
                                .font(.scaled(size: 16, weight: .bold))
                                .foregroundStyle(Color.appInk)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(g.tint.opacity(0.35), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(lang.localized("tut.play.hint"))
                    .accessibilityIdentifier("tutorial.guide.\(g.id)")
                }
            }
        }
    }

    @ViewBuilder private func guideList(_ title: String, _ list: [TutorialGuide]) -> some View {
        if !list.isEmpty {
            SettingsSection(title) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, g in
                    if i > 0 { SettingsDivider() }
                    guideRow(g)
                }
            }
        }
    }

    private func guideRow(_ g: TutorialGuide) -> some View {
        Button { path.append(g.id) } label: {
            SettingsRow(icon: g.icon, tint: g.tint, title: lang.localized(g.titleKey),
                        subtitle: lang.localized(g.summaryKey),
                        value: String(format: lang.localized("tut.length"), g.steps.count))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tutorial.guide.\(g.id)")
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundStyle(.secondary)
            Text(String(format: lang.localized("tut.search.none"), query))
                .font(.scaled(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TutorialEmergencyStrip(role: role, close: dismiss)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

// MARK: - Emergency strip

/// The real emergency actions, first thing on the page and after a search that found
/// nothing: hold for SOS, call family, call the local emergency number, and for a
/// guardian the alert that is waiting.
struct TutorialEmergencyStrip: View {
    let role: TutorialRole
    let close: DismissAction
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    private var familyToCall: Guardian? {
        coordinator.myGuardians.first(where: { $0.isOnDuty && !($0.user.phone ?? "").isEmpty })
            ?? coordinator.myGuardians.first(where: { !($0.user.phone ?? "").isEmpty })
    }

    /// Guardian: people with an SOS going on, by name
    private var alerts: [(id: String, name: String)] {
        coordinator.guardianSOS.keys.sorted().map { id in
            (id, coordinator.protectedPersons.first { $0.id == id }?.user.displayName ?? lang.localized("tut.someone"))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(lang.localized("tut.now.title"), systemImage: "light.beacon.max.fill")
                .font(.scaled(size: 17, weight: .bold))
                .foregroundStyle(SettingsTint.sos)
            ForEach(alerts, id: \.id) { a in
                bigAction(icon: "exclamationmark.triangle.fill", title: String(format: lang.localized("tut.now.openAlert"), a.name),
                          color: SettingsTint.sos, filled: true) {
                    after { coordinator.pendingAlertPersonId = a.id }
                }
            }
            HStack(alignment: .center, spacing: 14) {
                TutorialSOSHold { after { coordinator.requestSOS(method: .longPress) } }
                VStack(spacing: 10) {
                    if role != .guardian, let g = familyToCall, let phone = g.user.phone {
                        bigAction(icon: "phone.fill", title: String(format: lang.localized("simple.call"), g.user.displayName),
                                  color: SettingsTint.blue, filled: false) { call(phone) }
                    }
                    bigAction(icon: "staroflife.fill",
                              title: String(format: lang.localized("tut.now.callLocal"), coordinator.localEmergencyNumber),
                              color: SettingsTint.sos, filled: false) { call(coordinator.localEmergencyNumber) }
                    if role == .rider {
                        bigAction(icon: "car.side.rear.and.collision.and.car.side.front", title: lang.localized("rider.crash.title"),
                                  color: SettingsTint.amber, filled: false) {
                            after { coordinator.showCrashReport = true }
                        }
                    }
                }
            }
            Text(lang.localized("tut.now.hint"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SettingsTint.sos.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(SettingsTint.sos.opacity(0.3), lineWidth: 1.5))
    }

    private func bigAction(icon: String, title: String, color: Color, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.scaled(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(filled ? .white : color)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(filled ? color : color.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func call(_ number: String) {
        let digits = number.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel:\(digits)") { ExternalURL.open(url) }
    }

    /// Close the guides first, then act: the home presents the SOS screen / alert
    /// itself and can't while this sheet is up
    private func after(_ action: @escaping () -> Void) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action)
    }
}

/// The real hold-for-SOS control, small: same hold time and haptics as the home button
struct TutorialSOSHold: View {
    var diameter: CGFloat = 118
    let send: () -> Void
    @ObservedObject private var lang = LanguageManager.shared
    @State private var progress: Double = 0
    @State private var pressing = false

    var body: some View {
        let k = diameter / 118
        ZStack {
            Circle().fill(SettingsTint.sos.opacity(0.18)).frame(width: diameter, height: diameter)
            Circle().trim(from: 0, to: progress)
                .stroke(SettingsTint.sos, style: StrokeStyle(lineWidth: 6 * k, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 110 * k, height: 110 * k)
            Circle().fill(SettingsTint.sos).frame(width: 96 * k, height: 96 * k)
                .overlay(VStack(spacing: 1) {
                    Text("SOS").font(.system(size: 26 * k, weight: .black))
                    Text(lang.localized("simple.sosHold"))
                        .font(.system(size: 10 * max(k, 0.9), weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 8 * k)
                }.foregroundStyle(.white))
                .scaleEffect(pressing ? 0.95 : 1)
        }
        .contentShape(Circle())
        .sosHold(duration: FloatingSOSButton.holdDuration, pressing: { isPressing in
            pressing = isPressing
            if isPressing {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.linear(duration: FloatingSOSButton.holdDuration)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }, perform: {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            progress = 0
            send()
        })
        .accessibilityLabel(lang.localized("sos.button.a11yLabel"))
        .accessibilityHint(lang.localized("sos.button.a11yHint"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("tutorial.sosHold")
    }
}

// MARK: - One guide

struct TutorialGuideView: View {
    let guide: TutorialGuide
    let role: TutorialRole
    let closeCenter: DismissAction
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @StateObject private var player: TutorialPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var sheet: TutorialAction?
    @State private var doneNote: String?

    init(guide: TutorialGuide, role: TutorialRole, closeCenter: DismissAction) {
        self.guide = guide
        self.role = role
        self.closeCenter = closeCenter
        _player = StateObject(wrappedValue: TutorialPlayer(guide: guide))
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 24) {
                    TutorialPhone(player: player).frame(maxWidth: 360)
                    ScrollView { steps.padding(.vertical, 8) }
                }
                .padding(20)
            } else {
                VStack(spacing: 0) {
                    TutorialPhone(player: player)
                        .frame(height: 330)
                        .padding(.top, 8)
                    controls
                    ScrollViewReader { proxy in
                        ScrollView {
                            steps.padding(.horizontal, 16).padding(.bottom, 12)
                        }
                        .onChange(of: player.step) { _, s in
                            withAnimation { proxy.scrollTo(s, anchor: .center) }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(lang.localized(guide.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            player.reduceMotion = reduceMotion
            player.play(from: 0)
        }
        .onDisappear { player.stop() }
        .sheet(item: $sheet) { action in
            TutorialActionSheet(action: action).environmentObject(coordinator)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button { player.play(from: max(0, player.step - 1)) } label: {
                Image(systemName: "backward.fill")
            }
            .accessibilityLabel(lang.localized("tut.prev"))
            Button { player.playing ? player.pause() : player.play() } label: {
                Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 34))
            }
            .accessibilityLabel(lang.localized(player.playing ? "tut.pause" : "tut.play"))
            .accessibilityIdentifier("tutorial.playPause")
            Button { player.play(from: min(guide.steps.count - 1, player.step + 1)) } label: {
                Image(systemName: "forward.fill")
            }
            .accessibilityLabel(lang.localized("tut.next"))
            Spacer()
            Button { player.speaks.toggle() } label: {
                Label(lang.localized("tut.readAloud"), systemImage: player.speaks ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.scaled(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tutorial.readAloud")
        }
        .font(.system(size: 18))
        .foregroundStyle(guide.tint)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.localized(guide.summaryKey))
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                Button { player.play(from: i) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(i == player.step ? guide.tint : Color(.tertiarySystemFill)).frame(width: 30, height: 30)
                            if player.seen.contains(i) && i != player.step {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(guide.tint)
                            } else {
                                Text("\(i + 1)").font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(i == player.step ? .white : .secondary)
                            }
                        }
                        Text(lang.localized(step.caption))
                            .font(.scaled(size: 17, weight: i == player.step ? .semibold : .regular))
                            .foregroundStyle(i == player.step ? Color.appInk : .secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(i == player.step ? guide.tint.opacity(0.1) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(i)
                .accessibilityLabel(String(format: lang.localized("tut.step.a11y"), i + 1, lang.localized(step.caption)))
            }
        }
    }

    @ViewBuilder private var actionBar: some View {
        if let action = guide.action {
            VStack(spacing: 8) {
                if let doneNote {
                    Label(doneNote, systemImage: "checkmark.circle.fill")
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsTint.safe)
                        .transition(.opacity)
                }
                if action == .sos {
                    HStack(spacing: 14) {
                        TutorialSOSHold(diameter: 92) {
                            closeCenter()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { coordinator.requestSOS(method: .longPress) }
                        }
                        Text(lang.localized("tut.doIt.sos"))
                            .font(.scaled(size: 15, weight: .semibold))
                            .foregroundStyle(SettingsTint.sos)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                } else {
                    Button { run(action) } label: {
                        Text(lang.localized(Self.actionTitleKey(action)))
                            .font(.scaled(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(guide.tint)
                    .accessibilityIdentifier("tutorial.doIt")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    static func actionTitleKey(_ action: TutorialAction) -> String {
        switch action {
        case .checkIn: return "tut.doIt.checkIn"
        case .homeSafe: return "tut.doIt.home"
        default: return "tut.doIt"
        }
    }

    private func run(_ action: TutorialAction) {
        switch action {
        case .sos: break
        case .checkIn:
            coordinator.performCheckIn()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { doneNote = lang.localized("simple.checkedIn") }
        case .homeSafe:
            coordinator.performCheckIn(note: lang.localized("widget.arrived.note"))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { doneNote = lang.localized("simple.homeSent") }
        case .joinWithCode:
            closeThen { coordinator.showInviteAccept = true }
        case .crashReport:
            closeThen { coordinator.showCrashReport = true }
        case .bikeReport:
            closeThen { coordinator.showBikeReport = true }
        default:
            sheet = action
        }
    }

    private func closeThen(_ action: @escaping () -> Void) {
        closeCenter()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action)
    }
}

extension TutorialAction: Identifiable {
    var id: String { "\(self)" }
}

/// The real screen a guide's "Do it now" opens
private struct TutorialActionSheet: View {
    let action: TutorialAction
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch action {
        case .inviteGuardian: InviteGuardianSheet(inviterRole: .protected_)
        case .invitePerson: InviteGuardianView()
        case .medicalCard: MedicalCardView()
        case .fakeCall: FakeCallSettingsView()
        case .duressCode: DuressCodeSettingsView()
        case .startShift: ShiftStartSheet()
        case .crew: CrewJoinSheet(initialCode: "")
        case .handsFree: HandsFreeSheet()
        case .lockScreenCard: wrapped { LockScreenCardSettingsView() }
        case .emergencyNumbers: wrapped { EmergencyYellowPagesView(country: coordinator.emergencyCountryCode) }
        case .dutySchedule: wrapped { GuardianDutyScheduleView() }
        case .textSize:
            wrapped {
                ScrollView {
                    SettingsDisplaySection(tint: SettingsTint.blue).padding(16)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(lang.localized("settings.section.display"))
            }
        default: EmptyView()
        }
    }

    private func wrapped<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        NavigationStack {
            content()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(lang.localized("common.done")) { dismiss() }
                    }
                }
        }
    }
}

// MARK: - The button on each home

/// "How to use" on the homes. `.icon` for a toolbar, `.label` for the simple home
/// (a larger capsule with text), `.row` for Settings → About.
struct TutorialHelpButton: View {
    enum Style { case icon, label, row }
    let role: TutorialRole
    var style: Style = .icon
    var tint: Color = SettingsTint.safe
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            switch style {
            case .icon:
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(minWidth: 32, minHeight: 32)
            case .label:
                Label(lang.localized("tut.button"), systemImage: "questionmark.circle.fill")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(tint.opacity(0.12)))
            case .row:
                SettingsRow(icon: "questionmark.circle.fill", tint: SettingsTint.blue,
                            title: lang.localized("tut.button"), subtitle: lang.localized("tut.row.subtitle"))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.localized("tut.button"))
        .accessibilityIdentifier("home.tutorial")
        .sheet(isPresented: $open) {
            TutorialCenterView(role: role).environmentObject(coordinator)
        }
    }
}
