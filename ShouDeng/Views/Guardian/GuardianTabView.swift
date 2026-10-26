import SwiftUI

// MARK: - Guardian Tab Container
//
// Wraps all Guardian screens in a TabView.
// Tabs: Home, Family Feed, Records (timeline + schedule), Settings
// On Duo inner screen, switches to vertical rail layout.

struct GuardianTabView: View {
    @AppStorage("debug_selected_tab") private var selectedTab = 0
    @State private var showInvite = false
    @ObservedObject private var lang = LanguageManager.shared
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    private var tabs: [DuoTabItem] {
        [
            DuoTabItem(id: 0, title: lang.localized("tab.home"),     icon: "eye.fill",                       view: AnyView(GuardianHomeView())),
            DuoTabItem(id: 1, title: lang.localized("tab.family"),   icon: "bubble.left.and.bubble.right",    view: AnyView(FamilyFeedView())),
            DuoTabItem(id: 2, title: lang.localized("tab.records"),  icon: "clock.arrow.circlepath",          view: AnyView(GuardianRecordsView())),
            DuoTabItem(id: 3, title: lang.localized("tab.settings"), icon: "gearshape",                       view: AnyView(GuardianSettingsView())),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DuoAdaptiveTabContainer(
                selectedTab: $selectedTab,
                tabs: tabs,
                tintColor: pro,
                showInviteButton: true,
                onInvite: { showInvite = true }
            )
            .sheet(isPresented: $showInvite) {
                InviteGuardianView()
            }

            // Persistent floating SOS button — always accessible
            FloatingSOSButton()
                .padding(.trailing, 20)
                .padding(.bottom, 96)
        }
    }
}
