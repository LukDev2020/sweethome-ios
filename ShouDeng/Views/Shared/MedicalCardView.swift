import SwiftUI

// MARK: - Medical Card View
//
// Emergency medical profile: blood type, allergies, meds, insurance.
// Designed for lock-screen visibility — first responders need this
// without unlocking the phone.

struct MedicalCardView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    /// Optional target user ID — when a guardian edits a protected person's card
    var targetUserId: String?
    var targetUserName: String?

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var card = MedicalCardData.empty
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showPreview = false
    @State private var saveResult: SaveResult?

    private enum SaveResult {
        case success, failure(String)
    }

    // Editing fields
    @State private var newAllergy = ""
    @State private var newMedication = ""
    @State private var newCondition = ""

    private var apiPath: String {
        if let userId = targetUserId {
            return "/v1/medical-card/\(userId)"
        }
        return "/v1/medical-card"
    }

    private var navTitle: String {
        if let name = targetUserName {
            return "\(name)的医疗卡"
        }
        return "紧急医疗卡"
    }

    private let bloodTypes = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    formView
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveCard() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存").bold()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showPreview) {
                MedicalCardPreview(card: card, userName: coordinator.currentUser?.displayName ?? "")
            }
            .overlay(alignment: .top) {
                if let result = saveResult {
                    HStack(spacing: 6) {
                        switch result {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("已保存")
                        case .failure(let msg):
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(msg)
                        }
                    }
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(.systemGray2)))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 4)
                }
            }
            .task { await loadCard() }
        }
    }

    private var formView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Preview button
                Button { showPreview = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.fill")
                        Text("预览急救卡")
                            .font(.scaled(size: 14, weight: .medium))
                    }
                    .foregroundStyle(safe)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(safe.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Blood Type
                section(title: "血型") {
                    Picker("血型", selection: Binding(
                        get: { card.bloodType ?? "" },
                        set: { card.bloodType = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("未设置").tag("")
                        ForEach(bloodTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Allergies
                section(title: "过敏史") {
                    tagList(items: card.allergies) { card.allergies.remove(at: $0) }
                    addField(text: $newAllergy, placeholder: "添加过敏原 (如 青霉素)") {
                        card.allergies.append(newAllergy)
                        newAllergy = ""
                    }
                }

                // Medications (structured)
                medicationItemsSection

                // Conditions
                section(title: "既往病史") {
                    tagList(items: card.conditions) { card.conditions.remove(at: $0) }
                    addField(text: $newCondition, placeholder: "添加病史 (如 哮喘)") {
                        card.conditions.append(newCondition)
                        newCondition = ""
                    }
                }

                // Insurance
                section(title: "保险信息") {
                    TextField("保险公司", text: Binding(
                        get: { card.insuranceProvider ?? "" },
                        set: { card.insuranceProvider = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    TextField("保单号", text: Binding(
                        get: { card.insurancePolicyNumber ?? "" },
                        set: { card.insurancePolicyNumber = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                // Emergency Note
                section(title: "紧急备注") {
                    TextField("其他重要信息", text: Binding(
                        get: { card.emergencyNote ?? "" },
                        set: { card.emergencyNote = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                // Organ Donor
                section(title: "其他") {
                    Toggle("器官捐献意愿", isOn: $card.organDonor)
                        .tint(safe)
                }

                Text("此信息存储在服务器，可通过紧急分享链接供急救人员查看。不需要解锁手机。")
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Medication Items Section

    private var medicationItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("药品管理")
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("标记为急救的药品将显示在锁屏")
                    .font(.scaled(size: 10))
                    .foregroundStyle(.tertiary)
            }

            ForEach(Array(card.medicationItems.enumerated()), id: \.element.id) { index, item in
                medicationItemCard(index: index, item: item)
            }

            // Add new medication button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    card.medicationItems.append(MedicationItem())
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.scaled(size: 14))
                    Text("添加药品")
                        .font(.scaled(size: 13, weight: .medium))
                }
                .foregroundStyle(safe)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(safe.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("添加")

            // Legacy medications migration hint
            if !card.medications.isEmpty && card.medicationItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("旧版药物记录")
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(card.medications, id: \.self) { med in
                        Text("• \(med)")
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Button("转换为新格式") {
                        for med in card.medications {
                            card.medicationItems.append(MedicationItem(name: med))
                        }
                        card.medications = []
                    }
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(safe)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func medicationItemCard(index: Int, item: MedicationItem) -> some View {
        VStack(spacing: 8) {
            // Header row: name + emergency toggle + delete
            HStack(spacing: 8) {
                Image(systemName: item.isEmergency ? "cross.circle.fill" : "pill.fill")
                    .font(.scaled(size: 14))
                    .foregroundStyle(item.isEmergency ? alert : ink.opacity(0.5))

                TextField("药品名称", text: $card.medicationItems[index].name)
                    .font(.scaled(size: 14, weight: .medium))

                Spacer()

                // Emergency toggle
                Button {
                    card.medicationItems[index].isEmergency.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: item.isEmergency ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                            .font(.scaled(size: 10))
                        Text("急救")
                            .font(.scaled(size: 10, weight: .medium))
                    }
                    .foregroundStyle(item.isEmergency ? .white : .orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(item.isEmergency ? Color.orange : Color.orange.opacity(0.1)))
                }
                .accessibilityLabel("标记为急救药物")

                // Delete
                Button {
                    withAnimation { _ = card.medicationItems.remove(at: index) }
                } label: {
                    Image(systemName: "trash")
                        .font(.scaled(size: 12))
                        .foregroundStyle(.red.opacity(0.6))
                }
            }

            // Location + Dosage fields
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle")
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("放置位置 (如 床头柜)", text: $card.medicationItems[index].storageLocation)
                        .font(.scaled(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("服用方法 (如 每日2次)", text: $card.medicationItems[index].dosage)
                        .font(.scaled(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(item.isEmergency ? Color.orange.opacity(0.04) : Color(.systemGray6).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(item.isEmergency ? Color.orange.opacity(0.2) : Color(.separator).opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func tagList(items: [String], onRemove: @escaping (Int) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 4) {
                    Text(item)
                        .font(.scaled(size: 13))
                    Button { onRemove(index) } label: {
                        Image(systemName: "xmark")
                            .font(.scaled(size: 9, weight: .bold))
                    }
                    .accessibilityLabel("删除")
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
            }
        }
    }

    private func addField(text: Binding<String>, placeholder: String, onAdd: @escaping () -> Void) -> some View {
        HStack {
            TextField(placeholder, text: text)
                .font(.scaled(size: 13))
                .textFieldStyle(.roundedBorder)
            Button {
                guard !text.wrappedValue.isEmpty else { return }
                onAdd()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(safe)
            }
        }
    }

    // MARK: - Actions

    private func loadCard() async {
        // Show cached data immediately (no spinner wait)
        let cached = loadCachedMedicalCard()
        if let cached {
            card = cached
            isLoading = false
        }

        // Try server in background, update if successful
        if let loaded: MedicalCardData = try? await coordinator.apiClient.get(apiPath) {
            if let cached, !cached.medicationItems.isEmpty && loaded.medicationItems.isEmpty {
                // Local cache has medication items server doesn't — keep local
            } else {
                await MainActor.run { card = loaded }
                cacheMedicalCard(loaded)
            }
        }

        // If no cache and no server, show empty form
        await MainActor.run { isLoading = false }
    }

    private func saveCard() async {
        isSaving = true

        // Optimistic: cache locally + show success immediately
        cacheMedicalCard(card)
        isSaving = false
        withAnimation(.easeInOut(duration: 0.3)) { saveResult = .success }

        // Background: widget sync + Live Activity refresh + server save (non-blocking)
        let cardCopy = card
        let path = apiPath
        coordinator.syncWidgetState()
        // Refresh Live Activity with updated medical data
        coordinator.startLiveActivityIfNeeded()
        Task.detached(priority: .utility) {
            do {
                let _: SuccessResponse = try await coordinator.apiClient.put(path, body: cardCopy)
            } catch {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        saveResult = .failure("已本地保存，服务器同步失败")
                    }
                }
                #if DEBUG
                print("[MedicalCard] save error: \(error)")
                #endif
            }
        }

        // Auto-dismiss toast after 1.5s
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        withAnimation(.easeInOut(duration: 0.3)) { saveResult = nil }
    }

    private static let cacheEncoder = JSONEncoder()
    private static let cacheDecoder = JSONDecoder()

    private func cacheMedicalCard(_ data: MedicalCardData) {
        if let encoded = try? Self.cacheEncoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: "medical_card_cache")
        }
    }

    private func loadCachedMedicalCard() -> MedicalCardData? {
        guard let data = UserDefaults.standard.data(forKey: "medical_card_cache"),
              let card = try? Self.cacheDecoder.decode(MedicalCardData.self, from: data) else {
            return nil
        }
        return card
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}

// MARK: - Medical Card Preview (lock screen style)

struct MedicalCardPreview: View {
    let card: MedicalCardData
    let userName: String
    @Environment(\.dismiss) private var dismiss

    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    HStack {
                        Image(systemName: "staroflife.fill")
                            .font(.scaled(size: 24))
                            .foregroundStyle(alert)
                        Text("紧急医疗信息")
                            .font(.scaled(size: 20, weight: .bold))
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    if !userName.isEmpty {
                        previewRow("姓名", value: userName)
                    }

                    if let blood = card.bloodType {
                        previewRow("血型", value: blood)
                    }

                    if !card.allergies.isEmpty {
                        previewRow("过敏", value: card.allergies.joined(separator: "、"))
                    }

                    if !card.medicationItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("药物")
                                .font(.scaled(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            ForEach(card.medicationItems) { med in
                                HStack(spacing: 8) {
                                    if med.isEmergency {
                                        Image(systemName: "cross.circle.fill")
                                            .font(.scaled(size: 14))
                                            .foregroundStyle(alert)
                                    } else {
                                        Image(systemName: "pill.fill")
                                            .font(.scaled(size: 14))
                                            .foregroundStyle(.secondary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(med.name)
                                            .font(.scaled(size: 16, weight: .semibold))
                                        if !med.storageLocation.isEmpty {
                                            HStack(spacing: 3) {
                                                Image(systemName: "mappin.circle")
                                                    .font(.scaled(size: 10))
                                                Text(med.storageLocation)
                                                    .font(.scaled(size: 13))
                                            }
                                            .foregroundStyle(.secondary)
                                        }
                                        if !med.dosage.isEmpty {
                                            HStack(spacing: 3) {
                                                Image(systemName: "clock")
                                                    .font(.scaled(size: 10))
                                                Text(med.dosage)
                                                    .font(.scaled(size: 13))
                                            }
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if med.isEmergency {
                                        Text("急救")
                                            .font(.scaled(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(alert))
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(med.isEmergency ? alert.opacity(0.08) : Color(.systemGray6))
                                )
                            }
                        }
                    } else if !card.medications.isEmpty {
                        previewRow("药物", value: card.medications.joined(separator: "、"))
                    }

                    if !card.conditions.isEmpty {
                        previewRow("病史", value: card.conditions.joined(separator: "、"))
                    }

                    if let provider = card.insuranceProvider {
                        previewRow("保险", value: provider + (card.insurancePolicyNumber.map { " #\($0)" } ?? ""))
                    }

                    if let note = card.emergencyNote, !note.isEmpty {
                        previewRow("备注", value: note)
                    }

                    if card.organDonor {
                        previewRow("器官捐献", value: "同意")
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("急救卡预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func previewRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.scaled(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.scaled(size: 18, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
