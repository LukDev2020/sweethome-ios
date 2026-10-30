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
    /// Persistent control pinned above the tab bar (the SOS button). It is laid
    /// out in each tab's bottom safe-area inset so scroll content can always be
    /// scrolled clear of it instead of sitting underneath it.
    var bottomAccessory: AnyView? = nil

    var body: some View {
        if sizeClass == .regular {
            // Duo inner screen: content + vertical rail on right
            HStack(spacing: 0) {
                if let tab = tabs.first(where: { $0.id == selectedTab }) {
                    tab.view
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaInset(edge: .bottom, spacing: 0) { accessoryBar }
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
                        .safeAreaInset(edge: .bottom, spacing: 0) { accessoryBar }
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

    @ViewBuilder
    private var accessoryBar: some View {
        if let bottomAccessory {
            HStack {
                Spacer()
                bottomAccessory
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
            .background {
                // Opaque strip (soft top edge): content scrolls *behind* it like a
                // bar, so a card is never half-covered by the button at rest.
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 14)
                    Color(.systemBackground)
                }
                .allowsHitTesting(false)
            }
        }
    }
}
