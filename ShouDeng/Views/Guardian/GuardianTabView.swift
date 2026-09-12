import SwiftUI

// MARK: - Guardian Tab Container
//
// Wraps all Guardian screens in a TabView.
// Tabs: Home, Family Feed, Records (timeline + schedule), Settings

struct GuardianTabView: View {
    @State private var selectedTab = 0  // DEV: change to test different tabs (0=home, 1=feed, 2=records, 3=settings)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    var body: some View {
        TabView(selection: $selectedTab) {
            GuardianHomeView()
                .tabItem {
                    Image(systemName: "eye.fill")
                    Text("首页")
                }
                .tag(0)

            FamilyFeedView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("家庭圈")
                }
                .tag(1)

            GuardianRecordsView()
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("记录")
                }
                .tag(2)

            GuardianSettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("设置")
                }
                .tag(3)
        }
        .tint(pro)
    }
}
