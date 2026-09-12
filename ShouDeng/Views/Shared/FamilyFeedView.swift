import SwiftUI
import PhotosUI

// MARK: - Family Feed View ("家庭圈")
//
// Chat-style family feed. Both guardians and protected persons can:
//   - Send text messages and photos
//   - Edit/delete their own messages
//   - Reply with inline comments
//   - Pull to refresh

struct FamilyFeedView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    @State private var isLoading = false
    @State private var messageText = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isSending = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                Group {
                    if coordinator.familyPosts.isEmpty && !isLoading {
                        emptyState
                    } else {
                        messageList
                    }
                }

                // Chat input bar
                chatInputBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("家庭圈")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadPosts()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(safe.opacity(0.35))
            Text("家庭圈还没有消息")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ink)
            Text("发一条消息，分享照片或生活点滴")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Date headers + messages
                    ForEach(Array(groupedByDate.enumerated()), id: \.offset) { _, group in
                        // Date header
                        Text(group.dateLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)

                        ForEach(group.posts) { post in
                            MessageBubbleView(post: post)
                                .environmentObject(coordinator)
                                .id(post.id)
                        }
                    }

                    if isLoading {
                        ProgressView()
                            .padding(16)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .refreshable {
                await loadPosts()
            }
            .onChange(of: coordinator.familyPosts.count) {
                if let last = coordinator.familyPosts.first {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var groupedByDate: [(dateLabel: String, posts: [FamilyPost])] {
        let cal = Calendar.current
        var groups: [(dateLabel: String, posts: [FamilyPost])] = []
        var currentLabel = ""
        var currentPosts: [FamilyPost] = []

        // Posts are newest-first from API, reverse for chat order
        for post in coordinator.familyPosts.reversed() {
            let label = dateLabel(for: post.createdAt, cal: cal)
            if label != currentLabel {
                if !currentPosts.isEmpty {
                    groups.append((currentLabel, currentPosts))
                }
                currentLabel = label
                currentPosts = [post]
            } else {
                currentPosts.append(post)
            }
        }
        if !currentPosts.isEmpty {
            groups.append((currentLabel, currentPosts))
        }
        return groups
    }

    private func dateLabel(for date: Date, cal: Calendar) -> String {
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    // MARK: - Chat Input Bar

    private var chatInputBar: some View {
        VStack(spacing: 0) {
            Divider()

            // Image preview strip
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Button {
                                    selectedImages.remove(at: index)
                                    if index < selectedItems.count {
                                        selectedItems.remove(at: index)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(Color(.systemBackground))
            }

            // Input row
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 9,
                    matching: .any(of: [.images, .videos])
                ) {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(safe)
                }

                // Text field
                TextField("发消息...", text: $messageText)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        guard canSend else { return }
                        Task { await sendMessage() }
                    }

                // Send button
                Button {
                    Task { await sendMessage() }
                } label: {
                    if isSending {
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSend ? safe : Color(.systemGray4))
                    }
                }
                .disabled(!canSend || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .onChange(of: selectedItems) { _, newItems in
            Task { await loadImages(from: newItems) }
        }
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty
    }

    // MARK: - Actions

    private func loadPosts() async {
        isLoading = true
        await coordinator.fetchFamilyPosts()
        isLoading = false
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        await MainActor.run { selectedImages = images }
    }

    private func sendMessage() async {
        guard canSend else { return }
        isSending = true
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Save images to temp files before clearing, so they persist through the send flow
        let imagesToUpload = selectedImages
        var localFileURLs: [String] = []
        for (i, image) in imagesToUpload.enumerated() {
            if let data = image.jpegData(compressionQuality: 0.85) {
                let filename = "chat_\(UUID().uuidString)_\(i).jpg"
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try? data.write(to: fileURL)
                localFileURLs.append(fileURL.absoluteString)
            }
        }

        // Clear input immediately for responsive feel
        await MainActor.run {
            messageText = ""
            selectedImages = []
            selectedItems = []
        }

        // Upload images to server
        var remoteURLs: [String] = []
        for image in imagesToUpload {
            if let data = image.jpegData(compressionQuality: 0.7) {
                do {
                    let url = try await coordinator.uploadMedia(data: data, mimeType: "image/jpeg")
                    remoteURLs.append(url)
                } catch {
                    #if DEBUG
                    print("[FamilyFeed] Upload failed: \(error)")
                    #endif
                }
            }
        }

        // Use remote URLs if upload succeeded, otherwise fall back to local file URLs
        let finalMediaURLs = remoteURLs.isEmpty ? localFileURLs : remoteURLs

        // Don't create an empty post (no text and no images)
        guard !text.isEmpty || !finalMediaURLs.isEmpty else {
            isSending = false
            return
        }

        // Create post — if API fails, add locally so chat still works
        do {
            try await coordinator.createFamilyPost(text: text, mediaURLs: finalMediaURLs)
        } catch {
            #if DEBUG
            print("[FamilyFeed] Send failed (adding locally): \(error)")
            #endif
            let localPost = FamilyPost(
                id: UUID().uuidString,
                authorId: coordinator.currentUser?.id ?? "local",
                authorName: coordinator.currentUser?.displayName ?? "我",
                authorInitial: coordinator.currentUser?.avatarInitial ?? "我",
                text: text,
                mediaURLs: finalMediaURLs,
                createdAt: Date(),
                comments: [],
                commentCount: 0
            )
            await MainActor.run {
                coordinator.familyPosts.insert(localPost, at: 0)
            }
        }

        isSending = false
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let post: FamilyPost

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    @State private var showComments = false
    @State private var commentText = ""
    @State private var isEditing = false
    @State private var editText = ""
    @State private var showActions = false

    private var isOwnMessage: Bool {
        post.authorId == coordinator.currentUser?.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isOwnMessage { Spacer(minLength: 48) }

            if !isOwnMessage {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 30, height: 30)
                    Text(post.authorInitial)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ink)
                }
            }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 3) {
                // Name + time
                if !isOwnMessage {
                    HStack(spacing: 4) {
                        Text(post.authorName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(timeString(post.createdAt))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Bubble
                VStack(alignment: .leading, spacing: 6) {
                    // Editing mode
                    if isEditing {
                        TextField("编辑消息", text: $editText, axis: .vertical)
                            .font(.system(size: 14))
                            .lineLimit(1...10)
                        HStack(spacing: 12) {
                            Button("取消") {
                                isEditing = false
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            Button("保存") {
                                saveEdit()
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(safe)
                        }
                    } else {
                        // Text content
                        if !post.text.isEmpty {
                            Text(post.text)
                                .font(.system(size: 14))
                                .foregroundStyle(isOwnMessage ? .white : ink)
                                .lineSpacing(2)
                        }
                    }

                    // Media
                    if !post.mediaURLs.isEmpty {
                        mediaGrid
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isOwnMessage ? safe : Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                .onLongPressGesture {
                    if isOwnMessage { showActions = true }
                }
                .confirmationDialog("消息操作", isPresented: $showActions) {
                    Button("编辑") {
                        editText = post.text
                        isEditing = true
                    }
                    Button("删除", role: .destructive) {
                        deletePost()
                    }
                    Button("取消", role: .cancel) {}
                }

                // Time for own messages
                if isOwnMessage {
                    Text(timeString(post.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // Comment count / reply button
                if post.commentCount > 0 || showComments {
                    Button {
                        showComments.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 10))
                            Text("\(post.commentCount) 条回复")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                // Comments
                if showComments {
                    commentsSection
                }
            }

            if !isOwnMessage { Spacer(minLength: 48) }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Media

    private var mediaGrid: some View {
        let urls = post.mediaURLs
        let columns = urls.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
        let maxH: CGFloat = urls.count == 1 ? 220 : 120

        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(urls, id: \.self) { urlString in
                if urlString.hasPrefix("file://"),
                   let fileURL = URL(string: urlString),
                   let uiImage = UIImage(contentsOfFile: fileURL.path) {
                    // Local file image
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(minHeight: 80, maxHeight: maxH)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // Remote URL image
                    AsyncImage(url: URL(string: urlString)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(minHeight: 80, maxHeight: maxH)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                                .frame(height: 80)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                        case .empty:
                            ProgressView()
                                .frame(height: 80)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(post.comments) { comment in
                HStack(alignment: .top, spacing: 5) {
                    Text(comment.authorInitial)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(ink)
                        .frame(width: 18, height: 18)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Text(comment.authorName)
                                .font(.system(size: 10, weight: .medium))
                            Text(timeString(comment.createdAt))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        Text(comment.text)
                            .font(.system(size: 12))
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("回复...", text: $commentText)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                Button {
                    guard !commentText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task {
                        await coordinator.addComment(postId: post.id, text: commentText)
                        commentText = ""
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(safe)
                }
                .disabled(commentText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(8)
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func saveEdit() {
        let newText = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty else { return }
        // Update locally
        if let idx = coordinator.familyPosts.firstIndex(where: { $0.id == post.id }) {
            coordinator.familyPosts[idx].text = newText
        }
        // TODO: API call PUT /v1/family/posts/:id
        isEditing = false
    }

    private func deletePost() {
        coordinator.familyPosts.removeAll { $0.id == post.id }
        // TODO: API call DELETE /v1/family/posts/:id
    }

    private func timeString(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60))分钟前" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
