import SwiftUI
import TipKit

// MARK: - In-app tips (TipKit)
//
// Short, one-time hints in the real app — not the step-by-step Explore Mode tour.
// Rules:
//  - each tip shows once, where it is relevant, and closes for good when used or dismissed;
//  - the SOS tip comes first; the others wait until it has been seen, so tips never pile up;
//  - nothing is shown in Explore Mode (it has its own tour), during an SOS or its countdown;
//  - Settings can switch all tips off, or show them again (applied at next launch).

enum AppTips {
    private static let enabledKey = "tips.enabled"
    private static let resetKey = "tips.resetPending"

    /// Mirrors Settings → Tips; every tip's rules check it, so turning it off hides them at once.
    @Parameter static var enabled: Bool = true
    /// True once the SOS tip has been closed or used: the other tips wait for it.
    @Parameter static var sosTipDone: Bool = false

    static var isEnabledSetting: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Call once at launch, before any tip is shown.
    static func configure() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: resetKey) {
            try? Tips.resetDatastore()
            defaults.set(false, forKey: resetKey)
        }
        try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
        enabled = isEnabledSetting
        Task { @MainActor in
            for await status in SOSHoldTip().statusUpdates {
                if case .invalidated = status { sosTipDone = true }
            }
        }
    }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: enabledKey)
        enabled = on
    }

    /// Tips come back the next time the app opens (TipKit resets only before it starts).
    static func showAgainOnNextLaunch() {
        UserDefaults.standard.set(true, forKey: resetKey)
        setEnabled(true)
    }

    /// The tip to attach, or nil where tips must not appear.
    /// Generic (not `any Tip`) so the iOS 17 `popoverTip` overload is used.
    static func available<T: Tip>(_ tip: T) -> T? {
        ExploreMode.isActive ? nil : tip
    }

    fileprivate static func text(_ key: String) -> Text {
        Text(LanguageManager.shared.localized(key))
    }
}

/// Everyone: hold the SOS button.
struct SOSHoldTip: Tip {
    var title: Text { AppTips.text("tip.sos.title") }
    var message: Text? { AppTips.text("tip.sos.message") }
    var image: Image? { Image(systemName: "hand.tap.fill") }
    var rules: [Rule] { #Rule(AppTips.$enabled) { $0 } }
}

/// Protected person: Home Safe.
struct HomeSafeTip: Tip {
    var title: Text { AppTips.text("tip.homeSafe.title") }
    var message: Text? { AppTips.text("tip.homeSafe.message") }
    var image: Image? { Image(systemName: "house.fill") }
    var rules: [Rule] {
        #Rule(AppTips.$enabled) { $0 }
        #Rule(AppTips.$sosTipDone) { $0 }
    }
}

/// Protected person with nobody watching over them yet.
struct InviteGuardianTip: Tip {
    var title: Text { AppTips.text("tip.inviteGuardian.title") }
    var message: Text? { AppTips.text("tip.inviteGuardian.message") }
    var image: Image? { Image(systemName: "person.badge.plus") }
    var actions: [Action] { [Action(id: "invite", title: LanguageManager.shared.localized("tip.inviteGuardian.action"))] }
    var rules: [Rule] { #Rule(AppTips.$enabled) { $0 } }
}

/// Guardian: tap a family member's card.
struct MemberCardTip: Tip {
    var title: Text { AppTips.text("tip.memberCard.title") }
    var message: Text? { AppTips.text("tip.memberCard.message") }
    var image: Image? { Image(systemName: "person.crop.circle") }
    var rules: [Rule] {
        #Rule(AppTips.$enabled) { $0 }
        #Rule(AppTips.$sosTipDone) { $0 }
    }
}

/// Guardian: the status bar turned yellow or red.
struct StatusBarTip: Tip {
    var title: Text { AppTips.text("tip.statusBar.title") }
    var message: Text? { AppTips.text("tip.statusBar.message") }
    var image: Image? { Image(systemName: "bell.badge.fill") }
    var rules: [Rule] { #Rule(AppTips.$enabled) { $0 } }
}

/// Family circle: enter an invite code.
struct InviteCodeTip: Tip {
    var title: Text { AppTips.text("tip.inviteCode.title") }
    var message: Text? { AppTips.text("tip.inviteCode.message") }
    var image: Image? { Image(systemName: "key.fill") }
    var rules: [Rule] {
        #Rule(AppTips.$enabled) { $0 }
        #Rule(AppTips.$sosTipDone) { $0 }
    }
}

// MARK: - Popover helper

extension View {
    /// `popoverTip` that compiles for iOS 17: the iOS 26 SDK's preferred overload is
    /// iOS 26+, so older systems call the original iOS 17 one explicitly.
    @ViewBuilder
    func appTip<T: Tip>(_ tip: T?, arrowEdge: Edge) -> some View {
        if #available(iOS 26.0, *) {
            popoverTip(tip, arrowEdge: arrowEdge)
        } else if let tip {
            popoverTip(tip, arrowEdge: arrowEdge)
        } else {
            self
        }
    }
}

// MARK: - Settings

/// Settings → Tips: on/off, and show them again.
struct TipsSettingsPanel: View {
    @ObservedObject private var lang = LanguageManager.shared
    @State private var enabled = AppTips.isEnabledSetting
    @State private var showResetDone = false
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.localized("settings.tips.section"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                Text(lang.localized("settings.tips.show")).font(.scaled(size: 13))
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .tint(safe)
                    .onChange(of: enabled) { _, on in AppTips.setEnabled(on) }
            }
            .padding(.vertical, 2)
            Button {
                AppTips.showAgainOnNextLaunch()
                enabled = true
                showResetDone = true
            } label: {
                HStack {
                    Text(lang.localized("settings.tips.reset")).font(.scaled(size: 13))
                    Spacer()
                    Image(systemName: "arrow.counterclockwise").font(.scaled(size: 12))
                }
                .foregroundStyle(safe)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .alert(lang.localized("settings.tips.resetDone"), isPresented: $showResetDone) {
            Button(lang.localized("settings.action.ok")) {}
        }
    }
}
