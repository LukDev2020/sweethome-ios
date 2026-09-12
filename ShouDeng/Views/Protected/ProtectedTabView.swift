import SwiftUI

// MARK: - Protected Person Tab Container
//
// Wraps all Protected Person screens in a TabView.
// Home is the default tab.

struct ProtectedTabView: View {
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ProtectedHomeView()
                .tabItem {
                    Image(systemName: "shield.fill")
                    Text("首页")
                }
                .tag(0)

            FamilyFeedView()
                .tabItem {
                    Image(systemName: "heart.text.square")
                    Text("家庭圈")
                }
                .tag(1)

            ProtectedRecordsView()
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("记录")
                }
                .tag(2)

            ProtectedSettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("设置")
                }
                .tag(3)
        }
        .tint(safe)
    }
}
