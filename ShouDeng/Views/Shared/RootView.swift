import SwiftUI

struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        Group {
            switch coordinator.userRole {
            case .protected_:
                ProtectedTabView()
            case .guardian:
                GuardianTabView()
            }
        }
        // Dev-only: long press anywhere to switch portal
        .overlay(alignment: .topTrailing) {
            portalSwitcher
        }
    }

    // MARK: - Portal Switcher (development tool)

    private var portalSwitcher: some View {
        Menu {
            Button {
                withAnimation { coordinator.userRole = .protected_ }
            } label: {
                Label("被守护者 · 小雨在基辅", systemImage: "shield.fill")
            }
            Button {
                withAnimation { coordinator.userRole = .guardian }
            } label: {
                Label("守护者 · 妈妈在多伦多", systemImage: "eye.fill")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: coordinator.userRole == .protected_ ? "shield.fill" : "eye.fill")
                    .font(.system(size: 10))
                Text(coordinator.userRole == .protected_ ? "被守护" : "守护者")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .padding(.top, 54)
        .padding(.trailing, 16)
    }
}
