import SwiftUI
import TipKit

struct FloatingSOSButton: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var isPressed = false
    @State private var progress: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var showConfirm = false
    /// Shown when the button is released early — a tap used to do nothing at all.
    @State private var showHoldHint = false
    @State private var hintTask: Task<Void, Never>?
    /// When the current press began. `progress` can't tell an early release: inside
    /// withAnimation it is already 1.0 the moment the press starts.
    @State private var pressStartedAt: Date?

    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    /// Same hold as the home-screen slider and the copy ("Hold 5s to send SOS").
    /// 5 s after user testing: 3 s was triggered by accident several times. A real
    /// SOS still goes through the 5 s cancel countdown afterwards.
    static let holdDuration: Double = 5.0
    private var holdDuration: Double { Self.holdDuration }

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .fill(alert.opacity(0.15))
                .frame(width: 70, height: 70)
                .scaleEffect(pulseScale)

            // Progress ring (outside the button, so it reads clearly while holding)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(alert, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 66, height: 66)
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
                pressStartedAt = Date()
                SOSHoldTip().invalidate(reason: .actionPerformed)
                hideHoldHint()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.linear(duration: holdDuration)) {
                    progress = 1.0
                }
            } else {
                let held = pressStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                pressStartedAt = nil
                if held < holdDuration - 0.05 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        progress = 0
                    }
                    showHoldHintBriefly()
                }
            }
        }, perform: {
            triggerSOS()
        })
        .overlay(alignment: .trailing) {
            // To the left of the button (above it sits Explore Mode's "Show tips" pill)
            if showHoldHint {
                Text(LanguageManager.shared.localized("sos.button.holdHint"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .fixedSize()
                    .offset(x: -78)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
        .coachMark(CoachAnchor.sosButton)
        .appTip(coordinator.pendingSOS == nil && coordinator.activeSOSEvent == nil
                    ? AppTips.available(SOSHoldTip()) : nil, arrowEdge: .bottom)
        .accessibilityLabel(LanguageManager.shared.localized("sos.button.a11yLabel"))
        .accessibilityHint(LanguageManager.shared.localized("sos.button.a11yHint"))
    }

    private func showHoldHintBriefly() {
        withAnimation(.easeOut(duration: 0.15)) { showHoldHint = true }
        hintTask?.cancel()
        hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            hideHoldHint()
        }
    }

    private func hideHoldHint() {
        hintTask?.cancel()
        withAnimation(.easeIn(duration: 0.15)) { showHoldHint = false }
    }

    private func triggerSOS() {
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()
        coordinator.requestSOS(method: .longPress)
        withAnimation(.easeOut(duration: 0.3)) {
            progress = 0
        }
    }
}

extension View {
    /// Extra bottom margin for every scroll view inside, so content can scroll
    /// clear of the floating SOS button (it sits ~116 pt above the tab bar)
    /// instead of staying hidden under it. contentMargins reaches scroll views
    /// nested in a NavigationStack, unlike safeAreaInset.
    func floatingSOSClearance() -> some View {
        contentMargins(.bottom, 120, for: .scrollContent)
    }
}

// MARK: - SOS overlays

/// The 5-second cancel countdown and the fall check, on top of everything. Used by the
/// real app (RootView) and Explore Mode (DemoRootView), which showed nothing for 5 s.
private struct SOSOverlays: ViewModifier {
    @ObservedObject var coordinator: AppCoordinator

    func body(content: Content) -> some View {
        content.overlay {
            if coordinator.showFallConfirmation {
                FallConfirmationOverlay()
                    .environmentObject(coordinator)
            } else if let pending = coordinator.pendingSOS {
                SOSCountdownOverlay(pending: pending)
                    .environmentObject(coordinator)
            }
        }
    }
}

extension View {
    func sosOverlays(_ coordinator: AppCoordinator) -> some View {
        modifier(SOSOverlays(coordinator: coordinator))
    }
}
