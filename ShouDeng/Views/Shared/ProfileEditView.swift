import SwiftUI

// MARK: - Profile Edit View
//
// Shared between protected and guardian portals.
// Edits display name, city, and timezone.
// Calls PUT /v1/user/me to persist.

struct ProfileEditView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var displayName: String = ""
    @State private var cityName: String = ""
    @State private var selectedTimeZone: TimeZone = .current
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Avatar
                    avatarSection

                    // Fields
                    fieldSection

                    // Timezone
                    timezoneSection

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(alert)
                    }

                    // Save button
                    Button {
                        Task { await saveProfile() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().tint(.white)
                            }
                            Text("保存")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(safe)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)

                    // Role info
                    HStack(spacing: 6) {
                        Image(systemName: coordinator.userRole == .protected_ ? "shield.fill" : "eye.fill")
                            .font(.system(size: 11))
                        Text(coordinator.userRole == .protected_ ? "被守护者" : "守护者")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear { loadCurrentProfile() }
            .alert("已保存", isPresented: $showSuccess) {
                Button("好") { dismiss() }
            }
        }
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 72, height: 72)
                Text(displayName.isEmpty ? "?" : String(displayName.prefix(1)))
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(ink)
            }
            Text("头像取自昵称首字")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Fields

    private var fieldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基本信息")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                fieldRow("昵称") {
                    TextField("输入昵称", text: $displayName)
                        .font(.system(size: 14))
                        .multilineTextAlignment(.trailing)
                }
                Divider()
                fieldRow("城市") {
                    TextField("输入城市", text: $cityName)
                        .font(.system(size: 14))
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Timezone

    private var timezoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("时区")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                fieldRow("当前时区") {
                    Text(selectedTimeZone.identifier)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Divider()
                fieldRow("本地时间") {
                    let formatter = DateFormatter()
                    let _ = formatter.dateFormat = "HH:mm"
                    let _ = formatter.timeZone = selectedTimeZone
                    Text(formatter.string(from: Date()))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            content()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func loadCurrentProfile() {
        guard let user = coordinator.currentUser else { return }
        displayName = user.displayName
        cityName = user.cityName
        selectedTimeZone = user.timeZone
    }

    private func saveProfile() async {
        isSaving = true
        errorMessage = nil
        do {
            let _: SuccessResponse = try await coordinator.apiClient.put(
                "/v1/user/me",
                body: UpdateProfileRequest(
                    displayName: displayName.trimmingCharacters(in: .whitespaces),
                    timeZone: selectedTimeZone.identifier,
                    cityName: cityName.trimmingCharacters(in: .whitespaces),
                    countryCode: nil
                )
            )
            // Update local state
            await MainActor.run {
                coordinator.currentUser?.displayName = displayName.trimmingCharacters(in: .whitespaces)
                coordinator.currentUser?.avatarInitial = String(displayName.prefix(1))
                coordinator.currentUser?.cityName = cityName.trimmingCharacters(in: .whitespaces)
                if let user = coordinator.currentUser {
                    coordinator.localStore.saveCurrentUser(user)
                }
                showSuccess = true
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
        await MainActor.run { isSaving = false }
    }
}
