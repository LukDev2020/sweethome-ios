import SwiftUI

// MARK: - Protected Person Tab Container
//
// Wraps all Protected Person screens in a TabView.
// Home is the default tab.

struct ProtectedTabView: View {
    var body: some View {
        TabView {
            ProtectedHomeView()
                .tabItem {
                    Image(systemName: "shield.fill")
                    Text("首页")
                }

            FamilyFeedView()
                .tabItem {
                    Image(systemName: "heart.text.square")
                    Text("家庭圈")
                }

            ProtectedRecordsView()
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("记录")
                }

            ProtectedSettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("设置")
                }
        }
    }
}
