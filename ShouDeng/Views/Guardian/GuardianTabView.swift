import SwiftUI

// MARK: - Guardian Tab Container
//
// Wraps all Guardian screens in a TabView.
// Tabs: Home, Family Feed, Records (timeline + schedule), Settings
// On Duo inner screen, switches to vertical rail layout.

struct GuardianTabView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage("guardian_selected_tab") private var selectedTab = 0
    @State private var showInvite = false
    @ObservedObject private var lang = LanguageManager.shared
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    private var tabs: [DuoTabItem] {
        [
            DuoTabItem(id: 0, title: lang.localized("tab.home"),     icon: "eye.fill",                       view: AnyView(GuardianHomeView().floatingSOSClearance())),
            DuoTabItem(id: 1, title: lang.localized("tab.family"),   icon: "bubble.left.and.bubble.right",    view: AnyView(FamilyFeedView()), placesOwnAccessory: true),
            DuoTabItem(id: 2, title: lang.localized("tab.records"),  icon: "clock.arrow.circlepath",          view: AnyView(GuardianRecordsView().floatingSOSClearance())),
            DuoTabItem(id: 3, title: lang.localized("tab.settings"), icon: "gearshape",                       view: AnyView(GuardianSettingsView().floatingSOSClearance())),
        ]
    }

    var body: some View {
        DuoAdaptiveTabContainer(
            selectedTab: $selectedTab,
            tabs: tabs,
            tintColor: pro,
            showInviteButton: true,
            onInvite: { showInvite = true },
            // Persistent SOS button — always accessible, never covers content
            bottomAccessory: AnyView(FloatingSOSButton())
        )
        .sheet(isPresented: $showInvite) {
            InviteGuardianView()
        }
        // An SOS push was opened: straight to that person's response screen
        .sheet(isPresented: Binding(
            get: { coordinator.pendingAlertPersonId != nil },
            set: { if !$0 { coordinator.pendingAlertPersonId = nil } }
        )) {
            if let personId = coordinator.pendingAlertPersonId {
                NavigationStack {
                    GuardianAlertResponseView(personId: personId)
                }
                .environmentObject(coordinator)
            }
        }
        // The guardian's own SOS (floating button)
        .sheet(isPresented: $coordinator.isSOSScreenPresented) {
            SOSActiveView().environmentObject(coordinator)
        }
    }
}
