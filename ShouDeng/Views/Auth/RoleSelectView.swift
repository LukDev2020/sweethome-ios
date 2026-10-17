import SwiftUI

// MARK: - Role Select View
//
// Shown after signup when the user needs to choose their role.
// Two options: Care Receiver (protected) or Caregiver (guardian).
// Logs selection to AuditLog for compliance.

struct RoleSelectView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
    private let blue = Color(red: 61/255, green: 154/255, blue: 192/255)
    private let ink = Color(red: 14/255, green: 43/255, blue: 74/255)
    private let ink2 = Color(red: 14/255, green: 43/255, blue: 74/255).opacity(0.62)
    private let bg = Color(red: 251/255, green: 248/255, blue: 241/255)
    private let cream = Color(red: 252/255, green: 242/255, blue: 218/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    @State private var selectedRole: UserRole = .protected_
    @State private var isLoading = false

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(navy.opacity(0.7))
                    .padding(.bottom, 20)

                Text(lang.localized("role.select.title"))
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(navy)

                Text(lang.localized("role.select.subtitle"))
                    .font(.system(size: 14))
                    .foregroundStyle(ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 8)
                    .padding(.horizontal, 40)

                VStack(spacing: 12) {
                    roleCard(
                        role: .protected_,
                        icon: "shield.fill",
                        title: lang.localized("signup.role.protected"),
                        desc: lang.localized("signup.role.protected.desc"),
                        color: lamp
                    )
                    roleCard(
                        role: .guardian,
                        icon: "eye.fill",
                        title: lang.localized("signup.role.guardian"),
                        desc: lang.localized("signup.role.guardian.desc"),
                        color: blue
                    )
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)

                Button {
                    Task { await confirmRole() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(cream)
                        } else {
                            Text(lang.localized("role.select.confirm"))
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
                .padding(.top, 24)

                Spacer()
                Spacer()
            }
        }
    }

    private func roleCard(role: UserRole, icon: String, title: String, desc: String, color: Color) -> some View {
        Button {
            selectedRole = role
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(selectedRole == role ? color : ink.opacity(0.3))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ink)
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundStyle(ink2)
                }

                Spacer()

                Image(systemName: selectedRole == role ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedRole == role ? safe : ink.opacity(0.2))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(selectedRole == role ? safe.opacity(0.5) : ink.opacity(0.08), lineWidth: 1.5)
                    )
            )
        }
    }

    @MainActor
    private func confirmRole() async {
        isLoading = true
        defer { isLoading = false }

        coordinator.userRole = selectedRole
        coordinator.localStore.saveUserRole(selectedRole)

        // Update server
        do {
            let _: SuccessResponse = try await coordinator.apiClient.put(
                "/v1/user/role",
                body: ["role": selectedRole.rawValue]
            )
        } catch {
            #if DEBUG
            print("[RoleSelectView] Failed to update role on server: \(error)")
            #endif
        }

        AuditLog.record(event: .roleSelected, version: selectedRole.rawValue)
        coordinator.needsRoleSelection = false
    }
}
