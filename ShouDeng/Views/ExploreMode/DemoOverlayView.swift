import SwiftUI

// MARK: - Explore Mode overlay (separate pass-through window, above sheets)
//
//   - coach-mark spotlight + tip card (Back / Next / Try it, step dots)
//   - in-app DEMO notification banner (never a real UNNotification)
//   - "Meanwhile in Toronto…" hand-off
//   - progress checklist → "Set up my real family"

struct DemoOverlayView: View {
    @EnvironmentObject var explore: ExploreModeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if explore.showHandoff {
                    DemoHandoffView()
                        .overlayRegion("handoff")
                        .transition(.opacity)
                } else if explore.showChecklist {
                    DemoChecklistView()
                        .overlayRegion("checklist")
                        .transition(.move(edge: .bottom))
                } else if explore.isTourVisible, let step = explore.currentStep {
                    DemoTipLayer(step: step, screen: geo.size, column: Self.cardColumn(in: geo, window: explore.overlayWindow),
                                 safeTop: geo.safeAreaInsets.top, safeBottom: geo.safeAreaInsets.bottom)
                }

                VStack(spacing: 8) {
                    if let n = explore.notification {
                        DemoNotificationBanner(notification: n)
                            .overlayRegion("banner")
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                    if let feature = explore.blockedFeature {
                        Text(String(format: LanguageManager.shared.localized("explore.blocked"),
                                    Self.featureName(feature)))
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Color.black.opacity(0.8)))
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
                .padding(.top, geo.safeAreaInsets.top + 52)
                .padding(.leading, (explore.overlayWindow?.safeAreaInsets.left ?? 0) + 12)
                .padding(.trailing, (explore.overlayWindow?.safeAreaInsets.right ?? 0) + 12)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: explore.notification)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: explore.showChecklist)
        }
        .ignoresSafeArea()
    }
}

extension DemoOverlayView {
    /// Where the tip card may go: inside the side safe areas (the iPhone Duo puts the
    /// status bar and tab bar at the side), and past the fold when the screen is unfolded.
    /// The overlay ignores the safe area, so its GeometryProxy reports no insets: the
    /// side ones come from the overlay window.
    static func cardColumn(in geo: GeometryProxy, window: UIWindow?) -> ClosedRange<CGFloat> {
        let insets = window?.safeAreaInsets ?? .zero
        let start = insets.left
        let end = max(start, geo.size.width - insets.right)
        let split = FoldSplitLayout.resolve(width: geo.size.width, division: FoldSplitLayout.division(in: geo))
        if split.followsFold, split.leading + split.gap < end {
            return max(start, split.leading + split.gap)...end
        }
        return start...end
    }

    /// Biometrics is named after this device's kind (Face ID, Touch ID — iPhone Duo has
    /// no Face ID — or Optic ID).
    static func featureName(_ feature: String) -> String {
        feature == "biometrics"
            ? BiometricAuthManager.shared.biometricName
            : LanguageManager.shared.localized("explore.feature.\(feature)")
    }
}

// MARK: - Spotlight + tip card

private struct DemoTipLayer: View {
    @EnvironmentObject var explore: ExploreModeController
    let step: DemoTourStep
    let screen: CGSize
    /// Horizontal range the card stays within (see DemoOverlayView.cardColumn).
    let column: ClosedRange<CGFloat>
    let safeTop: CGFloat
    let safeBottom: CGFloat
    @State private var collapsed = false
    /// Collapsed because the app showed a sheet/alert (re-expands when it closes).
    @State private var autoCollapsed = false
    /// The person chose "Hide tips": drop the highlight ring too (it stays for "Try it").
    @State private var hiddenByUser = false
    @AccessibilityFocusState private var titleFocused: Bool
    /// Live drag of the "Show tip" button
    @GestureState private var tipDrag: CGSize = .zero

    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let ink = Color(red: 13/255, green: 52/255, blue: 99/255)

    private var anchor: CGRect? {
        step.anchor.flatMap { explore.anchorFrames[$0] }.flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let anchor, !collapsed {
                // Dim everything except the real control (visual only — taps pass through)
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: screen))
                    p.addRoundedRect(in: anchor.insetBy(dx: -6, dy: -6), cornerSize: CGSize(width: 14, height: 14))
                }
                .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            if let anchor, !hiddenByUser {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(lamp, lineWidth: 3)
                    .frame(width: anchor.width + 12, height: anchor.height + 12)
                    .position(x: anchor.midX, y: anchor.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if collapsed {
                // Hidden while a sheet/alert is up so it never covers the app's own UI.
                if !explore.isAppPresentingModal {
                    Button {
                        collapsed = false
                        autoCollapsed = false
                        hiddenByUser = false
                    } label: {
                        Label(LanguageManager.shared.localized("explore.tip.show"), systemImage: "lightbulb")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(lamp))
                            .foregroundStyle(.black)
                    }
                    // Drag it anywhere; a short tap still shows the tip
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .updating($tipDrag) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                explore.tipButtonOffset = clampedTipOffset(explore.tipButtonOffset + value.translation)
                            }
                    )
                    .overlayRegion("tipShow")
                    .position(tipButtonHome)
                    .offset(explore.tipButtonOffset + tipDrag)
                    .accessibilityHint(LanguageManager.shared.localized("explore.tip.show.moveHint"))
                }
            } else {
                card
                    .frame(width: max(0, min(column.upperBound - column.lowerBound - 32, 520)))
                    .overlayRegion("tipCard")
                    .position(x: (column.lowerBound + column.upperBound) / 2, y: cardCenterY)
            }
        }
        .frame(width: screen.width, height: screen.height)
        .onChange(of: step.id) { _, _ in
            collapsed = explore.isAppPresentingModal
            autoCollapsed = collapsed
            titleFocused = true
        }
        .onChange(of: explore.isAppPresentingModal) { _, presenting in
            // A sheet or alert (e.g. the SOS disclosure) appeared: step aside, come back after.
            if presenting, !collapsed {
                collapsed = true
                autoCollapsed = true
            } else if !presenting, autoCollapsed {
                collapsed = false
                autoCollapsed = false
            }
        }
        .onAppear { titleFocused = true }
    }

    /// Lower left, clear of the SOS button (bottom right) and the tab bar.
    private var tipButtonHome: CGPoint {
        CGPoint(x: column.lowerBound + 80, y: screen.height - safeBottom - 150)
    }

    /// Keeps the dragged button on screen.
    private func clampedTipOffset(_ offset: CGSize) -> CGSize {
        let home = tipButtonHome
        let x = min(max(home.x + offset.width, column.lowerBound + 70), column.upperBound - 70)
        let y = min(max(home.y + offset.height, safeTop + 60), screen.height - safeBottom - 40)
        return CGSize(width: x - home.x, height: y - home.y)
    }

    private let cardHeight: CGFloat = 230

    private var cardCenterY: CGFloat {
        let minY = safeTop + 56 + cardHeight / 2
        let maxY = screen.height - safeBottom - 90 - cardHeight / 2
        guard let anchor else { return maxY }
        let below = anchor.maxY + 14 + cardHeight / 2
        let above = anchor.minY - 14 - cardHeight / 2
        let y = anchor.midY > screen.height / 2 ? above : below
        return min(max(y, minY), maxY)
    }

    private var card: some View {
        let lm = LanguageManager.shared
        let steps = explore.steps
        let idx = explore.currentStepNumber - 1
        let phone = lm.localized(explore.role == .mom ? "explore.phone.mom" : "explore.phone.sarah")
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(format: lm.localized("explore.tip.header"), phone, idx + 1, steps.count).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(lamp)
            Text(lm.localized(step.titleKey))
                .font(.title3.weight(.bold))
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(lm.localized(step.bodyKey))
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i == idx ? lamp : Color.gray.opacity(0.3))
                        .frame(width: i == idx ? 18 : 6, height: 6)
                }
                .accessibilityHidden(true)
                Spacer()
                if idx > 0 {
                    Button(lm.localized("explore.tip.back")) { explore.back() }
                        .font(.subheadline)
                        .foregroundStyle(ink.opacity(0.7))
                }
                Button {
                    if case .tryIt = step.action {
                        collapsed = true // get out of the way of the real control
                    }
                    explore.performPrimary()
                } label: {
                    Text(lm.localized(step.primaryLabelKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(ink))
                }
            }
            Button(lm.localized("explore.tip.hide")) {
                // Collapse to the "Show tips" button so tips can come back.
                collapsed = true
                autoCollapsed = false
                hiddenByUser = true
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - DEMO notification banner

private struct DemoNotificationBanner: View {
    @EnvironmentObject var explore: ExploreModeController
    let notification: DemoNotification

    var body: some View {
        Button {
            explore.tapNotification()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image("AppLogo")
                    .resizable()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.shared.localized("explore.notif.source"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(notification.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(notification.body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint(LanguageManager.shared.localized("explore.notif.hint"))
    }
}

// MARK: - Hand-off: "Meanwhile in Toronto…"

private struct DemoHandoffView: View {
    @EnvironmentObject var explore: ExploreModeController

    var body: some View {
        let lm = LanguageManager.shared
        let t = DemoText(language: lm.current)
        let torontoTime = Self.time(in: "America/Toronto")
        let chengduTime = Self.time(in: "Asia/Shanghai")
        ZStack {
            Color(red: 13/255, green: 22/255, blue: 38/255).opacity(0.96).ignoresSafeArea()
            VStack(spacing: 18) {
                HStack(spacing: 22) {
                    phone(label: "SOS", color: Color(red: 196/255, green: 69/255, blue: 60/255))
                    Image(systemName: "arrow.right").foregroundStyle(.white.opacity(0.6))
                    phone(label: String(t.sarahName.prefix(1)), color: Color(red: 63/255, green: 143/255, blue: 110/255))
                }
                .accessibilityHidden(true)
                Text(String(format: lm.localized("explore.handoff.sent"), t.chengdu, chengduTime).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 232/255, green: 163/255, blue: 61/255))
                Text(String(format: lm.localized("explore.handoff.title"), t.toronto))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(String(format: lm.localized("explore.handoff.body"), torontoTime, t.sarahName))
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                Button {
                    explore.continueToGuardian()
                } label: {
                    Text(String(format: lm.localized("explore.handoff.cta"), t.sarahName))
                        .font(.headline)
                        .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255))
                        .padding(.horizontal, 28).padding(.vertical, 14)
                        .background(Capsule().fill(Color(red: 232/255, green: 163/255, blue: 61/255)))
                }
                Text(lm.localized("explore.handoff.footnote"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(28)
        }
    }

    private func phone(label: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color(red: 232/255, green: 163/255, blue: 61/255), lineWidth: 2)
            .frame(width: 64, height: 110)
            .overlay(Circle().fill(color).frame(width: 40, height: 40)
                .overlay(Text(label).font(.caption.weight(.bold)).foregroundStyle(.white)))
    }

    static func time(in tz: String) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: tz)
        f.timeStyle = .short
        f.dateStyle = .none
        f.locale = Locale(identifier: LanguageManager.shared.current.rawValue)
        return f.string(from: Date())
    }
}

// MARK: - Progress checklist

private struct DemoChecklistView: View {
    @EnvironmentObject var explore: ExploreModeController

    var body: some View {
        let lm = LanguageManager.shared
        let total = DemoLesson.allCases.count
        let done = explore.learned.count
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { explore.showChecklist = false }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Capsule().fill(Color.gray.opacity(0.4)).frame(width: 40, height: 5).frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text(String(format: lm.localized("explore.checklist.title"), done, total))
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                ProgressView(value: Double(done), total: Double(total))
                    .tint(Color(red: 63/255, green: 143/255, blue: 110/255))
                ForEach(DemoLesson.allCases) { lesson in
                    let learned = explore.learned.contains(lesson)
                    HStack {
                        Image(systemName: learned ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(learned ? Color(red: 63/255, green: 143/255, blue: 110/255) : .secondary)
                        Text(lm.localized(lesson.titleKey))
                            .strikethrough(learned)
                            .foregroundStyle(learned ? .secondary : .primary)
                        Spacer()
                        if !learned {
                            Button(lm.localized("explore.checklist.start")) { explore.jump(to: lesson) }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    explore.exit(setUpRealFamily: true)
                } label: {
                    Text(lm.localized("explore.checklist.setup"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 13/255, green: 52/255, blue: 99/255)))
                }
                HStack {
                    Spacer()
                    Button(lm.localized(explore.role == .mom ? "explore.switch.toSarah" : "explore.switch.toMom")) {
                        explore.showChecklist = false
                        explore.switchRole(to: explore.role.other)
                    }
                    Spacer()
                    Button(lm.localized("explore.exit")) { explore.exit() }
                    Spacer()
                }
                .font(.subheadline)
            }
            .padding(20)
            .padding(.bottom, 10)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.systemBackground)))
        }
    }
}

// MARK: - Tappable regions

private extension View {
    /// Reports this view's on-screen frame so the pass-through overlay window
    /// accepts touches here (and only here).
    func overlayRegion(_ id: String) -> some View {
        background {
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onAppear { ExploreModeController.shared.setOverlayRegion(id, frame) }
                    .onChange(of: frame) { _, new in ExploreModeController.shared.setOverlayRegion(id, new) }
                    .onDisappear { ExploreModeController.shared.setOverlayRegion(id, nil) }
            }
        }
    }
}

private func + (a: CGSize, b: CGSize) -> CGSize { CGSize(width: a.width + b.width, height: a.height + b.height) }
