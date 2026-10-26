import SwiftUI

struct FloatingSOSButton: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var isPressed = false
    @State private var progress: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var showConfirm = false

    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let holdDuration: Double = 1.5

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .fill(alert.opacity(0.15))
                .frame(width: 70, height: 70)
                .scaleEffect(pulseScale)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white.opacity(0.6), lineWidth: 3)
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(-90))

            // Main button
            Circle()
                .fill(
                    LinearGradient(
                        colors: [alert, alert.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .shadow(color: alert.opacity(0.4), radius: 8, y: 4)
                .overlay(
                    Text("SOS")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                )
                .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .onLongPressGesture(minimumDuration: holdDuration, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.15)) {
                isPressed = pressing
            }
            if pressing {
                withAnimation(.linear(duration: holdDuration)) {
                    progress = 1.0
                }
            } else {
                if progress < 0.95 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        progress = 0
                    }
                }
            }
        }, perform: {
            triggerSOS()
        })
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
        .accessibilityLabel("SOS Emergency Button")
        .accessibilityHint("Long press for 1.5 seconds to trigger emergency alert")
    }

    private func triggerSOS() {
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        coordinator.triggerSOS(method: .longPress)
        withAnimation(.easeOut(duration: 0.3)) {
            progress = 0
        }
    }
}
