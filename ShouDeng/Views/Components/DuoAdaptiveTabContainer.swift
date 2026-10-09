import SwiftUI

// MARK: - Duo Adaptive Tab Container
//
// Switches between native bottom TabView (compact) and
// vertical rail layout (regular) based on horizontal size class.
// compact = all standard iPhones + Duo outer screen
// regular = Duo inner screen (unfolded)

struct DuoAdaptiveTabContainer: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var selectedTab: Int
    let tabs: [DuoTabItem]
    let tintColor: Color
    var showInviteButton: Bool = false
    var onInvite: (() -> Void)? = nil

    var body: some View {
        if sizeClass == .regular {
            // Duo inner screen: content + vertical rail on right
            HStack(spacing: 0) {
                if let tab = tabs.first(where: { $0.id == selectedTab }) {
                    tab.view
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VerticalTabRail(
                    selectedTab: $selectedTab,
                    tabs: tabs,
                    showInviteButton: showInviteButton,
                    onInvite: onInvite
                )
            }
        } else {
            // Standard phone: native bottom TabView
            TabView(selection: $selectedTab) {
                ForEach(tabs) { tab in
                    tab.view
                        .tabItem {
                            Image(systemName: tab.icon)
                            Text(tab.title)
                        }
                        .tag(tab.id)
                }
            }
            .tint(tintColor)
        }
    }
}
