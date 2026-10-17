import SwiftUI

// MARK: - Invite Accept View
//
// Shown when a user opens a Universal Link invite (e.g. shoudeng.app/invite/ABC123).
// Displays invite details and lets the user accept or decline.

struct InviteAcceptView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lang = LanguageManager.shared

    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
    private let blue = Color(red: 61/255, green: 154/255, blue: 192/255)
    private let ink = Color(red: 14/255, green: 43/255, blue: 74/255)
    private let ink2 = Color(red: 14/255, green: 43/255, blue: 74/255).opacity(0.62)
    private let cream = Color(red: 252/255, green: 242/255, blue: 218/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let red = Color(red: 246/255, green: 78/255, blue: 77/255)

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var accepted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                if accepted {
                    successContent
                } else {
                    inviteContent
                }

                Spacer()
                Spacer()
            }
            .navigationTitle(lang.localized("invite.accept.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang.localized("picker.cancel")) {
                        coordinator.showInviteAccept = false
                        coordinator.pendingInviteCode = nil
                        dismiss()
                    }
                }
            }
        }
    }

    private var inviteContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(blue)

            Text(lang.localized("invite.accept.message"))
                .font(.system(size: 15))
                .foregroundStyle(ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            if let code = coordinator.pendingInviteCode {
                Text(code)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(navy)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(navy.opacity(0.06))
                    )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(red)
            }

            Button {
                Task { await acceptInvite() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(cream)
                    } else {
                        Text(lang.localized("invite.accept.button"))
                    }
                }
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(navy)
                )
            }
            .disabled(isLoading)
            .padding(.horizontal, 32)
        }
    }

    private var successContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(safe)

            Text(lang.localized("invite.accept.success"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ink)

            Button {
                coordinator.showInviteAccept = false
                coordinator.pendingInviteCode = nil
                dismiss()
            } label: {
                Text(lang.localized("invite.accept.done"))
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(cream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(navy)
                    )
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
    }

    @MainActor
    private func acceptInvite() async {
        guard let code = coordinator.pendingInviteCode else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let _: SuccessResponse = try await coordinator.apiClient.post(
                "/v1/invite/accept",
                body: ["code": code]
            )
            AuditLog.record(event: .inviteAccepted, version: code)
            accepted = true

            // Refresh data
            Task {
                await coordinator.fetchGuardians()
                await coordinator.fetchProtectedPersons()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
