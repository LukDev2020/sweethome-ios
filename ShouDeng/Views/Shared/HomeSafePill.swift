import SwiftUI

struct HomeSafePill: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var confirmed = false

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        Button(action: confirmSafe) {
            HStack(spacing: 6) {
                Image(systemName: confirmed ? "checkmark.circle.fill" : "house.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(confirmed
                     ? lang.localized("home_safe_confirmed", fallback: "Confirmed Safe")
                     : lang.localized("home_safe", fallback: "Home Safe"))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                LinearGradient(
                    colors: confirmed ? [safe.opacity(0.8), safe.opacity(0.7)] : [safe, Color(red: 45/255, green: 122/255, blue: 90/255)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(20)
            .shadow(color: safe.opacity(0.25), radius: 4, y: 2)
        }
        .disabled(confirmed)
        .accessibilityLabel(lang.localized("home_safe", fallback: "I'm Home Safe"))
    }

    private func confirmSafe() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        withAnimation(.spring(response: 0.3)) {
            confirmed = true
        }

        coordinator.performCheckIn()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { confirmed = false }
        }
    }
}
