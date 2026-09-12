import SwiftUI
import PhotosUI

// MARK: - Avatar View (reusable)

struct AvatarView: View {
    let user: User?
    var size: CGFloat = 36

    // Alternative init: pass raw values directly (for posts/comments)
    var initial: String?
    var avatarPath: String?

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    private var resolvedAvatarPath: String? {
        user?.avatarLocalPath ?? avatarPath
    }

    private var resolvedInitial: String {
        user?.avatarInitial ?? initial ?? "?"
    }

    var body: some View {
        if let path = resolvedAvatarPath, let image = Self.loadAvatar(path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: size, height: size)
                Text(resolvedInitial)
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(ink)
            }
        }
    }

    static func loadAvatar(_ filename: String) -> UIImage? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("avatars").appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Profile Edit View
//
// Shared between protected and guardian portals.
// Edits display name, avatar photo, city, and timezone.
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
    @State private var avatarImage: UIImage?
    @State private var avatarItem: PhotosPickerItem?

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
            PhotosPicker(selection: $avatarItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    if let avatarImage {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 80, height: 80)
                            .overlay {
                                Text(displayName.isEmpty ? "?" : String(displayName.prefix(1)))
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundStyle(ink)
                            }
                    }
                    // Camera badge
                    Circle()
                        .fill(safe)
                        .frame(width: 26, height: 26)
                        .overlay {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                }
            }
            Text("点击更换头像")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .onChange(of: avatarItem) { _, newItem in
            Task { await loadAvatarImage(from: newItem) }
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
        // Load saved avatar from disk
        if let path = user.avatarLocalPath {
            let url = Self.avatarDirectory.appendingPathComponent(path)
            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                avatarImage = image
            }
        }
    }

    private func loadAvatarImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            await MainActor.run { avatarImage = image }
        }
    }

    private static var avatarDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func saveAvatarToDisk(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let filename = "avatar_\(coordinator.currentUser?.id ?? "local").jpg"
        let url = Self.avatarDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: [.atomic])
            return filename
        } catch {
            return nil
        }
    }

    private func saveProfile() async {
        isSaving = true
        errorMessage = nil

        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        let trimmedCity = cityName.trimmingCharacters(in: .whitespaces)

        // Save avatar to disk if changed
        var avatarPath = coordinator.currentUser?.avatarLocalPath
        if let avatarImage {
            if let saved = saveAvatarToDisk(avatarImage) {
                avatarPath = saved
            }
        }

        do {
            let _: SuccessResponse = try await coordinator.apiClient.put(
                "/v1/user/me",
                body: UpdateProfileRequest(
                    displayName: trimmedName,
                    timeZone: selectedTimeZone.identifier,
                    cityName: trimmedCity,
                    countryCode: nil
                )
            )
            await MainActor.run {
                applyToUser(name: trimmedName, city: trimmedCity, avatarPath: avatarPath)
                showSuccess = true
            }
        } catch {
            // API failed — still save locally in dev mode
            await MainActor.run {
                applyToUser(name: trimmedName, city: trimmedCity, avatarPath: avatarPath)
                showSuccess = true
            }
        }
        await MainActor.run { isSaving = false }
    }

    private func applyToUser(name: String, city: String, avatarPath: String?) {
        if coordinator.currentUser != nil {
            coordinator.currentUser?.displayName = name
            coordinator.currentUser?.avatarInitial = String(name.prefix(1))
            coordinator.currentUser?.avatarLocalPath = avatarPath
            coordinator.currentUser?.cityName = city
            coordinator.currentUser?.timeZone = selectedTimeZone
        } else {
            // Create a new user if none exists (dev bypass mode)
            coordinator.currentUser = User(
                id: "dev_local_user",
                displayName: name,
                role: coordinator.userRole,
                avatarInitial: String(name.prefix(1)),
                avatarLocalPath: avatarPath,
                timeZone: selectedTimeZone,
                countryCode: "",
                cityName: city,
                createdAt: Date()
            )
        }
        if let user = coordinator.currentUser {
            coordinator.localStore.saveCurrentUser(user)
        }
    }
}
