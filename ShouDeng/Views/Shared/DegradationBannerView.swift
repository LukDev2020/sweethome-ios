import SwiftUI

// MARK: - Degradation Banner
//
// Non-dismissable banner that appears below the nav bar
// when protection is compromised. From revised plan:
//
//   "宁可打扰用户，不可让其误判。"
//
// - LAMP color for caution (location reduced, no duty, etc.)
// - ALERT color for critical (offline, battery dying, etc.)
// - Cannot be dismissed — disappears only when condition resolves
// - Tap opens detail sheet

struct DegradationBannerView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var selectedWarning: DisclaimerCopy.Degradation.Warning?

    // Design system
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(coordinator.deviceHealthMonitor.activeWarnings) { warning in
                bannerRow(warning)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: coordinator.deviceHealthMonitor.activeWarnings.count)
        .sheet(item: $selectedWarning) { warning in
            warningDetailSheet(warning)
        }
    }

    // MARK: - Banner Row

    private func bannerRow(_ warning: DisclaimerCopy.Degradation.Warning) -> some View {
        let isCritical = warning.severity == .critical
        let tintColor = isCritical ? alert : lamp

        return Button {
            selectedWarning = warning
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCritical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(tintColor)

                // Show appropriate message based on user role
                Text(messageForCurrentRole(warning))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ink.opacity(0.85))
                    .lineLimit(1)

                Spacer()

                Text("详情")
                    .font(.system(size: 10))
                    .foregroundStyle(ink.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(tintColor.opacity(0.12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Sheet

    private func warningDetailSheet(_ warning: DisclaimerCopy.Degradation.Warning) -> some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 24)

            // Icon
            let isCritical = warning.severity == .critical
            Image(systemName: isCritical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(isCritical ? alert : lamp)
                .padding(.bottom, 16)

            // Title
            Text(messageForCurrentRole(warning))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            // Detail text
            Text(warning.detailText)
                .font(.system(size: 14))
                .foregroundStyle(ink.opacity(0.72))
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 24)
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func messageForCurrentRole(_ warning: DisclaimerCopy.Degradation.Warning) -> String {
        switch coordinator.userRole {
        case .protected_:
            return warning.protectedMessage
        case .guardian:
            return warning.guardianMessage
        }
    }
}
