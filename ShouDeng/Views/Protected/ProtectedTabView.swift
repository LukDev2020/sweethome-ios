import SwiftUI

// MARK: - Protected Person Tab Container
//
// Wraps all Protected Person screens in a TabView.
// Home is the default tab.
// On Duo inner screen, switches to vertical rail layout.

struct ProtectedTabView: View {
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    @AppStorage("debug_selected_tab") private var selectedTab = 0

    private var tabs: [DuoTabItem] {
        [
            DuoTabItem(id: 0, title: "首页",   icon: "shield.fill",            view: AnyView(ProtectedHomeView())),
            DuoTabItem(id: 1, title: "家庭圈", icon: "heart.text.square",      view: AnyView(FamilyFeedView())),
            DuoTabItem(id: 2, title: "覆盖",   icon: "globe.americas",         view: AnyView(ProtectedCoverageView())),
            DuoTabItem(id: 3, title: "记录",   icon: "clock.arrow.circlepath", view: AnyView(ProtectedRecordsView())),
            DuoTabItem(id: 4, title: "设置",   icon: "gearshape",              view: AnyView(ProtectedSettingsView())),
        ]
    }

    var body: some View {
        DuoAdaptiveTabContainer(
            selectedTab: $selectedTab,
            tabs: tabs,
            tintColor: safe
        )
    }
}
