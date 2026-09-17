import SwiftUI

// MARK: - Medical Card View
//
// Emergency medical profile: blood type, allergies, meds, insurance.
// Designed for lock-screen visibility — first responders need this
// without unlocking the phone.

struct MedicalCardView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var card = MedicalCardData.empty
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showPreview = false

    // Editing fields
    @State private var newAllergy = ""
    @State private var newMedication = ""
    @State private var newCondition = ""

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
            .navigationTitle("紧急医疗卡")
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
                            .font(.system(size: 14, weight: .medium))
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

                // Medications
                section(title: "正在服用的药物") {
                    tagList(items: card.medications) { card.medications.remove(at: $0) }
                    addField(text: $newMedication, placeholder: "添加药物名称") {
                        card.medications.append(newMedication)
                        newMedication = ""
                    }
                }

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
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Helpers

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11))
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
                        .font(.system(size: 13))
                    Button { onRemove(index) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
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
                .font(.system(size: 13))
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
        isLoading = true
        defer { isLoading = false }
        // Try server first, fall back to local cache
        if let loaded: MedicalCardData = try? await coordinator.apiClient.get("/v1/medical-card") {
            await MainActor.run { card = loaded }
            cacheMedicalCard(loaded)
        } else if let cached = loadCachedMedicalCard() {
            await MainActor.run { card = cached }
        }
    }

    private func saveCard() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let _: SuccessResponse = try await coordinator.apiClient.put(
                "/v1/medical-card",
                body: card
            )
        } catch {
            #if DEBUG
            print("[MedicalCard] save error (saving locally): \(error)")
            #endif
        }
        // Always cache locally so EmergencyTextCardView and offline access work
        cacheMedicalCard(card)
    }

    private func cacheMedicalCard(_ data: MedicalCardData) {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: "medical_card_cache")
        }
    }

    private func loadCachedMedicalCard() -> MedicalCardData? {
        guard let data = UserDefaults.standard.data(forKey: "medical_card_cache"),
              let card = try? JSONDecoder().decode(MedicalCardData.self, from: data) else {
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
                            .font(.system(size: 24))
                            .foregroundStyle(alert)
                        Text("紧急医疗信息")
                            .font(.system(size: 20, weight: .bold))
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

                    if !card.medications.isEmpty {
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
