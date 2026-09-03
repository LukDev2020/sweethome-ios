import SwiftUI

// MARK: - Guardian Tab Container
//
// Wraps all Guardian screens (B1-B6) in a TabView.
// B1 (Home) is the default tab. B4/B5/B6 are reachable via tabs.
// B2 (Alert Response) and B3 (Member Detail) are push-navigated from B1.

struct GuardianTabView: View {
    var body: some View {
        TabView {
            GuardianHomeView()
                .tabItem {
                    Image(systemName: "eye.fill")
                    Text("首页")
                }

            GuardianDutyScheduleView()
                .tabItem {
                    Image(systemName: "calendar.badge.clock")
                    Text("排班")
                }

            GuardianInviteConsentView()
                .tabItem {
                    Image(systemName: "person.badge.plus")
                    Text("邀请")
                }

            GuardianPlanBillingView()
                .tabItem {
                    Image(systemName: "creditcard")
                    Text("方案")
                }
        }
    }
}
