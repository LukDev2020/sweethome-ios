import SwiftUI

// MARK: - Protected Person Tab Container
//
// Wraps all Protected Person screens (A1-A6) in a TabView.
// A1 (Home) is the default tab. A3/A4/A5/A6 are reachable via tabs.

struct ProtectedTabView: View {
    var body: some View {
        TabView {
            ProtectedHomeView()
                .tabItem {
                    Image(systemName: "shield.fill")
                    Text("首页")
                }

            ProtectedRecordsView()
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("记录")
                }

            ProtectedCoverageView()
                .tabItem {
                    Image(systemName: "globe.asia.australia")
                    Text("覆盖")
                }

            ProtectedSettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("设置")
                }
        }
    }
}
