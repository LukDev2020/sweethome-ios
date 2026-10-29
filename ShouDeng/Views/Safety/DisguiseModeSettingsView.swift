import SwiftUI

// MARK: - Disguise Mode Settings
//
// Configure and activate disguise mode — hides the real app behind
// a calculator, weather, or notes interface.

struct DisguiseModeSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @ObservedObject private var disguiseService = DisguiseModeService.shared
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    @State private var selectedDisguise: DisguiseType = .calculator
    @State private var secretPhrase: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Warning banner
                    HStack(spacing: 10) {
                        Image(systemName: "eye.slash.fill")
                            .font(.scaled(size: 24))
                            .foregroundStyle(pro)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lang.localized("disguise.title"))
                                .font(.scaled(size: 14, weight: .semibold))
                                .foregroundStyle(ink)
                            Text(lang.localized("disguise.info"))
                                .font(.scaled(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(pro.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(pro.opacity(0.2), lineWidth: 1)
                            )
                    )

                    // Disguise type selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text(lang.localized("disguise.title"))
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(ink)

                        disguiseOption(
                            type: .calculator,
                            icon: "function",
                            name: lang.localized("disguise.calculator"),
                            hint: lang.localized("disguise.secret.calculator")
                        )

                        disguiseOption(
                            type: .weather,
                            icon: "cloud.sun.fill",
                            name: lang.localized("disguise.weather"),
                            hint: lang.localized("disguise.secret.weather")
                        )

                        disguiseOption(
                            type: .notes,
                            icon: "note.text",
                            name: lang.localized("disguise.notes"),
                            hint: lang.localized("disguise.secret.notes")
                        )
                    }

                    // Secret phrase (for notes disguise)
                    if selectedDisguise == .notes {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Secret Phrase")
                                .font(.scaled(size: 13, weight: .semibold))
                                .foregroundStyle(ink)
                            SecureField("help me", text: $secretPhrase)
                                .font(.scaled(size: 16))
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                                )
                                .onChange(of: secretPhrase) { _, newValue in
                                    disguiseService.setNotesSecretPhrase(newValue)
                                }
                        }
                    }

                    // Activate button
                    Button {
                        disguiseService.activateDisguise(type: selectedDisguise)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash.fill")
                                .font(.scaled(size: 16))
                            Text(lang.localized("disguise.activate"))
                                .font(.scaled(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(pro)
                        )
                    }

                    if disguiseService.isDisguiseActive {
                        Button {
                            disguiseService.deactivateDisguise()
                        } label: {
                            Text(lang.localized("disguise.deactivate"))
                                .font(.scaled(size: 15, weight: .medium))
                                .foregroundStyle(alert)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle(lang.localized("disguise.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang.localized("duress.close")) { dismiss() }
                }
            }
            .onAppear {
                selectedDisguise = disguiseService.currentDisguise
                secretPhrase = disguiseService.notesSecretPhrase
            }
        }
    }

    private func disguiseOption(type: DisguiseType, icon: String, name: String, hint: String) -> some View {
        Button {
            selectedDisguise = type
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.scaled(size: 20))
                    .foregroundStyle(selectedDisguise == type ? .white : ink)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(selectedDisguise == type ? .white : ink)
                    Text(hint)
                        .font(.scaled(size: 11))
                        .foregroundStyle(selectedDisguise == type ? .white.opacity(0.7) : .secondary)
                }
                Spacer()
                if selectedDisguise == type {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedDisguise == type ? pro : Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}
