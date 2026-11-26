import SwiftUI
import CoreLocation

// MARK: - Home style (protected person)
//
// "Standard" is the full home (map, trips, tools, 5 tabs). "Simple" is for older
// users: large type, four things only — I'm OK, I'm home, call my family, SOS — and
// 3 tabs. Chosen in Settings (and suggested when the text size is set to extra large);
// both use the same data and the same SOS.

enum HomeStyle: String, CaseIterable {
    /// simple: the default — large text, four big buttons (SimpleProtectedHomeView)
    /// standard: "Full" — map, trips, tools, five tabs (ProtectedHomeView)
    /// rider: delivery / rideshare riders — shift, crew, rider SOS (RiderHomeView)
    case simple, standard, rider
    static let storageKey = "protected_home_style"
    /// A protected person who hasn't chosen yet gets the simple home; once they
    /// choose (Settings → Home screen), that choice stays until they change it.
    static let defaultStyle = HomeStyle.simple
}

struct SimpleProtectedHomeView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage(HomeStyle.storageKey) private var homeStyle = HomeStyle.defaultStyle.rawValue
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


    /// Where I am now: the device, else the last fix the location manager kept
    private var myCoordinate: CLLocationCoordinate2D? {
        if let loc = coordinator.locationManager.bestAvailableLocation { return loc.coordinate }
        return coordinator.locationService.currentLocation
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Simple | Full, and the guides
                HStack(spacing: 8) {
                    HomeStyleToggle(current: .simple)
                    Spacer(minLength: 0)
                    TutorialHelpButton(role: .protected, style: .label, tint: teal)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(.scaled(size: 30, weight: .bold))
                        .foregroundStyle(ink)
                    if let last = WidgetDataStore.read().lastCheckInDate {
                        Text(String(format: lang.localized("simple.lastCheckIn"),
                                    last.formatted(.dateTime.hour().minute().locale(Locale(identifier: lang.current.rawValue)))))
                            .font(.scaled(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }

                // Where I am: map, address, search, hospital / pharmacy / police
                SimpleMapCard(coordinate: myCoordinate)

                // Who in the family is online (tap to call)
                WhoIsOnlineRow(onInvite: { showInvite = true })

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

                // Disasters, traffic, crime around me: one calm line each
                NearbyAlertsCard(style: .compact, coordinate: myCoordinate)

                // How to use: always on Home so guides can be watched again
                TutorialHelpButton(role: .protected, style: .card, tint: teal)

                SwitchHomeCard(target: .standard)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 18)
        }
        .background(cream)
        // SOS and "call family" never scroll away
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SimpleSOSBar(caller: caller)
        }
        .sheet(isPresented: $showInvite) {
            InviteGuardianSheet(inviterRole: .protected_).environmentObject(coordinator)
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

/// Same hold as the floating button, drawn large.
struct BigSOSButton: View {
    /// The red circle; 166 on the rider home, smaller in the simple home's bottom bar
    var diameter: CGFloat = 166
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var progress: Double = 0
    @State private var pressing = false
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    var body: some View {
        let k = diameter / 166
        ZStack {
            Circle().fill(alert.opacity(0.18)).frame(width: diameter + 30 * k, height: diameter + 30 * k)
            Circle().trim(from: 0, to: progress)
                .stroke(alert, style: StrokeStyle(lineWidth: max(5, 8 * k), lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: diameter + 20 * k, height: diameter + 20 * k)
            Circle().fill(alert).frame(width: diameter, height: diameter)
                .overlay(
                    VStack(spacing: 4 * k) {
                        Text("SOS").font(.system(size: max(24, 42 * k), weight: .black))
                        if diameter >= 120 {
                            Text(lang.localized("simple.sosHold")).font(.scaled(size: 15, weight: .medium))
                        }
                    }
                    .foregroundStyle(.white)
                )
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
            coordinator.requestSOS(method: .longPress)
            progress = 0
        })
        .accessibilityLabel(lang.localized("sos.button.a11yLabel"))
        .accessibilityHint(lang.localized("sos.button.a11yHint"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Settings panel

/// Settings → Home style: simple (default), full, rider. Sits in a SettingsSection.
struct HomeStylePanel: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage(HomeStyle.storageKey) private var storedStyle = HomeStyle.defaultStyle.rawValue
    /// Read so the panel redraws; the demo keeps its own choice
    /// The home of My safety (not the Work side that may be on screen)
    private var homeStyle: String {
        _ = storedStyle
        return coordinator.hasWorkSide ? coordinator.familyHomeStyle : coordinator.effectiveHomeStyle
    }
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    @State private var showRiderSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(HomeStyle.allCases, id: \.self) { style in
                Button {
                    coordinator.setHomeStyle(style)
                    // First time choosing Rider: the rider setup (crew, someone at home, lock-screen SOS)
                    if style == .rider && !coordinator.riderSetupDone { coordinator.beginRiderSetup(at: .ride) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: style == .simple ? "textformat.size.larger" : style == .rider ? "bicycle" : "square.grid.2x2")
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
            riderSettingsRow
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showRiderSettings) { RiderSettingsView().environmentObject(coordinator) }
    }

    /// Rider settings, under the Rider choice when it is on
    @ViewBuilder private var riderSettingsRow: some View {
        if homeStyle == HomeStyle.rider.rawValue {
            Button { showRiderSettings = true } label: {
                HStack {
                    Label(lang.localized("rider.settings.title"), systemImage: "slider.horizontal.3").font(.scaled(size: 14))
                    Spacer()
                    Image(systemName: "chevron.right").font(.scaled(size: 12)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.settingsRow)
            .accessibilityIdentifier("settings.riderSettings")
        }
    }
}
