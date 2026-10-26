import SwiftUI

// MARK: - Protected Person Tab Container
//
// Wraps all Protected Person screens in a TabView.
// Home is the default tab.
// On Duo inner screen, switches to vertical rail layout.

struct ProtectedTabView: View {
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    @AppStorage("debug_selected_tab") private var selectedTab = 0
    @ObservedObject private var lang = LanguageManager.shared

    private var tabs: [DuoTabItem] {
        [
            DuoTabItem(id: 0, title: lang.localized("tab.home"),     icon: "shield.fill",            view: AnyView(ProtectedHomeView())),
            DuoTabItem(id: 1, title: lang.localized("tab.family"),   icon: "heart.text.square",      view: AnyView(FamilyFeedView())),
            DuoTabItem(id: 2, title: lang.localized("tab.coverage"), icon: "globe.americas",         view: AnyView(ProtectedCoverageView())),
            DuoTabItem(id: 3, title: lang.localized("tab.records"),  icon: "clock.arrow.circlepath", view: AnyView(ProtectedRecordsView())),
            DuoTabItem(id: 4, title: lang.localized("tab.settings"), icon: "gearshape",              view: AnyView(ProtectedSettingsView())),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DuoAdaptiveTabContainer(
                selectedTab: $selectedTab,
                tabs: tabs,
                tintColor: safe
            )

            // Persistent floating SOS button — always accessible
            FloatingSOSButton()
                .padding(.trailing, 20)
                .padding(.bottom, 96)
        }
    }
}
