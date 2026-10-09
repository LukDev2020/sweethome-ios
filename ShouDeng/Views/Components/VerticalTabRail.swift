import SwiftUI

// MARK: - Vertical Tab Rail (Duo Inner Screen)
//
// 68pt-wide vertical strip on the right edge of the unfolded inner screen.
// Design reference: vela-iphone-duo design spec.

struct VerticalTabRail: View {
    @Binding var selectedTab: Int
    let tabs: [DuoTabItem]
    var showInviteButton: Bool = false
    var onInvite: (() -> Void)? = nil

    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    var body: some View {
        VStack(spacing: 0) {
            // Camera dot indicator
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: 10, height: 10)
                .padding(.top, 12)

            // Invite button (guardian role only)
            if showInviteButton {
                Button {
                    onInvite?()
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(lamp)
                        .frame(width: 44, height: 44)
                }
                .padding(.top, 12)
            }

            Spacer()

            // Tab buttons in capsule container
            VStack(spacing: 4) {
                ForEach(tabs) { tab in
                    Button {
                        selectedTab = tab.id
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(selectedTab == tab.id ? inkDeep : .white.opacity(0.5))
                            .frame(width: 52, height: 52)
                            .background(
                                selectedTab == tab.id
                                    ? lamp
                                    : Color.clear
                            )
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                Capsule()
                    .fill(.white.opacity(0.08))
            )

            Spacer()
        }
        .frame(width: 68)
        .background(inkDeep)
    }
}
