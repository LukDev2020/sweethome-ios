import SwiftUI

// MARK: - Duress Code Settings
//
// Allows the user to set a "fake" unlock code. When entered on the login screen,
// the app appears to load normally but silently triggers an SOS with
// .duressPassword trigger method. The escalation engine already handles this.

struct DuressCodeSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color.appInk
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    @State private var newCode = ""
    @State private var confirmCode = ""
    @State private var currentCode = ""
    @State private var errorMessage: String?
    @State private var showRemoveConfirm = false
    @State private var showSuccess = false

    @State private var hasDuressCode = KeychainHelper.shared.read(.duressCode) != nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Warning banner
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.scaled(size: 24))
                            .foregroundStyle(lamp)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(langManager.localized("duress.warning.title"))
                                .font(.scaled(size: 14, weight: .semibold))
                                .foregroundStyle(ink)
                            Text(langManager.localized("duress.warning"))
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

                    if hasDuressCode {
                        existingCodeView
                    } else {
                        newCodeView
                    }

                    // How it works
                    VStack(alignment: .leading, spacing: 10) {
                        Text(langManager.localized("duress.how.title"))
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(ink)

                        howItWorksRow("1", text: "duress.how.step1")
                        howItWorksRow("2", text: "duress.how.step2")
                        howItWorksRow("3", text: "duress.how.step3")
                        howItWorksRow("4", text: "duress.how.step4")
                        howItWorksRow("5", text: "duress.how.step5")
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
            .navigationTitle(langManager.localized("duress.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label(langManager.localized("duress.close"), systemImage: "xmark") }
                }
            }
            .alert(langManager.localized("duress.remove.confirm.title"), isPresented: $showRemoveConfirm) {
                Button(langManager.localized("duress.cancel"), role: .cancel) {}
                Button(langManager.localized("duress.remove.confirm"), role: .destructive) {
                    KeychainHelper.shared.delete(.duressCode)
                    ConsentLogger.shared.log(
                        userId: coordinator.authManager.currentUserId ?? "unknown",
                        item: "duress_code",
                        copyVersion: "v1.0",
                        action: "removed"
                    )
                    dismiss()
                }
            } message: {
                Text(langManager.localized("duress.remove.confirm.message"))
            }
            .alert(langManager.localized("duress.save.success"), isPresented: $showSuccess) {
                Button(langManager.localized("duress.ok")) { dismiss() }
            } message: {
                Text(langManager.localized("duress.saved.message"))
            }
        }
    }

    // MARK: - New Code Entry

    private var newCodeView: some View {
        VStack(spacing: 14) {
            Text(langManager.localized("duress.new.code"))
                .font(.scaled(size: 16, weight: .semibold))
                .foregroundStyle(ink)

            SecureField(langManager.localized("duress.code.placeholder"), text: $newCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.scaled(size: 18))
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                )

            SecureField(langManager.localized("duress.confirm.code"), text: $confirmCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.scaled(size: 18))
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                )

            if let error = errorMessage {
                Text(error)
                    .font(.scaled(size: 12))
                    .foregroundStyle(alert)
            }

            Button {
                saveDuressCode()
            } label: {
                Text(langManager.localized("duress.save"))
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(newCode.count >= 4 && newCode == confirmCode ? safe : safe.opacity(0.4))
                    )
            }
            .disabled(newCode.count < 4 || newCode != confirmCode)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Existing Code View

    private var existingCodeView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(safe)
                    .font(.scaled(size: 20))
                Text(langManager.localized("duress.configured"))
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(safe)
            }

            Text(langManager.localized("duress.active.desc"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    showRemoveConfirm = true
                } label: {
                    Text(langManager.localized("duress.remove"))
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(alert)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(alert.opacity(0.4), lineWidth: 1)
                        )
                }

                Button {
                    KeychainHelper.shared.delete(.duressCode)
                    newCode = ""
                    confirmCode = ""
                    hasDuressCode = false
                } label: {
                    Text(langManager.localized("duress.change"))
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                        )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(safe.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(safe.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private func howItWorksRow(_ number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.scaled(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.inkSolid.opacity(0.6)))
            Text(langManager.localized(text))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveDuressCode() {
        guard newCode.count >= 4 else {
            errorMessage = langManager.localized("duress.error.short")
            return
        }
        guard newCode == confirmCode else {
            errorMessage = langManager.localized("duress.error.mismatch")
            return
        }
        KeychainHelper.shared.save(newCode, for: .duressCode)
        ConsentLogger.shared.log(
            userId: coordinator.authManager.currentUserId ?? "unknown",
            item: "duress_code",
            copyVersion: "v1.0",
            action: "enabled"
        )
        showSuccess = true
    }
}
