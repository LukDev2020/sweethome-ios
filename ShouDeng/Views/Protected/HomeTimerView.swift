import SwiftUI

// MARK: - Home Timer View
//
// "I'll be home by X" timer. If not dismissed before deadline,
// all guardians get notified. Solves "daily open rate = 0" problem.

struct HomeTimerView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var selectedTime = Date().addingTimeInterval(3600)
    @State private var label = "回家"
    @State private var isActive = false
    @State private var activeDeadline: Date?
    @State private var activeLabel: String?
    @State private var tick = Date()
    @State private var isLoading = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
            .navigationTitle("回家计时器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .onReceive(timer) { tick = $0 }
            .task { await loadActiveTimer() }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "house.fill")
                .font(.system(size: 48))
                .foregroundStyle(safe.opacity(0.6))

            Text("设置回家时间")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ink)

            Text("如果到时间还没有关闭计时器，\n系统会自动通知你的守护者。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("标签", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                DatePicker(
                    "预计时间",
                    selection: $selectedTime,
                    in: Date()...,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: 280)
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
                    Text("开始计时")
                        .font(.system(size: 16, weight: .semibold))
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

            Text("常用场景：夜间回家、独自出门、见陌生人")
                .font(.system(size: 11))
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
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: isExpired ? 1.0 : CGFloat(remaining) / max(1, CGFloat(deadline.timeIntervalSince(activeDeadline!.addingTimeInterval(-Double(remaining))))))
                    .stroke(isExpired ? alert : safe, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    if isExpired {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(alert)
                        Text("已超时")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(alert)
                    } else {
                        Text(String(format: "%02d:%02d:%02d", hours, minutes, seconds))
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundStyle(ink)
                        Text("剩余时间")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(activeLabel ?? label)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ink)

            Text("到达后请关闭计时器")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Button {
                Task { await dismissTimer() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("我到了，关闭计时")
                        .font(.system(size: 16, weight: .semibold))
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
                    longitude: lastLocation?.coordinate.longitude
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
        coordinator.addTimelineEntry(type: .homeTimerSet, description: "设置了回家计时：\(label)")
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
        coordinator.addTimelineEntry(type: .homeTimerDismissed, description: "已安全到达")
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
