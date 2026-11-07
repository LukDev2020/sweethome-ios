import SwiftUI
import UIKit

/// Full-screen "Are you OK?" after a detected fall, distress sound or voice command.
/// "I'm OK" dismisses; "Send SOS now" (hurt but conscious) or the end of the countdown
/// sends the SOS (AppCoordinator+AutoSOSCheck). A test shows a banner and sends nothing.
struct FallConfirmationOverlay: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    @StateObject private var countdownTimer = FallCountdownTimer()

    private var reason: AutoSOSReason { coordinator.autoSOSCheck?.reason ?? .fall }
    private var isTest: Bool { coordinator.autoSOSCheck?.isTest ?? false }
    private var total: Int { Int((coordinator.autoSOSCheck?.duration ?? 60).rounded()) }

    var body: some View {
        ZStack {
            // Nearly opaque: the screen behind must not compete with "Are you OK?"
            Color.black.opacity(0.94)
                .ignoresSafeArea()

            // Kept clear of the iPhone Duo fold (right half when unfolded)
            FoldAvoidingColumn {
                VStack(spacing: 24) {
                    Spacer()

                    // Warning icon
                    Image(systemName: "figure.fall")
                        .font(.system(size: 64))
                        .foregroundColor(.red)
                        .symbolEffect(.pulse, options: .repeating)

                    if isTest {
                        Text(lang.localized("fallTest.banner"))
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.yellow))
                    }

                    Text(lang.localized(reason.titleKey))
                        .font(.scaled(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(lang.localized(reason.subtitleKey))
                        .font(.scaled(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // Countdown circle
                    ZStack {
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 8)
                            .frame(width: 120, height: 120)

                        Circle()
                            .trim(from: 0, to: CGFloat(countdownTimer.timeRemaining) / CGFloat(max(total, 1)))
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: countdownTimer.timeRemaining)

                        Text("\(countdownTimer.timeRemaining)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }

                    Text(lang.localized(isTest ? "fallTest.countdown" : "fall.sos.countdown"))
                        .font(.scaled(size: 14))
                        .foregroundColor(.white.opacity(0.6))

                    Spacer()

                    // Hurt but conscious: don't make them wait
                    Button {
                        countdownTimer.stop()
                        coordinator.autoSOSCheckExpired(byPerson: true)
                    } label: {
                        Text(lang.localized("autosos.sendNow"))
                            .font(.scaled(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 32)

                    // "I'm Fine" button
                    Button {
                        countdownTimer.stop()
                        coordinator.dismissFallConfirmation()
                    } label: {
                        Text(lang.localized("fall.im.fine"))
                            .font(.scaled(size: 20, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                }
            }
        }
        .onAppear {
            if let deadline = coordinator.fallConfirmationDeadline {
                countdownTimer.start(deadline: deadline)
            }
        }
        .onDisappear {
            countdownTimer.stop()
        }
    }
}

/// Full-screen cancel window shown after a manual SOS trigger (button, widget,
/// Bluetooth button, watch). Guardians are alerted when the countdown ends,
/// unless the user cancels; "Send now" skips the wait.
struct SOSCountdownOverlay: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    let pending: AppCoordinator.PendingSOS
    @StateObject private var countdownTimer = FallCountdownTimer()

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()

            // Kept clear of the iPhone Duo fold (right half when unfolded)
            FoldAvoidingColumn {
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "sos.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.red)
                        .symbolEffect(.pulse, options: .repeating)
                        .accessibilityHidden(true)

                    Text(lang.localized("sos.pending.title"))
                        .font(.scaled(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(lang.localized("sos.pending.subtitle"))
                        .font(.scaled(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    ZStack {
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 8)
                            .frame(width: 120, height: 120)

                        Circle()
                            .trim(from: 0, to: CGFloat(countdownTimer.timeRemaining) / CGFloat(max(1, pending.duration)))
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: countdownTimer.timeRemaining)

                        Text("\(countdownTimer.timeRemaining)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(format: lang.localized("sos.pending.a11y.countdown"), countdownTimer.timeRemaining))

                    Spacer()

                    VStack(spacing: 12) {
                        Button {
                            countdownTimer.stop()
                            coordinator.cancelPendingSOS()
                        } label: {
                            Text(lang.localized("sos.pending.cancel"))
                                .font(.scaled(size: 20, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        Button {
                            countdownTimer.stop()
                            coordinator.sendPendingSOSNow()
                        } label: {
                            Text(lang.localized("sos.pending.sendNow"))
                                .font(.scaled(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                }
            }
        }
        .onAppear { countdownTimer.start(deadline: pending.deadline) }
        .onDisappear { countdownTimer.stop() }
    }
}

/// Background-safe countdown timer using DispatchSourceTimer + UIBackgroundTask.
/// Keeps ticking even when the app is backgrounded (within iOS background execution limits).
final class FallCountdownTimer: ObservableObject {
    @Published var timeRemaining: Int = 60

    private var dispatchTimer: DispatchSourceTimer?
    private var deadline: Date?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    func start(deadline: Date) {
        self.deadline = deadline
        let remaining = Int(deadline.timeIntervalSinceNow)
        timeRemaining = max(0, min(60, remaining))

        // Request background execution time for safety-critical countdown
        backgroundTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }

        // Use DispatchSourceTimer which fires on a background queue regardless of RunLoop state
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now() + 1, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, let deadline = self.deadline else { return }
            let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
            DispatchQueue.main.async {
                self.timeRemaining = remaining
            }
        }
        timer.resume()
        dispatchTimer = timer
    }

    func stop() {
        dispatchTimer?.cancel()
        dispatchTimer = nil
        deadline = nil
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }

    deinit {
        stop()
    }
}
