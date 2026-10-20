import SwiftUI
import UIKit

/// Full-screen overlay shown when a fall is detected.
/// Displays a 60-second countdown. If user taps "I'm Fine", the fall is dismissed.
/// If the countdown expires, FallDetector auto-escalates to SOS.
struct FallConfirmationOverlay: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    @StateObject private var countdownTimer = FallCountdownTimer()

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Warning icon
                Image(systemName: "figure.fall")
                    .font(.system(size: 64))
                    .foregroundColor(.red)
                    .symbolEffect(.pulse, options: .repeating)

                Text(lang.localized("fall.detected.title"))
                    .font(.scaled(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(lang.localized("fall.detected.subtitle"))
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
                        .trim(from: 0, to: CGFloat(countdownTimer.timeRemaining) / 60.0)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: countdownTimer.timeRemaining)

                    Text("\(countdownTimer.timeRemaining)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Text(lang.localized("fall.sos.countdown"))
                    .font(.scaled(size: 14))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

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
