import SwiftUI
import TipKit
import PhotosUI

// MARK: - Family Feed View ("家庭圈")
//
// Chat-style family feed. Both guardians and protected persons can:
//   - Send text messages and photos
//   - Edit/delete their own messages
//   - Reply with inline comments
//   - Pull to refresh
//
// Refreshes when shown, when the app comes back to the foreground, after sending,
// and every 30 s while visible. A failed refresh says so (error with Retry when
// nothing is cached, a banner over cached posts). Unsent posts show "Not sent"
// with Retry / Delete.

struct FamilyFeedView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let creamBg = Color(red: 254/255, green: 252/255, blue: 247/255)
    private let offWhiteBg = Color(red: 251/255, green: 248/255, blue: 241/255)
    private let paneBorder = Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.13)

    @State private var isLoading = false
    @State private var messageText = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var selectedImageData: [Data] = []
    @State private var isSending = false
    @FocusState private var isInputFocused: Bool
    /// The SOS button, handed over by the tab container (see DuoTabItem.placesOwnAccessory)
    @Environment(\.tabBottomAccessory) private var sosAccessory

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    feedDuoPane.safeAreaInset(edge: .bottom, spacing: 0) { sosRow }
                } else {
                    feedCompact
                }
            }
            .onTapGesture {
                isInputFocused = false
            }
            .navigationTitle(langManager.localized("familyFeed.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(sizeClass == .regular ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        InviteCodeTip().invalidate(reason: .actionPerformed)
                        coordinator.presentInviteAccept()
                    } label: {
                        Label(langManager.localized("familyFeed.enterInviteCode"), systemImage: "key")
                    }
                    .accessibilityIdentifier("familyFeed.enterInviteCode")
                    .appTip(AppTips.available(InviteCodeTip()), arrowEdge: .top)
                }
            }
            .task {
                // Runs while the feed is on screen (cancelled when it goes away)
                await loadPosts()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: Self.refreshInterval)
                    guard !Task.isCancelled else { break }
                    if scenePhase == .active { await loadPosts() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await loadPosts() } }
            }
        }
    }

    private static let refreshInterval: UInt64 = 30_000_000_000

    /// Messages, a load error, or the empty state.
    @ViewBuilder
    private var feedContent: some View {
        if coordinator.familyPosts.isEmpty && !isLoading {
            if coordinator.familyFeedRefreshFailed {
                loadErrorState
            } else {
                emptyState
            }
        } else {
            VStack(spacing: 0) {
                if coordinator.familyFeedRefreshFailed && !coordinator.familyPosts.isEmpty {
                    refreshFailedBanner
                }
                messageList
            }
        }
    }

    // MARK: - Compact Layout

    private var feedCompact: some View {
        feedContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    sosRow
                    chatInputBar
                }
            }
            .background(Color(.systemGroupedBackground))
    }

    /// SOS stays one tap away, just above the composer (never on top of it).
    @ViewBuilder
    private var sosRow: some View {
        if let sosAccessory {
            HStack {
                Spacer()
                sosAccessory
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Duo Pane Layout

    private var feedDuoPane: some View {
        FoldSplitView(dividerColor: paneBorder) {
            // Left: messages + input
            VStack(spacing: 0) {
                feedContent
                chatInputBar
            }
            .background(creamBg)
        } trailing: {
            // Right: family members panel
            ScrollView {
                VStack(spacing: 12) {
                    Text(langManager.localized("familyFeed.members"))
                        .font(.scaled(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)

                    familyMembersPanel

                    enterInviteCodeButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(offWhiteBg)
        }
    }

    // MARK: - Enter Invite Code (Duo right pane; compact uses the toolbar)

    private var enterInviteCodeButton: some View {
        Button {
            coordinator.presentInviteAccept()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "key")
                Text(langManager.localized("familyFeed.enterInviteCode"))
                    .font(.scaled(size: 14, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 11))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(ink)
            .padding(12)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(RoundedRectangle(cornerRadius: 12).stroke(paneBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Family Members Panel (Duo right pane)

    private var familyMembersPanel: some View {
        VStack(spacing: 0) {
            // Show protected persons (if guardian) or guardians (if protected)
            let persons = coordinator.protectedPersons
            let guardians = coordinator.myGuardians

            if !persons.isEmpty {
                ForEach(persons) { person in
                    memberRow(
                        name: person.user.displayName,
                        initial: person.user.avatarInitial,
                        city: person.user.cityName,
                        role: langManager.localized("familyFeed.roleProtected")
                    )
                }
            }

            if !guardians.isEmpty {
                ForEach(guardians) { guardian in
                    memberRow(
                        name: guardian.user.displayName,
                        initial: guardian.user.avatarInitial,
                        city: guardian.user.cityName,
                        role: langManager.localized("familyFeed.roleGuardian")
                    )
                }
            }

            // Current user
            if let user = coordinator.currentUser {
                memberRow(
                    name: user.displayName.isEmpty ? langManager.localized("familyFeed.me") : user.displayName,
                    initial: user.avatarInitial,
                    city: user.cityName,
                    role: user.role == .guardian ? langManager.localized("familyFeed.roleGuardianMe") : langManager.localized("familyFeed.roleProtectedMe")
                )
            }

            if persons.isEmpty && guardians.isEmpty && coordinator.currentUser == nil {
                VStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .font(.scaled(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(langManager.localized("familyFeed.noMembers"))
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func memberRow(name: String, initial: String, city: String, role: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(safe.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text(initial)
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .font(.scaled(size: 14, weight: .medium))
                    .foregroundStyle(safe)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundStyle(ink)
                HStack(spacing: 4) {
                    Text(role)
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                    if !city.isEmpty {
                        Text("·")
                            .font(.scaled(size: 12))
                            .foregroundStyle(.quaternary)
                        Text(city)
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.15))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.scaled(size: 44))
                .foregroundStyle(safe.opacity(0.35))
            Text(langManager.localized("familyFeed.empty"))
                .font(.scaled(size: 16, weight: .medium))
                .foregroundStyle(ink)
            Text(langManager.localized("familyFeed.emptyHint"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                Task { await loadPosts() }
            } label: {
                Text(langManager.localized("familyFeed.retry"))
                    .font(.scaled(size: 14, weight: .semibold))
            }
            #if BETA || DEBUG
            if let diagnostic = coordinator.familyFeedDiagnostic {
                Text(diagnostic)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            #endif
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Load Errors

    private var loadErrorState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.scaled(size: 40))
                .foregroundStyle(lamp)
            Text(langManager.localized("familyFeed.loadFailed"))
                .font(.scaled(size: 16, weight: .medium))
                .foregroundStyle(ink)
            Text(langManager.localized("familyFeed.loadFailedHint"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                Task { await loadPosts() }
            } label: {
                Text(langManager.localized("familyFeed.retry"))
                    .font(.scaled(size: 15, weight: .semibold))
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.borderedProminent)
            .tint(safe)
            .accessibilityIdentifier("familyFeed.retry")
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var refreshFailedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.scaled(size: 12))
                .foregroundStyle(lamp)
            Text(langManager.localized("familyFeed.refreshFailed"))
                .font(.scaled(size: 12))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(langManager.localized("familyFeed.retry")) {
                Task { await loadPosts() }
            }
            .font(.scaled(size: 12, weight: .semibold))
            .foregroundStyle(safe)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(lamp.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("familyFeed.refreshFailed")
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
                            .font(.scaled(size: 12, weight: .medium))
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
            .scrollDismissesKeyboard(.interactively)
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
        if cal.isDateInToday(date) { return langManager.localized("familyFeed.today") }
        if cal.isDateInYesterday(date) { return langManager.localized("familyFeed.yesterday") }
        // Month and day in the app's language ("Nov 5", "5 nov.", "11月5日")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: langManager.current.rawValue)
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
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
                                    if index < selectedImageData.count {
                                        selectedImageData.remove(at: index)
                                    }
                                    if index < selectedItems.count {
                                        selectedItems.remove(at: index)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.scaled(size: 16))
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
                AvatarView(user: coordinator.currentUser, size: 28)

                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 9,
                    matching: .images
                ) {
                    Image(systemName: "photo")
                        .font(.scaled(size: 20))
                        .foregroundStyle(safe)
                }

                // Text field
                TextField(langManager.localized("familyFeed.sendMessage"), text: $messageText)
                    .font(.scaled(size: 15))
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
                            .font(.scaled(size: 32))
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

    /// Refreshes the feed. The spinner only shows while there is nothing to show yet;
    /// the request's own timeout ends it (an error then replaces it, never "empty").
    private func loadPosts() async {
        let showSpinner = coordinator.familyPosts.isEmpty
        if showSpinner { isLoading = true }
        await coordinator.fetchFamilyPosts()
        if showSpinner { isLoading = false }
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        var datas: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
                datas.append(data)
            }
        }
        await MainActor.run {
            selectedImages = images
            selectedImageData = datas
        }
    }

    private func sendMessage() async {
        guard canSend, !isSending else { return }
        isSending = true
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = selectedImageData

        // Clear input immediately; the post shows as "sending" right away
        messageText = ""
        selectedImages = []
        selectedImageData = []
        selectedItems = []

        let id = await coordinator.queueFamilyPost(text: text, images: images)
        isSending = false
        if let id { await coordinator.sendFamilyPost(id: id) }
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
    @State private var commentFailed = false
    @State private var isSendingComment = false

    private var isOwnMessage: Bool {
        post.authorId == coordinator.currentUser?.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isOwnMessage { Spacer(minLength: 48) }

            if !isOwnMessage {
                // Other user's avatar — use post data
                AvatarView(user: nil, size: 30,
                           initial: post.authorInitial,
                           avatarPath: post.authorAvatarPath)
            }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 3) {
                // Name + time + location
                if !isOwnMessage {
                    HStack(spacing: 4) {
                        Text(post.authorName)
                            .font(.scaled(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(timeString(post.createdAt))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.tertiary)
                        if let locName = post.locationName, !locName.isEmpty {
                            Image(systemName: "location.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Text(locName)
                                .font(.scaled(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Bubble
                VStack(alignment: .leading, spacing: 6) {
                    // Editing mode
                    if isEditing {
                        TextField(LanguageManager.shared.localized("familyFeed.editMessage"), text: $editText, axis: .vertical)
                            .font(.scaled(size: 14))
                            .lineLimit(1...10)
                        HStack(spacing: 12) {
                            Button(LanguageManager.shared.localized("familyFeed.cancel")) {
                                isEditing = false
                            }
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                            Button(LanguageManager.shared.localized("familyFeed.save")) {
                                saveEdit()
                            }
                            .font(.scaled(size: 12, weight: .medium))
                            .foregroundStyle(safe)
                        }
                    } else {
                        // Text content
                        if !post.text.isEmpty {
                            Text(post.text)
                                .font(.scaled(size: 14))
                                .foregroundStyle(isOwnMessage ? .white : ink)
                                .lineSpacing(2)
                        }
                    }

                    // Media
                    if !post.mediaURLs.isEmpty || !(post.delivery?.pendingImages.isEmpty ?? true) {
                        mediaGrid
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isOwnMessage ? safe : Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                .opacity(post.isUnsent ? 0.6 : 1)
                .onLongPressGesture {
                    if isOwnMessage { showActions = true }
                }
                .confirmationDialog(LanguageManager.shared.localized("familyFeed.messageActions"), isPresented: $showActions) {
                    if post.isUnsent {
                        if post.delivery?.state == .failed {
                            Button(LanguageManager.shared.localized("familyFeed.retry")) { retrySend() }
                            Button(LanguageManager.shared.localized("familyFeed.deleteMsg"), role: .destructive) {
                                coordinator.deleteUnsentFamilyPost(id: post.id)
                            }
                        }
                    } else {
                        Button(LanguageManager.shared.localized("familyFeed.edit")) {
                            editText = post.text
                            isEditing = true
                        }
                        Button(LanguageManager.shared.localized("familyFeed.deleteMsg"), role: .destructive) {
                            deletePost()
                        }
                    }
                    Button(LanguageManager.shared.localized("familyFeed.cancel"), role: .cancel) {}
                }

                if let delivery = post.delivery {
                    deliveryRow(delivery)
                }

                // Time + location for own messages
                if isOwnMessage {
                    HStack(spacing: 4) {
                        Text(timeString(post.createdAt))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.tertiary)
                        if let locName = post.locationName, !locName.isEmpty {
                            Image(systemName: "location.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Text(locName)
                                .font(.scaled(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Reaction bar (not for a post the server doesn't have yet)
                if !post.isUnsent {
                    ReactionBarView(postId: post.id)
                }

                // Comment count / reply button
                if !post.isUnsent && (post.commentCount > 0 || showComments) {
                    Button {
                        showComments.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "bubble.right")
                                .font(.scaled(size: 10))
                            Text(String(format: LanguageManager.shared.localized("familyFeed.replies"), post.commentCount))
                                .font(.scaled(size: 12))
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                // Comments
                if showComments && !post.isUnsent {
                    commentsSection
                }
            }

            if isOwnMessage {
                // Own avatar — always use live user data
                AvatarView(user: coordinator.currentUser, size: 30)
            }

            if !isOwnMessage { Spacer(minLength: 48) }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Delivery

    /// "Sending…" or "Not sent · Retry · Delete" under an unsent post.
    private func deliveryRow(_ delivery: FamilyPostDelivery) -> some View {
        HStack(spacing: 8) {
            if delivery.state == .sending {
                ProgressView()
                    .controlSize(.mini)
                Text(LanguageManager.shared.localized("familyFeed.sending"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.scaled(size: 12))
                    .foregroundStyle(.red)
                Text(LanguageManager.shared.localized("familyFeed.notSent"))
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                Button(LanguageManager.shared.localized("familyFeed.retry")) { retrySend() }
                    .font(.scaled(size: 12, weight: .semibold))
                    .foregroundStyle(safe)
                    .accessibilityIdentifier("familyFeed.retrySend")
                Button(LanguageManager.shared.localized("familyFeed.deleteMsg"), role: .destructive) {
                    coordinator.deleteUnsentFamilyPost(id: post.id)
                }
                .font(.scaled(size: 12))
            }
        }
        .buttonStyle(.plain)
    }

    private func retrySend() {
        let id = post.id
        Task { await coordinator.sendFamilyPost(id: id) }
    }

    // MARK: - Media

    private enum MediaItem: Hashable {
        case remote(String)
        case pending(String)
    }

    private var mediaGrid: some View {
        let items = post.mediaURLs.map(MediaItem.remote) + (post.delivery?.pendingImages ?? []).map(MediaItem.pending)
        let columns = items.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
        let maxH: CGFloat = items.count == 1 ? 220 : 120

        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(items, id: \.self) { item in
                switch item {
                case .pending(let name):
                    LocalFamilyImage(maxHeight: maxH) { coordinator.localStore.loadFamilyMedia(name: name) }
                case .remote(let urlString):
                    remoteImage(urlString, maxHeight: maxH)
                }
            }
        }
    }

    @ViewBuilder
    private func remoteImage(_ urlString: String, maxHeight maxH: CGFloat) -> some View {
        if urlString.hasPrefix("file://"),
           let fileURL = URL(string: urlString),
           let uiImage = UIImage(contentsOfFile: fileURL.path) {
            // Posts from older builds may still point at a file on this phone
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(minHeight: 80, maxHeight: maxH)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let url = URL(string: urlString), url.host == DemoURLProtocol.host {
            // Explore Mode: photos "uploaded" to the demo live in memory
            LocalFamilyImage(maxHeight: maxH) { DemoURLProtocol.store?.mediaData(for: url) }
        } else {
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(minHeight: 80, maxHeight: maxH)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    mediaPlaceholder
                case .empty:
                    ProgressView()
                        .frame(height: 80)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    private var mediaPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray6))
            .frame(height: 80)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(post.comments) { comment in
                HStack(alignment: .top, spacing: 5) {
                    AvatarView(user: comment.authorId == coordinator.currentUser?.id ? coordinator.currentUser : nil,
                               size: 18,
                               initial: comment.authorInitial,
                               avatarPath: comment.authorAvatarPath)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Text(comment.authorName)
                                .font(.scaled(size: 12, weight: .medium))
                            Text(timeString(comment.createdAt))
                                .font(.scaled(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Text(comment.text)
                            .font(.scaled(size: 13))
                    }
                }
            }

            HStack(spacing: 6) {
                TextField(LanguageManager.shared.localized("familyFeed.reply"), text: $commentText)
                    .font(.scaled(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                Button {
                    let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, !isSendingComment else { return }
                    isSendingComment = true
                    Task {
                        let sent = await coordinator.addComment(postId: post.id, text: text)
                        // Keep the text when it didn't go out, so nothing is lost
                        if sent { commentText = "" }
                        commentFailed = !sent
                        isSendingComment = false
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.scaled(size: 22))
                        .foregroundStyle(safe)
                }
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingComment)
            }

            if commentFailed {
                Text(LanguageManager.shared.localized("familyFeed.replyFailed"))
                    .font(.scaled(size: 11))
                    .foregroundStyle(.red)
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
        if let idx = coordinator.familyPosts.firstIndex(where: { $0.id == post.id }) {
            coordinator.familyPosts[idx].text = newText
        }
        coordinator.persistFamilyPosts()
        Task {
            do {
                let _: EmptyResponse = try await coordinator.apiClient.put(
                    "/v1/family/posts/\(post.id)",
                    body: ["text": newText]
                )
            } catch {
                #if DEBUG
                print("[FamilyFeed] Edit post failed: \(error)")
                #endif
            }
        }
        isEditing = false
    }

    private func deletePost() {
        let postId = post.id
        coordinator.familyPosts.removeAll { $0.id == postId }
        coordinator.persistFamilyPosts()
        Task {
            do {
                let _: EmptyResponse = try await coordinator.apiClient.delete(
                    "/v1/family/posts/\(postId)"
                )
            } catch {
                #if DEBUG
                print("[FamilyFeed] Delete post failed: \(error)")
                #endif
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return LanguageManager.shared.localized("familyFeed.justNow") }
        if diff < 3600 { return String(format: LanguageManager.shared.localized("familyFeed.minutesAgo"), Int(diff / 60)) }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Local image (unsent photo, Explore Mode photo)

/// Decodes image data off the main thread once and shows it like a feed photo.
private struct LocalFamilyImage: View {
    let maxHeight: CGFloat
    let load: () -> Data?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minHeight: 80, maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .frame(height: 80)
            }
        }
        .task {
            guard image == nil, let data = load() else { return }
            image = await Task.detached(priority: .userInitiated) { UIImage(data: data)?.preparingForDisplay() }.value
        }
    }
}
