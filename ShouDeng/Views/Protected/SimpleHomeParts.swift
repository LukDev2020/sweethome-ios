import SwiftUI
import MapKit
import CoreLocation

// MARK: - Simple home parts
//
// The map with the address and a search box, who in the family is online, the SOS
// bar pinned to the bottom, and the switch between the simple and the full home.

private let safeGreen = Color(red: 63/255, green: 143/255, blue: 110/255)
private let tealBlue = Color(red: 47/255, green: 111/255, blue: 143/255)
private let sosRed = Color(red: 196/255, green: 69/255, blue: 60/255)

// MARK: - Map: where I am, the address, search

struct SimpleMapCard: View {
    let coordinate: CLLocationCoordinate2D?
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var address: String?
    @State private var fullMap: FullMapStart?

    struct FullMapStart: Identifiable {
        let id = UUID()
        var category: String?
        var typing = false
    }

    private static let quickCategories = ["hospital", "pharmacy", "police"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBox
            mapView
            VStack(alignment: .leading, spacing: 6) {
                Text(address.map { String(format: lang.localized("simple.map.youAreAt"), $0) }
                     ?? lang.localized(coordinate == nil ? "simple.map.finding" : "simple.map.locating"))
                    .font(.scaled(size: 18, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("simple.address")
                sharingLine
            }
            quickChips
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(.separator).opacity(0.35), lineWidth: 1))
        .task(id: coordinateKey) { await lookUpAddress() }
        .fullScreenCover(item: $fullMap) { start in
            FullScreenMapView(pins: pins, label: lang.localized("protected.home.myLocation"), focusedPinId: .constant(nil),
                              locationService: coordinator.locationService,
                              startCategoryId: start.category, startTyping: start.typing)
        }
    }

    private var coordinateKey: String {
        coordinate.map { String(format: "%.4f,%.4f-%@", $0.latitude, $0.longitude, lang.current.rawValue) } ?? "none"
    }

    private var pins: [LocationPin] {
        guard let c = coordinate else { return [] }
        return [LocationPin(id: "me", name: lang.localized("protected.home.me"), coordinate: c,
                            color: Color(red: 232/255, green: 163/255, blue: 61/255), isMe: true, role: .me)]
    }

    /// Looks like a search field; opens the full map with the keyboard up
    private var searchBox: some View {
        Button { fullMap = FullMapStart(typing: true) } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .semibold))
                Text(lang.localized("simple.map.search"))
                    .font(.scaled(size: 18))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("simple.map.search")
    }

    @ViewBuilder private var mapView: some View {
        if let c = coordinate {
            Button { fullMap = FullMapStart() } label: {
                Map(position: .constant(.region(MKCoordinateRegion(center: c, latitudinalMeters: 900, longitudinalMeters: 900))),
                    interactionModes: []) {
                    Annotation(lang.localized("protected.home.me"), coordinate: c) {
                        ZStack {
                            Circle().fill(tealBlue.opacity(0.2)).frame(width: 44, height: 44)
                            Circle().fill(.white).frame(width: 22, height: 22)
                            Circle().fill(tealBlue).frame(width: 16, height: 16)
                        }
                    }
                }
                .allowsHitTesting(false)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Label(lang.localized("simple.map.open"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(10)
                }
            }
            .buttonStyle(.plain)
            .id(String(format: "%.4f,%.4f", c.latitude, c.longitude))
            .accessibilityLabel(lang.localized("simple.map.open"))
            .accessibilityIdentifier("simple.map")
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 120)
                .overlay(ProgressView())
        }
    }

    /// Who sees where I am; tap to pause / resume (an SOS always turns it back on)
    private var sharingLine: some View {
        let paused = coordinator.isTrackingPaused
        let sharing = coordinator.myGuardians.filter(\.permissions.canSeeLocation).count
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation { paused ? coordinator.resumeTracking() : coordinator.pauseTracking() }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(paused ? Color(.systemGray) : safeGreen).frame(width: 10, height: 10)
                Text(paused ? lang.localized("simple.map.paused")
                     : sharing == 0 ? lang.localized("simple.map.notShared")
                     : lang.localized("simple.map.sharedWith", count: sharing))
                    .font(.scaled(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text(lang.localized(paused ? "simple.map.resume" : "simple.map.pause"))
                    .font(.scaled(size: 14, weight: .semibold))
                    .foregroundStyle(tealBlue)
            }
        }
        .buttonStyle(.plain)
        .coachMark(CoachAnchor.tracking)
        .accessibilityIdentifier("simple.sharing")
    }

    private var quickChips: some View {
        HStack(spacing: 8) {
            ForEach(Self.quickCategories, id: \.self) { id in
                if let cat = MapPlaceCategory.emergency.first(where: { $0.id == id }) {
                    Button { fullMap = FullMapStart(category: id) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: cat.icon).font(.system(size: 22, weight: .semibold))
                            Text(lang.localized(cat.labelKey))
                                .font(.scaled(size: 15, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(cat.color)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: 14).fill(cat.color.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("simple.map.\(id)")
                }
            }
        }
    }

    private func lookUpAddress() async {
        guard let c = coordinate else { address = nil; return }
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: c.latitude, longitude: c.longitude),
            preferredLocale: Locale(identifier: lang.current.rawValue))
        guard let p = placemarks?.first else { return }
        // City, district, street — short enough to read at a glance
        let parts = [p.locality, p.subLocality, p.thoroughfare].compactMap { $0 }.filter { !$0.isEmpty }
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0).inserted }
        let separator = [.chinese, .traditionalChinese, .japanese].contains(lang.current) ? "" : ", "
        address = unique.isEmpty ? p.name : unique.joined(separator: separator)
    }
}

// MARK: - Who's online

struct WhoIsOnlineRow: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    var onInvite: () -> Void

    static let onlineWindow: TimeInterval = 15 * 60

    /// Online first, then most recently active, then on duty
    private var guardians: [Guardian] {
        coordinator.myGuardians.sorted { a, b in
            let ta = a.user.lastActiveAt ?? .distantPast, tb = b.user.lastActiveAt ?? .distantPast
            if ta != tb { return ta > tb }
            return a.isOnDuty && !b.isOnDuty
        }
    }

    static func isOnline(_ g: Guardian, now: Date = Date()) -> Bool {
        guard let t = g.user.lastActiveAt else { return false }
        return now.timeIntervalSince(t) < onlineWindow
    }

    static func status(_ g: Guardian, now: Date = Date()) -> String {
        let lang = LanguageManager.shared
        if let t = g.user.lastActiveAt {
            let minutes = Int(now.timeIntervalSince(t) / 60)
            if minutes < 15 { return lang.localized("online.now") }
            if minutes < 60 { return lang.localized("online.minutes", count: minutes) }
            if minutes < 24 * 60 { return lang.localized("online.hours", count: minutes / 60) }
            return lang.localized("online.days", count: minutes / (24 * 60))
        }
        // Not known yet (older server, or never used the app): duty, else their local time
        if g.isOnDuty { return lang.localized("protected.home.onDuty") }
        let f = DateFormatter()
        f.timeZone = g.user.timeZone
        f.locale = Locale(identifier: lang.current.rawValue)
        f.timeStyle = .short
        return String(format: lang.localized("online.localTime"), f.string(from: now))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(lang.localized("online.title"))
                    .font(.scaled(size: 20, weight: .bold))
                    .foregroundStyle(Color.appInk)
                Spacer()
                let online = coordinator.myGuardians.filter { Self.isOnline($0) }.count
                if online > 0 {
                    Text(lang.localized("online.count", count: online))
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundStyle(safeGreen)
                }
            }
            if guardians.isEmpty {
                Button(action: onInvite) {
                    Label(lang.localized("simple.noGuardian"), systemImage: "person.badge.plus")
                        .font(.scaled(size: 18, weight: .semibold))
                        .foregroundStyle(tealBlue)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(guardians) { g in person(g) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(.separator).opacity(0.35), lineWidth: 1))
        .coachMark(CoachAnchor.guardiansGlobe)
        .accessibilityIdentifier("simple.online")
    }

    private func person(_ g: Guardian) -> some View {
        let online = Self.isOnline(g)
        let phone = (g.user.phone ?? "").filter { $0.isNumber || $0 == "+" }
        return Button {
            if !phone.isEmpty, let url = URL(string: "tel:\(phone)") { ExternalURL.open(url) }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(user: g.user, size: 58)
                    Circle()
                        .fill(online ? safeGreen : Color(.systemGray3))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 3))
                }
                Text(g.user.displayName)
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                    .lineLimit(1)
                Text(Self.status(g))
                    .font(.scaled(size: 13))
                    .foregroundStyle(online ? safeGreen : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 92)
        }
        .buttonStyle(.plain)
        .disabled(phone.isEmpty)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(g.user.displayName), \(Self.status(g))")
        .accessibilityHint(phone.isEmpty ? "" : String(format: lang.localized("simple.call"), g.user.displayName))
    }
}

// MARK: - SOS pinned to the bottom

/// Always on screen, however far the home is scrolled: hold SOS, or call family.
struct SimpleSOSBar: View {
    let caller: Guardian?
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        HStack(spacing: 14) {
            BigSOSButton(diameter: 84)
                .coachMark(CoachAnchor.sosButton)
            VStack(alignment: .leading, spacing: 8) {
                Text(lang.localized("simple.sosBar.hint"))
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(sosRed)
                    .fixedSize(horizontal: false, vertical: true)
                callButton
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle().fill(.regularMaterial)
                .overlay(alignment: .top) { Divider() }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder private var callButton: some View {
        if let caller, let phone = caller.user.phone, !phone.isEmpty {
            call(String(format: lang.localized("simple.call"), caller.user.displayName), phone, Color(red: 74/255, green: 93/255, blue: 138/255))
        } else {
            call(String(format: lang.localized("tut.now.callLocal"), coordinator.localEmergencyNumber), coordinator.localEmergencyNumber, sosRed)
        }
    }

    private func call(_ title: String, _ number: String, _ color: Color) -> some View {
        Button {
            let digits = number.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:\(digits)") { ExternalURL.open(url) }
        } label: {
            Label(title, systemImage: "phone.fill")
                .font(.scaled(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(color))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("simple.sosBar.call")
    }
}

// MARK: - Simple ⇄ Full

/// "Simple | Full" at the top of both homes. Switching asks first, with what each has.
struct HomeStyleToggle: View {
    let current: HomeStyle
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var target: HomeStyle?

    var body: some View {
        HStack(spacing: 2) {
            segment(.simple, icon: "textformat.size.larger")
            segment(.standard, icon: "square.grid.2x2.fill")
        }
        .padding(3)
        .background(Capsule().fill(Color(.tertiarySystemFill)))
        .sheet(item: $target) { style in
            HomeStyleCompareSheet(target: style).environmentObject(coordinator)
        }
        .accessibilityIdentifier("home.styleToggle")
    }

    private func segment(_ style: HomeStyle, icon: String) -> some View {
        let on = style == current
        return Button { if !on { target = style } } label: {
            Label(lang.localized("homeStyle.short.\(style.rawValue)"), systemImage: icon)
                .font(.scaled(size: 15, weight: .semibold))
                .foregroundStyle(on ? .white : Color.appInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(on ? tealBlue : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("home.style.\(style.rawValue)")
    }
}

extension HomeStyle: Identifiable { var id: String { rawValue } }

/// At the bottom of each home: what the other one adds, one tap to compare and switch.
struct SwitchHomeCard: View {
    let target: HomeStyle
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            HStack(spacing: 12) {
                Image(systemName: target == .standard ? "square.grid.2x2.fill" : "textformat.size.larger")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(tealBlue))
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.localized("homeStyle.switchTo.\(target.rawValue)"))
                        .font(.scaled(size: 17, weight: .bold))
                        .foregroundStyle(Color.appInk)
                    Text(lang.localized("homeStyle.switchHint.\(target.rawValue)"))
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tealBlue.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tealBlue.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $show) { HomeStyleCompareSheet(target: target).environmentObject(coordinator) }
        .accessibilityIdentifier("home.switchCard")
    }
}

/// Simple and Full side by side: a sketch of each and what it has. "Switch" applies it.
struct HomeStyleCompareSheet: View {
    let target: HomeStyle
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    private static let features: [HomeStyle: [(String, String)]] = [
        .simple: [("textformat.size.larger", "homeStyle.f.simple.big"), ("map.fill", "homeStyle.f.simple.map"),
                  ("person.2.fill", "homeStyle.f.simple.online"), ("dot.radiowaves.left.and.right", "homeStyle.f.simple.nearby"),
                  ("sos", "homeStyle.f.simple.sos")],
        .standard: [("globe.asia.australia.fill", "homeStyle.f.full.globe"), ("clock.fill", "homeStyle.f.full.clocks"),
                    ("point.topleft.down.to.point.bottomright.curvepath.fill", "homeStyle.f.full.trips"),
                    ("square.grid.2x2.fill", "homeStyle.f.full.tools"), ("rectangle.split.3x1.fill", "homeStyle.f.full.tabs")],
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text(lang.localized("homeStyle.compare.lead"))
                        .font(.scaled(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(alignment: .top, spacing: 12) {
                        column(.simple)
                        column(.standard)
                    }
                    Button {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        coordinator.setHomeStyle(target)
                        dismiss()
                    } label: {
                        Text(lang.localized("homeStyle.switchTo.\(target.rawValue)"))
                            .font(.scaled(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(RoundedRectangle(cornerRadius: 16).fill(tealBlue))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.style.confirm")
                    Text(lang.localized("homeStyle.compare.back"))
                        .font(.scaled(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .navigationTitle(lang.localized("homeStyle.compare.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.localized("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func column(_ style: HomeStyle) -> some View {
        let chosen = style == target
        let current = style.rawValue == (coordinator.hasWorkSide ? coordinator.familyHomeStyle : coordinator.effectiveHomeStyle)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(lang.localized("homeStyle.short.\(style.rawValue)"))
                    .font(.scaled(size: 18, weight: .bold))
                Spacer()
                if current {
                    Text(lang.localized("homeStyle.compare.now"))
                        .font(.scaled(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            sketch(style)
            ForEach(Self.features[style] ?? [], id: \.1) { icon, key in
                Label {
                    Text(lang.localized(key)).font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: icon).foregroundStyle(tealBlue)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(chosen ? tealBlue : Color(.separator).opacity(0.4), lineWidth: chosen ? 2.5 : 1))
    }

    /// A small drawing of the home, not a screenshot: shape over detail
    @ViewBuilder private func sketch(_ style: HomeStyle) -> some View {
        let block = { (h: CGFloat, c: Color) in RoundedRectangle(cornerRadius: 4).fill(c).frame(height: h) }
        VStack(spacing: 4) {
            if style == .simple {
                block(8, Color(.systemGray4)).frame(width: 60).frame(maxWidth: .infinity, alignment: .leading)
                block(34, Color(red: 200/255, green: 222/255, blue: 210/255))
                block(14, safeGreen)
                block(14, tealBlue)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Circle().fill(sosRed).frame(width: 18, height: 18)
                    block(12, Color(red: 74/255, green: 93/255, blue: 138/255))
                }
            } else {
                block(10, Color(red: 25/255, green: 42/255, blue: 70/255))
                block(30, Color.black.opacity(0.8))
                HStack(spacing: 3) { ForEach(0..<4, id: \.self) { _ in block(8, Color(.systemGray4)) } }
                block(16, Color(red: 200/255, green: 222/255, blue: 210/255))
                HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in block(10, Color(.systemGray5)) } }
                Spacer(minLength: 0)
                HStack(spacing: 3) { ForEach(0..<5, id: \.self) { _ in block(5, Color(.systemGray3)) } }
            }
        }
        .padding(6)
        .frame(height: 132)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.5)))
        .accessibilityHidden(true)
    }
}
