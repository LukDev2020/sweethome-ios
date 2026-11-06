import SwiftUI

// MARK: - Protected Person Tab Container
//
// Wraps all Protected Person screens in a TabView.
// Home is the default tab.
// The system places the tab bar (side on iPhone Duo, top/sidebar on iPad).

struct ProtectedTabView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    @AppStorage("protected_selected_tab") private var selectedTab = 0
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage(HomeStyle.storageKey) private var homeStyle = HomeStyle.standard.rawValue

    private var tabs: [DuoTabItem] {
        if homeStyle == HomeStyle.simple.rawValue {
            // Simple: three tabs; the home draws its own large SOS
            return [
                DuoTabItem(id: 0, title: lang.localized("tab.home"),     icon: "shield.fill",       view: AnyView(SimpleProtectedHomeView()), placesOwnAccessory: true),
                DuoTabItem(id: 1, title: lang.localized("tab.family"),   icon: "heart.text.square", view: AnyView(FamilyFeedView()), placesOwnAccessory: true),
                DuoTabItem(id: 4, title: lang.localized("tab.settings"), icon: "gearshape",         view: AnyView(ProtectedSettingsView().floatingSOSClearance())),
            ]
        }
        return [
            DuoTabItem(id: 0, title: lang.localized("tab.home"),     icon: "shield.fill",            view: AnyView(ProtectedHomeView().floatingSOSClearance())),
            DuoTabItem(id: 1, title: lang.localized("tab.family"),   icon: "heart.text.square",      view: AnyView(FamilyFeedView()), placesOwnAccessory: true),
            DuoTabItem(id: 2, title: lang.localized("tab.coverage"), icon: "globe.americas",         view: AnyView(ProtectedCoverageView().floatingSOSClearance())),
            DuoTabItem(id: 3, title: lang.localized("tab.records"),  icon: "clock.arrow.circlepath", view: AnyView(ProtectedRecordsView().floatingSOSClearance())),
            DuoTabItem(id: 4, title: lang.localized("tab.settings"), icon: "gearshape",              view: AnyView(ProtectedSettingsView().floatingSOSClearance())),
        ]
    }

    var body: some View {
        DuoAdaptiveTabContainer(
            selectedTab: $selectedTab,
            tabs: tabs,
            tintColor: safe,
            // Persistent SOS button — always accessible, never covers content
            bottomAccessory: AnyView(FloatingSOSButton())
        )
        // One place presents the SOS screen for every trigger path (floating
        // button, home slider, widget, lock screen, dead-man switch…)
        .onChange(of: homeStyle) { _, style in
            // Tabs 2 and 3 don't exist in the simple style
            if style == HomeStyle.simple.rawValue, selectedTab == 2 || selectedTab == 3 { selectedTab = 0 }
        }
        .sheet(isPresented: $coordinator.isSOSScreenPresented) {
            SOSActiveView()
                .environmentObject(coordinator)
        }
    }
}
