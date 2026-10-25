import SwiftUI
import Combine

// MARK: - Home Timer View
//
// "I'll be home by X" timer. If not dismissed before deadline,
// all guardians get notified. Solves "daily open rate = 0" problem.

struct HomeTimerView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var selectedTime = Date().addingTimeInterval(3600)
    @State private var label = ""
    @State private var destination = ""
    @State private var routeNotes = ""
    @State private var isActive = false
    @State private var activeDeadline: Date?
    @State private var activeLabel: String?
    @State private var tick = Date()
    @State private var isLoading = false
    @State private var hasEscalated = false

    nonisolated(unsafe) private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isActive, let deadline = activeDeadline {
                    activeTimerView(deadline: deadline)
                } else {
                    setupView
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(langManager.localized("homeTimer.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(langManager.localized("homeTimer.close")) { dismiss() }
                }
            }
            .onReceive(timer) { newTick in
                tick = newTick
                checkTimerExpiry()
            }
            .task { await loadActiveTimer() }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "house.fill")
                .font(.scaled(size: 48))
                .foregroundStyle(safe.opacity(0.6))

            Text(langManager.localized("homeTimer.setup"))
                .font(.scaled(size: 20, weight: .semibold))
                .foregroundStyle(ink)

            Text(langManager.localized("homeTimer.setupDesc"))
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField(langManager.localized("homeTimer.label"), text: $label)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)

                TextField(langManager.localized("homeTimer.destination"), text: $destination)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)

                TextField(langManager.localized("homeTimer.routeNotes"), text: $routeNotes)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)

                DatePicker(
                    langManager.localized("homeTimer.estimatedTime"),
                    selection: $selectedTime,
                    in: Date()...,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)

            Button {
                Task { await startTimer() }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(langManager.localized("homeTimer.start"))
                        .font(.scaled(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(safe)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isLoading)
            .padding(.horizontal, 32)

            Spacer()

            Text(langManager.localized("homeTimer.commonScenarios"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Active Timer View

    private func activeTimerView(deadline: Date) -> some View {
        let remaining = max(0, Int(deadline.timeIntervalSince(tick)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        let isExpired = remaining == 0

        return VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(isExpired ? alert.opacity(0.3) : safe.opacity(0.15), lineWidth: 8)
                    .frame(maxWidth: 200, maxHeight: 200)

                Circle()
                    .trim(from: 0, to: isExpired ? 1.0 : CGFloat(remaining) / max(1, CGFloat(deadline.timeIntervalSince(activeDeadline!.addingTimeInterval(-Double(remaining))))))
                    .stroke(isExpired ? alert : safe, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(maxWidth: 200, maxHeight: 200)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    if isExpired {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.scaled(size: 32))
                            .foregroundStyle(alert)
                        Text(langManager.localized("homeTimer.expired"))
                            .font(.scaled(size: 16, weight: .bold))
                            .foregroundStyle(alert)
                    } else {
                        Text(String(format: "%02d:%02d:%02d", hours, minutes, seconds))
                            .font(.scaled(size: 36, weight: .bold, design: .monospaced))
                            .foregroundStyle(ink)
                        Text(langManager.localized("homeTimer.remaining"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(activeLabel ?? label)
                .font(.scaled(size: 18, weight: .medium))
                .foregroundStyle(ink)

            Text(langManager.localized("homeTimer.dismissHint"))
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)

            Button {
                Task { await dismissTimer() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(langManager.localized("homeTimer.arrived"))
                        .font(.scaled(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(safe)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Expiry Check

    private func checkTimerExpiry() {
        guard isActive, let deadline = activeDeadline, !hasEscalated else { return }
        let remaining = deadline.timeIntervalSince(tick)
        if remaining <= 0 {
            hasEscalated = true
            // Auto-escalate: notify guardians via server
            Task {
                do {
                    let _: SuccessResponse = try await coordinator.apiClient.post(
                        "/v1/home-timer/expire",
                        body: HomeTimerExpireRequest(
                            destination: destination.isEmpty ? nil : destination,
                            routeNotes: routeNotes.isEmpty ? nil : routeNotes
                        )
                    )
                } catch {
                    #if DEBUG
                    print("[HomeTimer] expire escalation error: \(error)")
                    #endif
                }
            }
            coordinator.addTimelineEntry(type: .homeTimerExpired, description: langManager.localized("homeTimer.expiredNotify"))
        }
    }

    // MARK: - Actions

    private func startTimer() async {
        isLoading = true
        defer { isLoading = false }

        let lastLocation = coordinator.locationManager.lastReportedLocation
        do {
            let _: SuccessResponse = try await coordinator.apiClient.post(
                "/v1/home-timer",
                body: HomeTimerRequest(
                    deadline: selectedTime,
                    label: label,
                    latitude: lastLocation?.coordinate.latitude,
                    longitude: lastLocation?.coordinate.longitude,
                    destination: destination.isEmpty ? nil : destination,
                    routeNotes: routeNotes.isEmpty ? nil : routeNotes
                )
            )
        } catch {
            #if DEBUG
            print("[HomeTimer] start error (using local fallback): \(error)")
            #endif
        }
        // Always activate locally so timer works even without backend
        await MainActor.run {
            activeDeadline = selectedTime
            activeLabel = label
            isActive = true
        }
        coordinator.addTimelineEntry(type: .homeTimerSet, description: String(format: langManager.localized("homeTimer.setEntry"), label))
    }

    private func dismissTimer() async {
        do {
            let _: SuccessResponse = try await coordinator.apiClient.post(
                "/v1/home-timer/dismiss",
                body: EmptyBody()
            )
        } catch {
            #if DEBUG
            print("[HomeTimer] dismiss error (using local fallback): \(error)")
            #endif
        }
        // Always dismiss locally
        await MainActor.run {
            isActive = false
            activeDeadline = nil
            activeLabel = nil
        }
        coordinator.addTimelineEntry(type: .homeTimerDismissed, description: langManager.localized("homeTimer.safeArrival"))
        dismiss()
    }

    private func loadActiveTimer() async {
        do {
            let timer: HomeTimerResponse? = try await coordinator.apiClient.get("/v1/home-timer")
            if let timer, timer.status == "active" {
                await MainActor.run {
                    activeDeadline = timer.deadline
                    activeLabel = timer.label
                    isActive = true
                }
            }
        } catch {
            // No active timer
        }
    }
}
