import SwiftUI

// MARK: - Medical Card View
//
// Emergency medical profile: blood type, allergies, meds, insurance.
// Designed for lock-screen visibility — first responders need this
// without unlocking the phone.

struct MedicalCardView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
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
            return String(format: langManager.localized("medical.titleForUser"), name)
        }
        return langManager.localized("medical.title")
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
                    Button(langManager.localized("medical.close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveCard() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(langManager.localized("medical.save")).bold()
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
                            Text(langManager.localized("medical.saved"))
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
                        Text(langManager.localized("medical.preview"))
                            .font(.scaled(size: 14, weight: .medium))
                    }
                    .foregroundStyle(safe)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(safe.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Blood Type
                section(title: langManager.localized("medical.bloodType")) {
                    Picker(langManager.localized("medical.bloodType"), selection: Binding(
                        get: { card.bloodType ?? "" },
                        set: { card.bloodType = $0.isEmpty ? nil : $0 }
                    )) {
                        Text(langManager.localized("medical.notSet")).tag("")
                        ForEach(bloodTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Allergies
                section(title: langManager.localized("medical.allergies")) {
                    tagList(items: card.allergies) { card.allergies.remove(at: $0) }
                    addField(text: $newAllergy, placeholder: langManager.localized("medical.addAllergy")) {
                        card.allergies.append(newAllergy)
                        newAllergy = ""
                    }
                }

                // Medications (structured)
                medicationItemsSection

                // Conditions
                section(title: langManager.localized("medical.conditions")) {
                    tagList(items: card.conditions) { card.conditions.remove(at: $0) }
                    addField(text: $newCondition, placeholder: langManager.localized("medical.addCondition")) {
                        card.conditions.append(newCondition)
                        newCondition = ""
                    }
                }

                // Insurance
                section(title: langManager.localized("medical.insurance")) {
                    TextField(langManager.localized("medical.insuranceProvider"), text: Binding(
                        get: { card.insuranceProvider ?? "" },
                        set: { card.insuranceProvider = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    TextField(langManager.localized("medical.policyNumber"), text: Binding(
                        get: { card.insurancePolicyNumber ?? "" },
                        set: { card.insurancePolicyNumber = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                // Emergency Note
                section(title: langManager.localized("medical.emergencyNote")) {
                    TextField(langManager.localized("medical.otherInfo"), text: Binding(
                        get: { card.emergencyNote ?? "" },
                        set: { card.emergencyNote = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                // Organ Donor
                section(title: langManager.localized("medical.other")) {
                    Toggle(langManager.localized("medical.organDonor"), isOn: $card.organDonor)
                        .tint(safe)
                }

                Text(langManager.localized("medical.storageNote"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.top, 8)

                Text(LanguageManager.shared.localized("disclaimer.reference.only"))
                    .font(.scaled(size: 11))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Medication Items Section

    private var medicationItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(langManager.localized("medical.medicationMgmt"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(langManager.localized("medical.emergencyMedNote"))
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
                    Text(langManager.localized("medical.addMedication"))
                        .font(.scaled(size: 13, weight: .medium))
                }
                .foregroundStyle(safe)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(safe.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel(langManager.localized("medical.add"))

            // Legacy medications migration hint
            if !card.medications.isEmpty && card.medicationItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(langManager.localized("medical.legacyMeds"))
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(card.medications, id: \.self) { med in
                        Text("• \(med)")
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Button(langManager.localized("medical.convertFormat")) {
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

                TextField(langManager.localized("medical.medName"), text: $card.medicationItems[index].name)
                    .font(.scaled(size: 14, weight: .medium))

                Spacer()

                // Emergency toggle
                Button {
                    card.medicationItems[index].isEmergency.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: item.isEmergency ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                            .font(.scaled(size: 10))
                        Text(langManager.localized("medical.emergency"))
                            .font(.scaled(size: 10, weight: .medium))
                    }
                    .foregroundStyle(item.isEmergency ? .white : .orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(item.isEmergency ? Color.orange : Color.orange.opacity(0.1)))
                }
                .accessibilityLabel(langManager.localized("medical.markEmergency"))

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
                    TextField(langManager.localized("medical.storageLocation"), text: $card.medicationItems[index].storageLocation)
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
                    TextField(langManager.localized("medical.dosage"), text: $card.medicationItems[index].dosage)
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
                    .accessibilityLabel(langManager.localized("medical.delete"))
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

        // Try server in background with timeout, update if successful
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if isLoading {
                await MainActor.run { isLoading = false }
            }
        }
        defer { timeoutTask.cancel() }

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
                        saveResult = .failure(langManager.localized("medical.syncFailed"))
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

    private static var medicalCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("medical_card_cache.enc")
    }

    private func cacheMedicalCard(_ data: MedicalCardData) {
        guard let encoded = try? Self.cacheEncoder.encode(data) else { return }
        let url = Self.medicalCacheURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoded.write(to: url, options: [.completeFileProtection])
        // Exclude from backups to prevent PII leakage
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)
        // Remove legacy UserDefaults cache
        UserDefaults.standard.removeObject(forKey: "medical_card_cache")
    }

    private func loadCachedMedicalCard() -> MedicalCardData? {
        // Migrate from legacy UserDefaults if present
        if let legacyData = UserDefaults.standard.data(forKey: "medical_card_cache"),
           let card = try? Self.cacheDecoder.decode(MedicalCardData.self, from: legacyData) {
            cacheMedicalCard(card) // migrates to encrypted file
            return card
        }
        guard let data = try? Data(contentsOf: Self.medicalCacheURL),
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
                        Text(LanguageManager.shared.localized("medical.emergencyInfo"))
                            .font(.scaled(size: 20, weight: .bold))
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    if !userName.isEmpty {
                        previewRow(LanguageManager.shared.localized("medical.preview.name"), value: userName)
                    }

                    if let blood = card.bloodType {
                        previewRow(LanguageManager.shared.localized("medical.preview.bloodType"), value: blood)
                    }

                    if !card.allergies.isEmpty {
                        previewRow(LanguageManager.shared.localized("medical.preview.allergies"), value: card.allergies.joined(separator: "、"))
                    }

                    if !card.medicationItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LanguageManager.shared.localized("medical.preview.medications"))
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
                                        Text(LanguageManager.shared.localized("medical.emergency"))
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
                        previewRow(LanguageManager.shared.localized("medical.preview.medications"), value: card.medications.joined(separator: "、"))
                    }

                    if !card.conditions.isEmpty {
                        previewRow(LanguageManager.shared.localized("medical.preview.conditions"), value: card.conditions.joined(separator: "、"))
                    }

                    if let provider = card.insuranceProvider {
                        previewRow(LanguageManager.shared.localized("medical.preview.insurance"), value: provider + (card.insurancePolicyNumber.map { " #\($0)" } ?? ""))
                    }

                    if let note = card.emergencyNote, !note.isEmpty {
                        previewRow(LanguageManager.shared.localized("medical.preview.note"), value: note)
                    }

                    if card.organDonor {
                        previewRow(LanguageManager.shared.localized("medical.preview.organDonor"), value: LanguageManager.shared.localized("medical.preview.agreed"))
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle(LanguageManager.shared.localized("medical.preview.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LanguageManager.shared.localized("medical.close")) { dismiss() }
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
