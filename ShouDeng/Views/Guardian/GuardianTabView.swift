import SwiftUI

// MARK: - Guardian Tab Container
//
// Wraps all Guardian screens in a TabView.
// Tabs: Home, Family Feed, Records (timeline + schedule), Settings

struct GuardianTabView: View {
    var body: some View {
        TabView {
            GuardianHomeView()
                .tabItem {
                    Image(systemName: "eye.fill")
                    Text("首页")
                }

            FamilyFeedView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("家庭圈")
                }

            GuardianRecordsView()
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("记录")
                }

            GuardianSettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("设置")
                }
        }
    }
}
