import SwiftUI

// MARK: - Protected Person Tab Container
//
// Wraps all Protected Person screens in a TabView.
// Home is the default tab.
// On Duo inner screen, switches to vertical rail layout.

struct ProtectedTabView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    @AppStorage("protected_selected_tab") private var selectedTab = 0
    @ObservedObject private var lang = LanguageManager.shared

    private var tabs: [DuoTabItem] {
        [
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
        .sheet(isPresented: $coordinator.isSOSScreenPresented) {
            SOSActiveView()
                .environmentObject(coordinator)
        }
    }
}
