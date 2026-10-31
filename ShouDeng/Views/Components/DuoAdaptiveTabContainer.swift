import SwiftUI

// MARK: - Duo Adaptive Tab Container
//
// The system TabView at every width. iOS places the bar: bottom on an iPhone, at the
// side on the iPhone Duo outer screen and on the inner screen in landscape, top or
// sidebar on iPad. A custom bar would not move with it.
//
// The same view tree is used for compact and regular widths: folding or unfolding an
// iPhone Duo changes the size class on the same scene, and switching between two
// different containers rebuilt every tab — losing typed text, the selected person and
// scroll positions. The screens themselves pick their one- or two-pane layout.

struct DuoAdaptiveTabContainer: View {
    @Binding var selectedTab: Int
    let tabs: [DuoTabItem]
    let tintColor: Color
    /// Persistent control pinned above the tab bar (the SOS button). It is laid
    /// out in each tab's bottom safe-area inset so scroll content can always be
    /// scrolled clear of it instead of sitting underneath it.
    var bottomAccessory: AnyView? = nil

    var body: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                ForEach(tabs) { tab in
                    Tab(tab.title, systemImage: tab.icon, value: tab.id) {
                        withAccessory(tab)
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tint(tintColor)
        } else {
            TabView(selection: $selectedTab) {
                ForEach(tabs) { tab in
                    withAccessory(tab)
                        .tabItem { Label(tab.title, systemImage: tab.icon) }
                        .tag(tab.id)
                }
            }
            .tint(tintColor)
        }
    }

    @ViewBuilder
    private func withAccessory(_ tab: DuoTabItem) -> some View {
        if tab.placesOwnAccessory {
            tab.view.environment(\.tabBottomAccessory, bottomAccessory)
        } else {
            tab.view.safeAreaInset(edge: .bottom, spacing: 0) { accessoryBar }
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
