import SwiftUI

// MARK: - Fake Call Settings & Trigger
//
// Allows configuring and triggering a simulated incoming phone call
// to help the user discreetly exit dangerous situations.

struct FakeCallSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @ObservedObject private var fakeCallService = FakeCallService.shared
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Info banner
                    HStack(spacing: 10) {
                        Image(systemName: "phone.arrow.down.left.fill")
                            .font(.scaled(size: 24))
                            .foregroundStyle(safe)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lang.localized("fakecall.info.title"))
                                .font(.scaled(size: 14, weight: .semibold))
                                .foregroundStyle(ink)
                            Text(lang.localized("fakecall.info.body"))
                                .font(.scaled(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(safe.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(safe.opacity(0.2), lineWidth: 1)
                            )
                    )

                    // Caller name
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lang.localized("fakecall.caller.name"))
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(ink)

                        TextField(lang.localized("fakecall.caller.placeholder"), text: $fakeCallService.callerName)
                            .font(.scaled(size: 16))
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                            )
                    }

                    // Delay picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lang.localized("fakecall.delay"))
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(ink)

                        Picker("", selection: $fakeCallService.selectedDelay) {
                            ForEach(FakeCallDelay.allCases) { delay in
                                Text(delay.displayName).tag(delay)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Auto-SOS toggle
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.scaled(size: 14))
                            .foregroundStyle(lamp)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(lang.localized("fakecall.autoSOS"))
                                .font(.scaled(size: 13))
                            Text(lang.localized("fakecall.autoSOS.desc"))
                                .font(.scaled(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $fakeCallService.triggerSilentSOSOnEnd)
                            .labelsHidden()
                            .tint(alert)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                    )

                    Spacer().frame(height: 10)

                    // Trigger button
                    Button {
                        fakeCallService.scheduleCall()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.scaled(size: 16))
                            Text(lang.localized("fakecall.trigger"))
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

                    // How it works
                    VStack(alignment: .leading, spacing: 10) {
                        Text(lang.localized("fakecall.how.title"))
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(ink)

                        howRow("1", text: lang.localized("fakecall.how.step1"))
                        howRow("2", text: lang.localized("fakecall.how.step2"))
                        howRow("3", text: lang.localized("fakecall.how.step3"))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                    )
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle(lang.localized("fakecall.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang.localized("duress.close")) { dismiss() }
                }
            }
        }
    }

    private func howRow(_ number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.scaled(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(ink.opacity(0.6)))
            Text(text)
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
