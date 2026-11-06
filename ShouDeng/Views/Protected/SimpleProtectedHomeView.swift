import SwiftUI

// MARK: - Home style (protected person)
//
// "Standard" is the full home (map, trips, tools, 5 tabs). "Simple" is for older
// users: large type, four things only — I'm OK, I'm home, call my family, SOS — and
// 3 tabs. Chosen in Settings (and suggested when the text size is set to extra large);
// both use the same data and the same SOS.

enum HomeStyle: String, CaseIterable {
    case standard, simple
    static let storageKey = "protected_home_style"
}

struct SimpleProtectedHomeView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage(HomeStyle.storageKey) private var homeStyle = HomeStyle.standard.rawValue
    @State private var checkedIn = false
    @State private var homeConfirmed = false
    @State private var showInvite = false

    private let ink = Color.appInk
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let teal = Color(red: 47/255, green: 111/255, blue: 143/255)
    private let indigo = Color(red: 74/255, green: 93/255, blue: 138/255)
    private let cream = Color.paper(251, 248, 241)

    /// 陈秀兰 → 秀兰; "Margaret Chen" → Margaret
    private var givenName: String {
        let name = (coordinator.currentUser?.displayName ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "" }
        let initial = AvatarInitial.make(for: name)
        return initial.count > 1 || initial == name ? initial : (name.split(separator: " ").first.map(String.init) ?? name)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let key = hour < 12 ? "simple.greeting.morning" : hour < 18 ? "simple.greeting.afternoon" : "simple.greeting.evening"
        return givenName.isEmpty ? lang.localized(key + ".plain") : String(format: lang.localized(key), givenName)
    }

    private var caller: Guardian? {
        coordinator.myGuardians.first(where: { $0.isOnDuty && !($0.user.phone ?? "").isEmpty })
            ?? coordinator.myGuardians.first(where: { !($0.user.phone ?? "").isEmpty })
    }

    private var watcher: Guardian? {
        coordinator.myGuardians.first(where: \.isOnDuty) ?? coordinator.myGuardians.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(greeting)
                        .font(.scaled(size: 30, weight: .bold))
                        .foregroundStyle(ink)
                    if let watcher {
                        HStack(spacing: 8) {
                            Circle().fill(safe).frame(width: 12, height: 12)
                            Text(String(format: lang.localized("simple.watching"), watcher.user.displayName))
                                .font(.scaled(size: 19))
                        }
                        .coachMark(CoachAnchor.guardiansGlobe)
                    } else {
                        Button { showInvite = true } label: {
                            Label(lang.localized("simple.noGuardian"), systemImage: "person.badge.plus")
                                .font(.scaled(size: 18, weight: .semibold))
                                .foregroundStyle(teal)
                        }
                    }
                    if let last = WidgetDataStore.read().lastCheckInDate {
                        Text(String(format: lang.localized("simple.lastCheckIn"),
                                    last.formatted(.dateTime.hour().minute().locale(Locale(identifier: lang.current.rawValue)))))
                            .font(.scaled(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 12)

                bigButton(icon: checkedIn ? "checkmark.circle.fill" : "checkmark.circle",
                          title: lang.localized(checkedIn ? "simple.checkedIn" : "simple.checkIn"), color: safe) {
                    coordinator.performCheckIn()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation { checkedIn = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { checkedIn = false } }
                }
                bigButton(icon: "house.fill", title: lang.localized(homeConfirmed ? "simple.homeSent" : "simple.home"), color: teal) {
                    coordinator.performCheckIn(note: lang.localized("widget.arrived.note"))
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation { homeConfirmed = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { homeConfirmed = false } }
                }
                .coachMark(CoachAnchor.homeSafe)
                if let caller, let phone = caller.user.phone {
                    bigButton(icon: "phone.fill", title: String(format: lang.localized("simple.call"), caller.user.displayName), color: indigo) {
                        let digits = phone.filter { $0.isNumber || $0 == "+" }
                        if let url = URL(string: "tel:\(digits)") { ExternalURL.open(url) }
                    }
                }

                BigSOSButton()
                    .coachMark(CoachAnchor.sosButton)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                Button {
                    homeStyle = HomeStyle.standard.rawValue
                } label: {
                    Text(lang.localized("simple.switchToStandard"))
                        .font(.scaled(size: 15))
                        .foregroundStyle(.secondary)
                        .underline()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 18)
        }
        .background(cream)
        .sheet(isPresented: $showInvite) {
            InviteGuardianSheet().environmentObject(coordinator)
        }
    }

    private func bigButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 30, weight: .semibold))
                Text(title).font(.scaled(size: 22, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(RoundedRectangle(cornerRadius: 20).fill(color))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Large SOS button (simple home)

/// Same 5-second hold as the floating button, drawn large.
struct BigSOSButton: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var progress: Double = 0
    @State private var pressing = false
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    var body: some View {
        ZStack {
            Circle().fill(alert.opacity(0.18)).frame(width: 196, height: 196)
            Circle().trim(from: 0, to: progress)
                .stroke(alert, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 186, height: 186)
            Circle().fill(alert).frame(width: 166, height: 166)
                .overlay(
                    VStack(spacing: 4) {
                        Text("SOS").font(.system(size: 42, weight: .black))
                        Text(lang.localized("simple.sosHold")).font(.scaled(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.white)
                )
                .scaleEffect(pressing ? 0.95 : 1)
        }
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: FloatingSOSButton.holdDuration,
                            maximumDistance: FloatingSOSButton.holdTolerance,
                            pressing: { isPressing in
            pressing = isPressing
            if isPressing {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.linear(duration: FloatingSOSButton.holdDuration)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }, perform: {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            coordinator.requestSOS(method: .longPress)
            progress = 0
        })
        .accessibilityLabel(lang.localized("sos.button.a11yLabel"))
        .accessibilityHint(lang.localized("sos.button.a11yHint"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Settings panel

/// Settings → Home style: two cards, standard / simple.
struct HomeStylePanel: View {
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage(HomeStyle.storageKey) private var homeStyle = HomeStyle.standard.rawValue
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.localized("homeStyle.section"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            ForEach(HomeStyle.allCases, id: \.self) { style in
                Button { homeStyle = style.rawValue } label: {
                    HStack(spacing: 10) {
                        Image(systemName: style == .simple ? "textformat.size.larger" : "square.grid.2x2")
                            .font(.scaled(size: 18))
                            .foregroundStyle(safe)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.localized("homeStyle.\(style.rawValue)")).font(.scaled(size: 14, weight: .semibold))
                            Text(lang.localized("homeStyle.\(style.rawValue).desc"))
                                .font(.scaled(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: homeStyle == style.rawValue ? "checkmark.circle.fill" : "circle")
                            .font(.scaled(size: 20))
                            .foregroundStyle(homeStyle == style.rawValue ? safe : Color(.tertiaryLabel))
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.settingsRow)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.3), lineWidth: 1))
    }
}
