import SwiftUI
import AVFoundation

// MARK: - How-to guides: the engine
//
// A guide replays the real screens on a small phone: a finger moves to a control,
// taps, holds or types, and the next step shows the screen the app shows next.
// Screen labels use the same localization keys as the real screens, so the replay
// reads like the app in every language. What each guide shows: TutorialCatalog.swift;
// the guide list and the emergency strip: TutorialCenterView.swift.

enum TutorialRole: String, CaseIterable {
    case protected, guardian, rider
}

enum TutorialCategory: String, CaseIterable {
    case emergency, everyday, people, setup
    var titleKey: String { "tut.cat.\(rawValue)" }
    var icon: String {
        switch self {
        case .emergency: return "exclamationmark.triangle.fill"
        case .everyday: return "sun.max.fill"
        case .people: return "person.2.fill"
        case .setup: return "slider.horizontal.3"
        }
    }
}

/// Text on a mock screen: a localization key (string literals), raw text, or a key
/// formatted with another text.
indirect enum MT: ExpressibleByStringLiteral {
    case k(String)
    case r(String)
    case f(String, MT)
    /// The lock-screen card's own text table (WidgetDataStore), for la.* labels
    case w(String)
    /// The local emergency number / police number of the person watching
    case emergency, police

    init(stringLiteral value: String) { self = .k(value) }

    var text: String {
        let lang = LanguageManager.shared
        switch self {
        case .k(let key): return lang.localized(key)
        case .r(let raw): return raw
        case .f(let key, let arg): return String(format: lang.localized(key), arg.text)
        case .w(let key): return WidgetDataStore.localized(key)
        case .emergency: return TutorialContext.emergencyNumber
        case .police: return TutorialContext.policeNumber
        }
    }

    /// Every key this text reads (for the completeness test)
    var keys: [String] {
        switch self {
        case .k(let key): return [key]
        case .r, .w, .emergency, .police: return []
        case .f(let key, let arg): return [key] + arg.keys
        }
    }
}

/// Numbers the replays show, set from the person's country when the guides open
enum TutorialContext {
    static var emergencyNumber = "112"
    static var policeNumber = "112"
}

struct MockPin {
    let initial: MT
    let color: Color
    /// 0…1 across and down the map
    let x: CGFloat
    let y: CGFloat
    var alert = false
}

/// One control or block on a mock screen. `id` is what a gesture points at; parts of
/// a control (a chip, a round button) are "<id>.<index>".
struct MockItem {
    enum Trailing { case none, chevron, toggle(Bool), value(MT), check }
    struct Round { let icon: String; let color: Color; let label: MT }

    enum Kind {
        /// Large greeting / page title with a line under it
        case greeting(MT, MT?)
        /// A full-width coloured button (simple home)
        case bigButton(String, MT, Color)
        /// The red hold-for-SOS circle
        case sos(MT)
        /// A settings-style row
        case row(String, Color, MT, MT?, Trailing)
        /// A tinted card with an icon, a title and a line
        case card(String, Color, MT, MT?)
        /// A text field; a `type` gesture writes the text in letter by letter
        case field(String, MT, MT?)
        case chips([MT], Int?)
        case map([MockPin])
        case button(MT, Color, filled: Bool)
        /// A big number counting down from `seconds`
        case countdown(MT, Int, Color)
        /// An invite code in large letters
        case code(MT)
        case note(MT)
        /// Round buttons with a label under each (call screen, alert actions)
        case rounds([Round])
        /// A lock-screen style card (the live card on the lock screen)
        case lockCard(MT, MT, [MT])
    }

    let id: String
    let kind: Kind

    init(_ id: String, _ kind: Kind) {
        self.id = id
        self.kind = kind
    }

    var keys: [String] {
        switch kind {
        case .greeting(let a, let b): return a.keys + (b?.keys ?? [])
        case .bigButton(_, let t, _), .sos(let t), .code(let t), .note(let t), .button(let t, _, _), .countdown(let t, _, _): return t.keys
        case .row(_, _, let t, let s, let trailing):
            var k = t.keys + (s?.keys ?? [])
            if case .value(let v) = trailing { k += v.keys }
            return k
        case .card(_, _, let t, let s), .field(_, let t, let s): return t.keys + (s?.keys ?? [])
        case .chips(let c, _): return c.flatMap(\.keys)
        case .map(let pins): return pins.flatMap(\.initial.keys)
        case .rounds(let r): return r.flatMap(\.label.keys)
        case .lockCard(let a, let b, let c): return a.keys + b.keys + c.flatMap(\.keys)
        }
    }
}

struct MockBanner {
    let id: String
    let icon: String
    let tint: Color
    let title: MT
    let body: MT?
}

struct MockScreen {
    enum Chrome { case app, lock, call }
    var chrome: Chrome = .app
    var title: MT? = nil
    var tint: Color = SettingsTint.safe
    var background: Color = Color(.systemBackground)
    var items: [MockItem]
    /// A sheet over the screen (title, items)
    var sheet: (title: MT?, items: [MockItem])? = nil
    /// A notification at the top
    var banner: MockBanner? = nil
    /// A short confirmation at the bottom
    var toast: MT? = nil
    /// Tab bar icons and the selected one
    var tabs: (icons: [String], selected: Int)? = nil

    var keys: [String] {
        var k = (title?.keys ?? []) + items.flatMap(\.keys) + (toast?.keys ?? [])
        if let sheet { k += (sheet.title?.keys ?? []) + sheet.items.flatMap(\.keys) }
        if let banner { k += banner.title.keys + (banner.body?.keys ?? []) }
        return k
    }
}

enum MockGesture {
    case none
    case tap(String)
    case hold(String, Double)
    case type(String)
    /// The phone drops and shakes (a fall)
    case shake

    var target: String? {
        switch self {
        case .tap(let id), .hold(let id, _), .type(let id): return id
        case .none, .shake: return nil
        }
    }
}

struct TutorialStep {
    let caption: String
    let screen: MockScreen
    let gesture: MockGesture
}

/// What "Do it now" opens from a guide
enum TutorialAction {
    case sos, checkIn, homeSafe, inviteGuardian, invitePerson, joinWithCode, medicalCard,
         lockScreenCard, fakeCall, duressCode, fallDetection, nearbyHelp, emergencyNumbers,
         textSize, startShift, crashReport, bikeReport, crew, handsFree, dutySchedule, criticalAlerts
}

struct TutorialGuide: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let category: TutorialCategory
    let roles: Set<TutorialRole>
    var action: TutorialAction? = nil
    let steps: [TutorialStep]

    var titleKey: String { "tut.\(id).title" }
    var summaryKey: String { "tut.\(id).summary" }
    /// Other words people may search with, comma separated
    var keywordsKey: String { "tut.\(id).keywords" }

    var allKeys: [String] {
        [titleKey, summaryKey, keywordsKey] + steps.flatMap { [$0.caption] + $0.screen.keys }
    }

    /// Rough length, for the list ("4 steps · 20 s")
    var seconds: Int {
        Int(steps.reduce(0.0) { total, step in
            switch step.gesture {
            case .hold(_, let s): return total + s + 3.2
            case .type: return total + 4
            default: return total + 3.5
            }
        }.rounded())
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let lang = LanguageManager.shared
        let haystack = ([titleKey, summaryKey, keywordsKey] + steps.map(\.caption))
            .map { lang.localized($0).lowercased() }
        return q.split(separator: " ").allSatisfy { word in haystack.contains { $0.contains(word) } }
    }
}

// MARK: - Player

/// Which guides this phone has watched to the end ("Watch again" on Home and in the list).
/// Its own store, not @AppStorage: demo mode swaps the views' AppStorage for a sandbox.
@MainActor
final class TutorialHistory: ObservableObject {
    static let shared = TutorialHistory()
    private static let key = "tut.watched"
    @Published private(set) var watched: Set<String>

    private init() {
        watched = Set((UserDefaults.standard.string(forKey: Self.key) ?? "").split(separator: ",").map(String.init))
    }

    func mark(_ id: String) {
        guard watched.insert(id).inserted else { return }
        UserDefaults.standard.set(watched.sorted().joined(separator: ","), forKey: Self.key)
    }

    func hasWatched(any guides: [TutorialGuide]) -> Bool {
        !watched.isDisjoint(with: guides.map(\.id))
    }
}

@MainActor
final class TutorialPlayer: ObservableObject {
    @Published private(set) var step = 0
    @Published private(set) var target: String?
    @Published private(set) var fingerShown = false
    @Published private(set) var pressing = false
    @Published private(set) var holdProgress: Double = 0
    @Published private(set) var typed = 0
    @Published private(set) var shaking = false
    @Published private(set) var playing = false
    /// Steps already played through (ticked in the list)
    @Published private(set) var seen: Set<Int> = []
    /// Played to the last step: the play button becomes "Watch again"
    @Published private(set) var finished = false
    @Published var speaks = false {
        didSet { if !speaks { voice.stopSpeaking(at: .immediate) } else { say(step) } }
    }

    let guide: TutorialGuide
    var reduceMotion = false
    private var task: Task<Void, Never>?
    private let voice = AVSpeechSynthesizer()

    init(guide: TutorialGuide) {
        self.guide = guide
    }

    func play(from index: Int? = nil) {
        task?.cancel()
        playing = true
        let start = finished && index == nil ? 0 : (index ?? step)
        finished = false
        task = Task { [weak self] in await self?.run(from: start) }
    }

    func pause() {
        task?.cancel()
        task = nil
        playing = false
        pressing = false
        voice.stopSpeaking(at: .immediate)
    }

    func stop() {
        pause()
    }

    private func run(from start: Int) async {
        var i = max(0, min(start, guide.steps.count - 1))
        while !Task.isCancelled {
            await perform(i)
            guard !Task.isCancelled else { return }
            seen.insert(i)
            if i + 1 < guide.steps.count {
                i += 1
            } else {
                // The end: keep the last screen and offer "Watch again"
                await wait(1.2)
                guard !Task.isCancelled else { return }
                withAnimation { fingerShown = false; playing = false; finished = true }
                TutorialHistory.shared.mark(guide.id)
                task = nil
                return
            }
        }
    }

    private func perform(_ i: Int) async {
        let s = guide.steps[i]
        withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.45)) {
            step = i
            typed = 0
            holdProgress = 0
            pressing = false
            shaking = false
        }
        say(i)
        await wait(1.0)
        switch s.gesture {
        case .none:
            withAnimation { fingerShown = false }
            await wait(2.4)
        case .tap(let id):
            await moveFinger(to: id)
            await press()
            await wait(1.0)
        case .hold(let id, let seconds):
            await moveFinger(to: id)
            withAnimation(.easeOut(duration: 0.12)) { pressing = true }
            withAnimation(.linear(duration: seconds)) { holdProgress = 1 }
            await wait(seconds)
            withAnimation(.easeOut(duration: 0.2)) { pressing = false }
            await wait(0.8)
        case .type(let id):
            await moveFinger(to: id)
            await press()
            let count = typedLength(of: id, in: s.screen)
            for c in 0...count {
                guard !Task.isCancelled else { return }
                typed = c
                await wait(0.09)
            }
            await wait(1.0)
        case .shake:
            withAnimation { fingerShown = false }
            withAnimation(.easeIn(duration: 0.35)) { shaking = true }
            await wait(1.2)
            withAnimation(.spring(duration: 0.4)) { shaking = false }
            await wait(0.8)
        }
        // Give a spoken caption time to finish
        while speaks && voice.isSpeaking && !Task.isCancelled { await wait(0.2) }
    }

    private func moveFinger(to id: String) async {
        let firstShow = !fingerShown
        withAnimation(reduceMotion || firstShow ? .easeOut(duration: 0.25) : .spring(duration: 0.75, bounce: 0.15)) {
            target = id
            fingerShown = true
        }
        await wait(firstShow ? 0.5 : 0.85)
    }

    private func press() async {
        withAnimation(.easeOut(duration: 0.12)) { pressing = true }
        await wait(0.28)
        withAnimation(.easeOut(duration: 0.2)) { pressing = false }
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func typedLength(of id: String, in screen: MockScreen) -> Int {
        let items = screen.items + (screen.sheet?.items ?? [])
        guard let item = items.first(where: { $0.id == id }), case .field(_, _, let text) = item.kind else { return 0 }
        return text?.text.count ?? 0
    }

    private func say(_ i: Int) {
        guard speaks, guide.steps.indices.contains(i) else { return }
        voice.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: LanguageManager.shared.localized(guide.steps[i].caption))
        utterance.voice = AVSpeechSynthesisVoice(language: Self.voiceLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        voice.speak(utterance)
    }

    private static var voiceLanguage: String {
        switch LanguageManager.shared.current {
        case .english: return "en-US"
        case .chinese: return "zh-CN"
        case .traditionalChinese: return "zh-HK"
        case .french: return "fr-FR"
        case .japanese: return "ja-JP"
        }
    }
}

// MARK: - The phone

private struct MockAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func mockAnchor(_ id: String) -> some View {
        anchorPreference(key: MockAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

/// The animated phone for one guide. Drawn at a fixed size and scaled to fit.
struct TutorialPhone: View {
    @ObservedObject var player: TutorialPlayer
    @Environment(\.colorScheme) private var scheme

    static let size = CGSize(width: 280, height: 580)

    private var screen: MockScreen { player.guide.steps[player.step].screen }
    private var gesture: MockGesture { player.guide.steps[player.step].gesture }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.size.width, geo.size.height / Self.size.height)
            phone
                .frame(width: Self.size.width, height: Self.size.height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }

    private var phone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
            MockScreenView(screen: screen, gesture: gesture, player: player)
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .padding(8)
                .overlayPreferenceValue(MockAnchorKey.self) { anchors in
                    GeometryReader { proxy in
                        if player.fingerShown, let id = player.target, let anchor = anchors[id] {
                            let rect = proxy[anchor]
                            Finger(pressing: player.pressing, holding: holdTarget == id ? player.holdProgress : nil)
                                .position(x: rect.midX, y: rect.midY)
                                .transition(.opacity)
                        }
                    }
                }
            // Dynamic Island
            Capsule().fill(Color.black).frame(width: 84, height: 24).frame(maxHeight: .infinity, alignment: .top).padding(.top, 16)
        }
        .rotationEffect(.degrees(player.shaking ? -14 : 0))
        .offset(y: player.shaking ? 40 : 0)
        .modifier(ShakeEffect(amount: player.shaking ? 1 : 0))
    }

    private var holdTarget: String? {
        if case .hold(let id, _) = gesture { return id }
        return nil
    }
}

private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 6), y: 0))
    }
}

/// The touch: a soft circle with a ripple on tap and a ring that fills on hold
private struct Finger: View {
    let pressing: Bool
    let holding: Double?

    var body: some View {
        ZStack {
            if pressing {
                Circle()
                    .stroke(Color.white.opacity(0.7), lineWidth: 3)
                    .frame(width: 64, height: 64)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if let holding {
                Circle()
                    .trim(from: 0, to: holding)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 58, height: 58)
            }
            Circle()
                .fill(Color.gray.opacity(0.45))
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                .frame(width: 38, height: 38)
                .scaleEffect(pressing ? 0.8 : 1)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .offset(x: 18, y: 24)
                .scaleEffect(pressing ? 0.92 : 1)
        }
        .allowsHitTesting(false)
    }
}

/// One mock screen: status bar, title, items, then any sheet, banner and toast
private struct MockScreenView: View {
    let screen: MockScreen
    let gesture: MockGesture
    @ObservedObject var player: TutorialPlayer

    var body: some View {
        ZStack(alignment: .top) {
            background
            VStack(spacing: 0) {
                statusBar
                if let title = screen.title, screen.chrome == .app {
                    Text(title.text)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(screen.chrome == .app ? Color.appInk : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                }
                if screen.chrome == .lock {
                    lockClock
                }
                VStack(spacing: 9) {
                    ForEach(screen.items, id: \.id) { item in
                        MockItemView(item: item, chrome: screen.chrome, tint: screen.tint, gesture: gesture, player: player)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 14)
                Spacer(minLength: 0)
                if let tabs = screen.tabs, screen.sheet == nil {
                    tabBar(tabs.icons, tabs.selected)
                }
            }
            if let sheet = screen.sheet {
                Color.black.opacity(0.25).transition(.opacity)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 9) {
                        Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 36, height: 5).padding(.top, 7)
                        if let title = sheet.title {
                            Text(title.text)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.appInk)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 14)
                        }
                        ForEach(sheet.items, id: \.id) { item in
                            MockItemView(item: item, chrome: .app, tint: screen.tint, gesture: gesture, player: player)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 26)
                    .frame(maxWidth: .infinity)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .ignoresSafeArea()
                    )
                }
                .transition(.move(edge: .bottom))
            }
            if let banner = screen.banner {
                bannerView(banner)
                    .padding(.horizontal, 8)
                    .padding(.top, screen.chrome == .lock ? 150 : 34)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let toast = screen.toast {
                VStack {
                    Spacer()
                    Label(toast.text, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(SettingsTint.safe))
                        .padding(.bottom, screen.tabs == nil ? 24 : 62)
                        .padding(.horizontal, 12)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder private var background: some View {
        switch screen.chrome {
        case .app: screen.background
        case .lock:
            LinearGradient(colors: [Color(red: 0.12, green: 0.2, blue: 0.36), Color(red: 0.36, green: 0.27, blue: 0.48)],
                           startPoint: .top, endPoint: .bottom)
        case .call:
            LinearGradient(colors: [Color(red: 0.2, green: 0.22, blue: 0.26), Color(red: 0.08, green: 0.09, blue: 0.11)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var statusBar: some View {
        HStack {
            Text("9:41").font(.system(size: 12, weight: .semibold))
            Spacer()
            Image(systemName: "cellularbars").font(.system(size: 10))
            Image(systemName: "battery.75percent").font(.system(size: 12))
        }
        .foregroundStyle(screen.chrome == .app ? Color.primary : .white)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .opacity(screen.chrome == .lock ? 0.9 : 1)
    }

    private var lockClock: some View {
        VStack(spacing: 0) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month().day().locale(Locale(identifier: LanguageManager.shared.current.rawValue))))
                .font(.system(size: 13, weight: .semibold))
            Text("9:41").font(.system(size: 64, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.bottom, 16)
    }

    private func tabBar(_ icons: [String], _ selected: Int) -> some View {
        HStack {
            ForEach(Array(icons.enumerated()), id: \.offset) { i, icon in
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(i == selected ? screen.tint : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .mockAnchor("tab.\(i)")
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 22)
        .background(.bar)
    }

    private func bannerView(_ b: MockBanner) -> some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 7).fill(b.tint).frame(width: 28, height: 28)
                .overlay(Image(systemName: b.icon).font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(b.title.text).font(.system(size: 12, weight: .bold)).lineLimit(2)
                if let body = b.body { Text(body.text).font(.system(size: 11)).lineLimit(3) }
            }
            .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .scaleEffect(gesture.target == b.id && player.pressing ? 0.97 : 1)
        .mockAnchor(b.id)
    }
}

private struct MockItemView: View {
    let item: MockItem
    let chrome: MockScreen.Chrome
    let tint: Color
    let gesture: MockGesture
    @ObservedObject var player: TutorialPlayer

    private var onLight: Bool { chrome == .app }
    private var fg: Color { onLight ? .appInk : .white }
    private var isTarget: Bool { gesture.target == item.id }
    private var pressed: Bool { isTarget && player.pressing }

    var body: some View {
        content
            .scaleEffect(pressed ? 0.96 : 1)
            .opacity(pressed ? 0.85 : 1)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .greeting(let title, let sub):
            VStack(alignment: .leading, spacing: 3) {
                Text(title.text).font(.system(size: 21, weight: .bold)).foregroundStyle(fg).lineLimit(2).minimumScaleFactor(0.7)
                if let sub {
                    Text(sub.text).font(.system(size: 12)).foregroundStyle(onLight ? .secondary : Color.white.opacity(0.8)).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .mockAnchor(item.id)

        case .bigButton(let icon, let title, let color):
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(title.text).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color))
            .mockAnchor(item.id)

        case .sos(let hint):
            let progress = isTarget ? player.holdProgress : 0
            ZStack {
                Circle().fill(SettingsTint.sos.opacity(0.18)).frame(width: 128, height: 128)
                Circle().trim(from: 0, to: progress)
                    .stroke(SettingsTint.sos, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 120)
                Circle().fill(SettingsTint.sos).frame(width: 106, height: 106)
                    .overlay(VStack(spacing: 2) {
                        Text("SOS").font(.system(size: 28, weight: .black))
                        Text(hint.text).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 10)
                    }.foregroundStyle(.white))
            }
            .frame(maxWidth: .infinity)
            .mockAnchor(item.id)

        case .row(let icon, let color, let title, let sub, let trailing):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7).fill(color).frame(width: 28, height: 28)
                    .overlay(Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.text).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.appInk).lineLimit(1).minimumScaleFactor(0.7)
                    if let sub { Text(sub.text).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 4)
                trailingView(trailing)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.06)))
            .mockAnchor(item.id)

        case .card(let icon, let color, let title, let sub):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(color).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.text).font(.system(size: 13, weight: .bold)).foregroundStyle(fg).lineLimit(2)
                    if let sub { Text(sub.text).font(.system(size: 11)).foregroundStyle(onLight ? .secondary : Color.white.opacity(0.85)).lineLimit(3) }
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(color.opacity(onLight ? 0.12 : 0.3)))
            .mockAnchor(item.id)

        case .field(let icon, let placeholder, let text):
            let full = text?.text ?? ""
            let shown: String = {
                if case .type(let id) = gesture, id == item.id { return String(full.prefix(player.typed)) }
                return full
            }()
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.secondary)
                Text(shown.isEmpty ? placeholder.text : shown)
                    .font(.system(size: 13))
                    .foregroundStyle(shown.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
                if isTarget, case .type = gesture, player.typed < full.count {
                    Rectangle().fill(tint).frame(width: 1.5, height: 15)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
            .mockAnchor(item.id)

        case .chips(let chips, let selected):
            HStack(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { i, chip in
                    Text(chip.text)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(i == selected ? tint : Color(.tertiarySystemFill)))
                        .foregroundStyle(i == selected ? .white : .primary)
                        .scaleEffect(gesture.target == "\(item.id).\(i)" && player.pressing ? 0.9 : 1)
                        .mockAnchor("\(item.id).\(i)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .map(let pins):
            GeometryReader { geo in
                ZStack {
                    LinearGradient(colors: [Color(red: 0.86, green: 0.92, blue: 0.86), Color(red: 0.83, green: 0.89, blue: 0.94)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: geo.size.height * 0.62))
                        p.addCurve(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.35),
                                   control1: CGPoint(x: geo.size.width * 0.35, y: geo.size.height * 0.75),
                                   control2: CGPoint(x: geo.size.width * 0.6, y: geo.size.height * 0.2))
                        p.move(to: CGPoint(x: geo.size.width * 0.3, y: 0))
                        p.addLine(to: CGPoint(x: geo.size.width * 0.45, y: geo.size.height))
                    }
                    .stroke(Color.white, lineWidth: 6)
                    ForEach(Array(pins.enumerated()), id: \.offset) { i, pin in
                        ZStack {
                            if pin.alert {
                                Circle().fill(SettingsTint.sos.opacity(0.25)).frame(width: 40, height: 40)
                            }
                            Circle().fill(pin.color).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                            Text(pin.initial.text).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        }
                        .position(x: geo.size.width * pin.x, y: geo.size.height * pin.y)
                    }
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                // Pins as targets
                GeometryReader { geo in
                    ForEach(Array(pins.enumerated()), id: \.offset) { i, pin in
                        Color.clear.frame(width: 26, height: 26)
                            .mockAnchor("\(item.id).\(i)")
                            .position(x: geo.size.width * pin.x, y: geo.size.height * pin.y)
                    }
                }
            }
            .mockAnchor(item.id)

        case .button(let title, let color, let filled):
            Text(title.text)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(filled ? (color == .white ? Color.black : .white) : color)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(filled ? color : color.opacity(0.12)))
                .mockAnchor(item.id)

        case .countdown(let title, let seconds, let color):
            CountdownView(title: title.text, seconds: seconds, color: color, light: onLight)
                .mockAnchor(item.id)

        case .code(let code):
            Text(code.text)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .kerning(4)
                .foregroundStyle(Color.appInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .mockAnchor(item.id)

        case .note(let note):
            Text(note.text)
                .font(.system(size: 11))
                .foregroundStyle(onLight ? .secondary : Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .mockAnchor(item.id)

        case .rounds(let rounds):
            HStack(alignment: .top) {
                ForEach(Array(rounds.enumerated()), id: \.offset) { i, r in
                    VStack(spacing: 5) {
                        Circle().fill(r.color).frame(width: 52, height: 52)
                            .overlay(Image(systemName: r.icon).font(.system(size: 21, weight: .semibold)).foregroundStyle(.white))
                            .scaleEffect(gesture.target == "\(item.id).\(i)" && player.pressing ? 0.88 : 1)
                            .mockAnchor("\(item.id).\(i)")
                        Text(r.label.text).font(.system(size: 10, weight: .medium)).foregroundStyle(fg)
                            .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

        case .lockCard(let title, let sub, let buttons):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.fill").font(.system(size: 12)).foregroundStyle(SettingsTint.safe)
                    Text(title.text).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(sub.text).font(.system(size: 11)).opacity(0.85).lineLimit(2)
                HStack(spacing: 6) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { i, b in
                        Text(b.text)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(i == 0 ? SettingsTint.sos : Color.white.opacity(0.22)))
                            .scaleEffect(gesture.target == "\(item.id).\(i)" && player.pressing ? 0.9 : 1)
                            .mockAnchor("\(item.id).\(i)")
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.35)))
            .mockAnchor(item.id)
        }
    }

    @ViewBuilder private func trailingView(_ t: MockItem.Trailing) -> some View {
        switch t {
        case .none: EmptyView()
        case .chevron: Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
        case .toggle(let on):
            Capsule().fill(on ? SettingsTint.safe : Color(.systemFill)).frame(width: 38, height: 23)
                .overlay(Circle().fill(.white).padding(2).offset(x: on ? 7.5 : -7.5))
        case .value(let v): Text(v.text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        case .check: Image(systemName: "checkmark.circle.fill").foregroundStyle(SettingsTint.safe)
        }
    }
}

/// Counts down once per second from `seconds` while on screen
private struct CountdownView: View {
    let title: String
    let seconds: Int
    let color: Color
    let light: Bool
    @State private var left: Int = 0

    var body: some View {
        VStack(spacing: 2) {
            Text("\(left)")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText(countsDown: true))
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(light ? Color.appInk : .white)
                .multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .task {
            left = seconds
            while left > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                withAnimation { left -= 1 }
            }
        }
    }
}
