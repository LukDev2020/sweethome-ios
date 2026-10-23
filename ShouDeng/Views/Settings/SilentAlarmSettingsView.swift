import SwiftUI

// MARK: - Silent Alarm Settings
//
// "沉默即报警" configuration. Set daily check-in times, confirm window,
// and grace period. If check-in is missed, guardians are notified.

struct SilentAlarmSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = SilentAlarmService.shared

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    @State private var showAddTime = false
    @State private var newHour = 12
    @State private var newMinute = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Enable toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("silent.alarm.enable")
                                .font(.scaled(size: 15, weight: .medium))
                                .foregroundStyle(ink)
                            Text("silent.alarm.enable.desc")
                                .font(.scaled(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $service.isEnabled)
                            .labelsHidden()
                            .tint(safe)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                    )

                    if service.isEnabled {
                        // Check-in times
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("silent.alarm.times")
                                    .font(.scaled(size: 13, weight: .semibold))
                                    .foregroundStyle(ink)
                                Spacer()
                                Button {
                                    showAddTime = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(safe)
                                }
                            }

                            ForEach(service.checkInTimes) { time in
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .foregroundStyle(safe)
                                        .font(.scaled(size: 14))
                                    Text(time.displayString)
                                        .font(.scaled(size: 16, weight: .medium, design: .monospaced))
                                        .foregroundStyle(ink)
                                    Spacer()
                                    Button {
                                        service.checkInTimes.removeAll { $0.id == time.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(alert.opacity(0.6))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                        )

                        // Confirm window
                        VStack(alignment: .leading, spacing: 8) {
                            Text("silent.alarm.window")
                                .font(.scaled(size: 13, weight: .semibold))
                                .foregroundStyle(ink)
                            Text("silent.alarm.window.desc")
                                .font(.scaled(size: 12))
                                .foregroundStyle(.secondary)

                            Picker("", selection: $service.confirmWindowMinutes) {
                                Text("15 分钟").tag(15)
                                Text("30 分钟").tag(30)
                                Text("60 分钟").tag(60)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                        )

                        // Grace period
                        VStack(alignment: .leading, spacing: 8) {
                            Text("silent.alarm.grace")
                                .font(.scaled(size: 13, weight: .semibold))
                                .foregroundStyle(ink)
                            Text("silent.alarm.grace.desc")
                                .font(.scaled(size: 12))
                                .foregroundStyle(.secondary)

                            Picker("", selection: $service.gracePeriodMisses) {
                                Text("1 次").tag(1)
                                Text("2 次").tag(2)
                                Text("3 次").tag(3)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                        )

                        // Explanation
                        VStack(alignment: .leading, spacing: 6) {
                            Label("silent.alarm.escalation.title", systemImage: "arrow.up.right.circle.fill")
                                .font(.scaled(size: 13, weight: .semibold))
                                .foregroundStyle(lamp)

                            Text("silent.alarm.escalation.desc")
                                .font(.scaled(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(lamp.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(lamp.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("silent.alarm.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        Task {
                            await service.syncScheduleToServer()
                            ConsentLogger.shared.log(
                                userId: coordinator.authManager.currentUserId ?? "unknown",
                                item: "silent_alarm",
                                copyVersion: "v1.0",
                                action: service.isEnabled ? "enabled" : "disabled"
                            )
                            dismiss()
                        }
                    }
                    .font(.scaled(size: 14, weight: .semibold))
                }
            }
            .sheet(isPresented: $showAddTime) {
                addTimeSheet
            }
        }
    }

    private var addTimeSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                HStack(spacing: 0) {
                    Picker("时", selection: $newHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)

                    Text(":")
                        .font(.scaled(size: 24, weight: .bold))

                    Picker("分", selection: $newMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                }

                Button {
                    let newTime = SilentAlarmService.CheckInTime(hour: newHour, minute: newMinute)
                    if !service.checkInTimes.contains(newTime) {
                        service.checkInTimes.append(newTime)
                        service.checkInTimes.sort { ($0.hour * 60 + $0.minute) < ($1.hour * 60 + $1.minute) }
                    }
                    showAddTime = false
                } label: {
                    Text("添加")
                        .font(.scaled(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(safe)
                        )
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationTitle("添加时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showAddTime = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
