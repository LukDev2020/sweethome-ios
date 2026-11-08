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
        if coordinator.isRiderMode {
            // Rider: the home draws its own large SOS; Crew replaces Coverage
            return [
                DuoTabItem(id: 0, title: lang.localized("tab.home"),     icon: "bicycle",           view: AnyView(RiderHomeView()), placesOwnAccessory: true),
                DuoTabItem(id: 5, title: lang.localized("rider.tab.crew"), icon: "person.3.fill",   view: AnyView(CrewView().floatingSOSClearance())),
                DuoTabItem(id: 1, title: lang.localized("tab.family"),   icon: "heart.text.square", view: AnyView(FamilyFeedView()), placesOwnAccessory: true),
                DuoTabItem(id: 4, title: lang.localized("tab.settings"), icon: "gearshape",         view: AnyView(ProtectedSettingsView().floatingSOSClearance())),
            ]
        }
        if coordinator.effectiveHomeStyle == HomeStyle.simple.rawValue {
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
        // A different set of tabs (rider / simple / standard): build the tab bar anew —
        // reusing it kept the old content of a tab with the same id (blank Crew tab)
        .id("\(coordinator.effectiveHomeStyle)-\(homeStyle)")
        // One place presents the SOS screen for every trigger path (floating
        // button, home slider, widget, lock screen, dead-man switch…)
        .onChange(of: homeStyle) { _, style in
            // Tabs 2 and 3 don't exist in the simple style, tab 3 not in the rider style
            if style == HomeStyle.simple.rawValue, selectedTab == 2 || selectedTab == 3 { selectedTab = 0 }
            if style == HomeStyle.rider.rawValue, selectedTab == 2 || selectedTab == 3 { selectedTab = 0 }
            if style != HomeStyle.rider.rawValue, selectedTab == 5 { selectedTab = 0 }
        }
        // Rider mode: a crew mate's SOS (push tap), bike report (lock screen), crew QR code
        .sheet(isPresented: Binding(get: { coordinator.pendingCrewAlertId != nil },
                                    set: { if !$0 { coordinator.pendingCrewAlertId = nil } })) {
            CrewAlertView(sosEventId: coordinator.pendingCrewAlertId ?? "")
                .environmentObject(coordinator)
        }
        // Watch back: a guardian I watch called SOS
        .sheet(isPresented: Binding(get: { coordinator.pendingAlertPersonId != nil },
                                    set: { if !$0 { coordinator.pendingAlertPersonId = nil } })) {
            if let personId = coordinator.pendingAlertPersonId {
                NavigationStack { GuardianAlertResponseView(personId: personId) }
                    .environmentObject(coordinator)
            }
        }
        .sheet(isPresented: $coordinator.showBikeReport) {
            BikeReportView().environmentObject(coordinator)
        }
        // "I've crashed": rider home, lock-screen card
        .sheet(isPresented: $coordinator.showCrashReport) {
            CrashReportView().environmentObject(coordinator)
        }
        .sheet(isPresented: Binding(get: { coordinator.pendingCrewCode != nil && coordinator.isRiderMode && !coordinator.showRiderSetup },
                                    set: { if !$0 { coordinator.pendingCrewCode = nil } })) {
            CrewJoinSheet(initialCode: coordinator.pendingCrewCode ?? "")
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $coordinator.isSOSScreenPresented) {
            SOSActiveView()
                .environmentObject(coordinator)
        }
    }
}
