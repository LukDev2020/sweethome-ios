import SwiftUI

// MARK: - Satellite Mode Banner
//
// Shown while the only connection is carrier satellite data (iOS 26.1+).
// Tells the person what still works so they don't wait for photos or the feed.

struct SatelliteModeBanner: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    private let ink = Color.appInk

    var body: some View {
        if coordinator.isOnSatellite {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.scaled(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lang.localized("satellite.banner.title"))
                        .font(.scaled(size: 13, weight: .semibold))
                    Text(lang.localized("satellite.banner.detail"))
                        .font(.scaled(size: 12))
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.inkSolid)
            .accessibilityElement(children: .combine)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
