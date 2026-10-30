import SwiftUI

// MARK: - Demo root
//
// The real tab screens, fed by the demo coordinator, under a persistent DEMO
// banner that takes its own space (it never covers a screen's header).

struct DemoRootView: View {
    @ObservedObject var explore: ExploreModeController
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 0) {
            DemoBannerView(explore: explore)
            switch coordinator.userRole {
            case .protected_:
                ProtectedTabView()
            case .guardian:
                GuardianTabView()
            }
        }
        .environmentObject(coordinator)
        // SwiftUI Links (hotlines, consulate…) must not dial anyone from the demo
        .environment(\.openURL, OpenURLAction { url in
            if ExternalURL.isBlockedInDemo(url) {
                ExploreMode.blocks("call")
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $explore.presentedSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .dutySchedule: GuardianDutyScheduleView()
                case .claimMaterials: ClaimMaterialsView()
                }
            }
            .environmentObject(coordinator)
        }
    }
}

struct DemoBannerView: View {
    @ObservedObject var explore: ExploreModeController
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    var body: some View {
        let lm = LanguageManager.shared
        HStack(spacing: 8) {
            Text("DEMO")
                .font(.caption.weight(.heavy))
                .foregroundStyle(lamp)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(ink))
            Text(lm.localized("explore.banner.subtitle"))
                .font(.caption.weight(.medium))
                .foregroundStyle(ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                explore.switchRole(to: explore.role.other)
            } label: {
                Text(lm.localized(explore.role == .mom ? "explore.switch.toSarah" : "explore.switch.toMom"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(ink))
                    .lineLimit(1)
            }
            Button(lm.localized("explore.exit")) { explore.exit() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.7)))
            if !explore.isTourVisible && !explore.showChecklist && !explore.showHandoff {
                Button {
                    explore.isTourVisible = true
                } label: {
                    Image(systemName: "lightbulb")
                }
                .foregroundStyle(ink)
                .accessibilityLabel(lm.localized("explore.tip.show"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(lamp)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(lm.localized("explore.banner.a11y"))
    }
}
