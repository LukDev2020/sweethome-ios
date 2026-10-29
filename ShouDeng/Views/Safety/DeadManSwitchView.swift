import SwiftUI

// MARK: - Dead Man's Switch View
//
// A user-triggered countdown timer: if not dismissed before expiry,
// automatically sends SOS with location to all guardians.
// Use cases: walking home alone, meeting a stranger, night run.

struct DeadManSwitchView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @ObservedObject private var switchService = DeadManSwitchService.shared
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    @State private var selectedProfile: DeadManSwitchService.QuickStartProfile = DeadManSwitchService.QuickStartProfile.all[0]
    @State private var selectedPreset: DeadManSwitchService.Preset = .min20

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if switchService.isActive {
                    activeTimerView
                } else {
                    setupView
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(lang.localized("deadman.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang.localized("duress.close")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Setup View (before starting)

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Info banner
                HStack(spacing: 10) {
                    Image(systemName: "timer.circle.fill")
                        .font(.scaled(size: 28))
                        .foregroundStyle(lamp)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.localized("deadman.info.title"))
                            .font(.scaled(size: 14, weight: .semibold))
                            .foregroundStyle(ink)
                        Text(lang.localized("deadman.info.body"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(lamp.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(lamp.opacity(0.2), lineWidth: 1)
                        )
                )

                // Quick start profiles
                VStack(alignment: .leading, spacing: 10) {
                    Text(lang.localized("deadman.presets"))
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(ink)

                    ForEach(DeadManSwitchService.QuickStartProfile.all) { profile in
                        Button {
                            selectedProfile = profile
                            selectedPreset = profile.preset
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: profile.icon)
                                    .font(.scaled(size: 16))
                                    .foregroundStyle(selectedProfile.id == profile.id ? .white : ink)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.scaled(size: 14, weight: .medium))
                                        .foregroundStyle(selectedProfile.id == profile.id ? .white : ink)
                                    Text(profile.preset.displayName)
                                        .font(.scaled(size: 11))
                                        .foregroundStyle(selectedProfile.id == profile.id ? .white.opacity(0.7) : .secondary)
                                }
                                Spacer()
                                if selectedProfile.id == profile.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedProfile.id == profile.id ? safe : Color(.secondarySystemBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Custom duration picker
                if selectedProfile.id == "custom" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lang.localized("deadman.custom.duration"))
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(ink)
                        Picker("", selection: $selectedPreset) {
                            ForEach(DeadManSwitchService.Preset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                    }
                }

                // Start button
                Button {
                    switchService.start(preset: selectedPreset)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.scaled(size: 16))
                        Text(lang.localized("deadman.start"))
                            .font(.scaled(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(safe)
                    )
                }
            }
            .padding(16)
        }
    }

    // MARK: - Active Timer View

    private var activeTimerView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Circular countdown
            ZStack {
                Circle()
                    .stroke(Color(.separator).opacity(0.2), lineWidth: 12)
                    .frame(width: 220, height: 220)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        timerColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: switchService.remainingSeconds)

                VStack(spacing: 4) {
                    Text(timeString)
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundStyle(timerColor)
                    Text(switchService.isPaused
                         ? lang.localized("deadman.paused")
                         : lang.localized("deadman.remaining"))
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            // Warning text
            if switchService.remainingSeconds <= 30 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(alert)
                    Text(lang.localized("deadman.warning.imminent"))
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundStyle(alert)
                }
                .padding(12)
                .background(alert.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            // Extend buttons
            HStack(spacing: 10) {
                ForEach(DeadManSwitchService.Extension.allCases) { ext in
                    Button {
                        switchService.extend(by: ext)
                    } label: {
                        Text(ext.displayName)
                            .font(.scaled(size: 14, weight: .medium))
                            .foregroundStyle(safe)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(safe.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 16)

            // Pause / Cancel
            HStack(spacing: 12) {
                Button {
                    if switchService.isPaused {
                        switchService.resume()
                    } else {
                        switchService.pause()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: switchService.isPaused ? "play.fill" : "pause.fill")
                        Text(switchService.isPaused
                             ? lang.localized("deadman.resume")
                             : lang.localized("deadman.pause"))
                    }
                    .font(.scaled(size: 15, weight: .medium))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                    )
                }

                Button {
                    switchService.cancel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                        Text(lang.localized("deadman.imsafe"))
                    }
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(safe)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Helpers

    private var progress: Double {
        guard switchService.totalSeconds > 0 else { return 0 }
        return Double(switchService.remainingSeconds) / Double(switchService.totalSeconds)
    }

    private var timerColor: Color {
        if switchService.remainingSeconds <= 30 { return alert }
        if switchService.remainingSeconds <= 60 { return lamp }
        return safe
    }

    private var timeString: String {
        let m = switchService.remainingSeconds / 60
        let s = switchService.remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
