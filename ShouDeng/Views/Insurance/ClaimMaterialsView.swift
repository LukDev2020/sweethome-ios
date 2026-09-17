import SwiftUI
import CryptoKit

// MARK: - Claim Materials Organizer
//
// 3-step flow: Select scope → Preview records → Export
// Both Guardian and Protected portals can access this.
// Vela provides reference data only — no certifications.

struct ClaimMaterialsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    // Step tracking
    @State private var step = 0 // 0=scope, 1=preview, 2=result

    // Step 0: Scope
    @State private var incidentDate = Date()
    @State private var windowHours = 24
    @State private var userDescription = ""
    @State private var selectedType: InsuranceType?
    @State private var policyNumber = ""
    @State private var includeSOS = true
    @State private var includeCheckIns = true
    @State private var includeTimeline = true
    @State private var includeLocation = true
    @State private var includeMedicalCard = true

    // Step 1: Preview / generation
    @State private var isLoading = false
    @State private var exportResult: ClaimMaterialExport?
    @State private var errorMessage: String?

    // Step 2: Result
    @State private var showShareSheet = false
    @State private var pdfURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: scopeStep
                case 1: previewStep
                default: resultStep
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("整理理赔材料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == 0 {
                        Button("关闭") { dismiss() }
                    } else if step == 1 && !isLoading {
                        Button("上一步") { step = 0 }
                    }
                }
            }
        }
    }

    // MARK: - Step 0: Scope Selection

    private var scopeStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(safe.opacity(0.6))
                    Text("整理设备记录")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ink)
                    Text("选择时间范围和记录类型，\n导出事件前后的设备记录供您自行使用。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                // Insurance type (optional)
                insuranceTypePicker

                // Incident date
                dateSection

                // Window
                windowSection

                // Policy number (optional)
                policySection

                // What to include
                inclusionToggles

                // Description (optional)
                descriptionSection

                // Next
                Button {
                    step = 1
                    Task { await generateExport() }
                } label: {
                    Text("预览记录")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(safe)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                }

                // Disclaimer
                Text(ClaimDisclaimer.full)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Insurance Type Picker

    private var insuranceTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("险种参考 (可选)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("选择险种后将显示对应的材料参考清单")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 8) {
                ForEach(InsuranceType.allCases) { type in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedType = selectedType == type ? nil : type
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: type.icon)
                                .font(.system(size: 15))
                            Text(type.displayName)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(selectedType == type ? .white : ink.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedType == type ? safe : safe.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Date Section

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("事件日期")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            DatePicker(
                "",
                selection: $incidentDate,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Window Section

    private var windowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("导出范围")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Picker("", selection: $windowHours) {
                Text("前后 12 小时").tag(12)
                Text("前后 24 小时").tag(24)
                Text("前后 48 小时").tag(48)
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Policy Section

    private var policySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("保单号 (可选，仅记录在导出文件中)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("例如 PA-20260101-XXX", text: $policyNumber)
                .font(.system(size: 13))
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Inclusion Toggles

    private var inclusionToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择要包含的记录")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            toggleRow("SOS 求助记录", isOn: $includeSOS)
            toggleRow("签到 (报平安) 记录", isOn: $includeCheckIns)
            toggleRow("时间线事件", isOn: $includeTimeline)
            toggleRow("位置轨迹", isOn: $includeLocation)
            toggleRow("医疗卡快照", isOn: $includeMedicalCard)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注 (可选，仅记录在导出文件中)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("简要描述发生了什么", text: $userDescription, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 13))
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Step 1: Preview & Loading

    private var previewStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在整理记录...")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            Task { await generateExport() }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(safe)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else if let export = exportResult {
                    previewContent(export)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func previewContent(_ export: ClaimMaterialExport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Summary header
            VStack(spacing: 4) {
                Text("记录预览")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ink)
                Text("请确认以下内容，确认后可导出")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            // Basic info
            infoCard {
                previewRow("导出编号", value: export.exportId)
                previewRow("当事人", value: export.personName)
                previewRow("事件日期", value: formatDateTime(export.incidentDate))
                previewRow("时间范围", value: "\(formatDateTime(export.window.start)) ~ \(formatDateTime(export.window.end))")
            }

            // SOS Events
            if let sos = export.sosEvents, !sos.isEmpty {
                sectionCard(title: "SOS 求助记录", count: sos.count) {
                    ForEach(sos) { event in
                        HStack {
                            Text(formatISOTime(event.triggeredAt))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("SOS 触发")
                                .font(.system(size: 12))
                            if let method = event.triggerMethod {
                                Text("(\(method))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Check-ins
            if let checkIns = export.checkIns, !checkIns.isEmpty {
                sectionCard(title: "签到记录", count: checkIns.count) {
                    ForEach(checkIns) { ci in
                        HStack {
                            Text(formatISOTime(ci.timestamp))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("报平安")
                                .font(.system(size: 12))
                            if let note = ci.note, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Timeline
            if let timeline = export.timeline, !timeline.isEmpty {
                sectionCard(title: "时间线事件", count: timeline.count) {
                    ForEach(timeline) { entry in
                        HStack(alignment: .top) {
                            Text(formatISOTime(entry.timestamp))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                            Text(entry.description ?? entry.type ?? "事件")
                                .font(.system(size: 12))
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Medical snapshot
            if let med = export.medicalSnapshot {
                sectionCard(title: "医疗卡快照", count: nil) {
                    if let bt = med.bloodType, !bt.isEmpty {
                        previewRow("血型", value: bt)
                    }
                    if let allergies = med.allergies, !allergies.isEmpty {
                        previewRow("过敏", value: allergies.joined(separator: "、"))
                    }
                    if let conditions = med.conditions, !conditions.isEmpty {
                        previewRow("病史", value: conditions.joined(separator: "、"))
                    }
                    if let provider = med.insuranceProvider, !provider.isEmpty {
                        previewRow("保险公司", value: provider)
                    }
                    if let policy = med.policyNumber, !policy.isEmpty {
                        previewRow("保单号", value: policy)
                    }
                }
            }

            // Reference checklist (if insurance type selected)
            if let type = selectedType {
                referenceChecklist(type, export: export)
            }

            // Hash
            infoCard {
                previewRow("内容哈希 (SHA-256)", value: String(export.contentHash.prefix(24)) + "...")
                Text("此哈希值供您自行校验导出内容未被修改")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // Confirm export
            Button {
                pdfURL = ClaimPDFGenerator.generate(
                    export: export,
                    insuranceType: selectedType,
                    policyNumber: policyNumber.isEmpty ? nil : policyNumber,
                    userDescription: userDescription.isEmpty ? nil : userDescription
                )
                step = 2
            } label: {
                Text("确认并导出 PDF")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(safe)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
            }

            Text(ClaimDisclaimer.full)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Reference Checklist

    private func referenceChecklist(_ type: InsuranceType, export: ClaimMaterialExport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checklist")
                    .font(.system(size: 13))
                    .foregroundStyle(lamp)
                Text("材料参考清单 · \(type.displayName)")
                    .font(.system(size: 13, weight: .semibold))
            }

            // Insurer requires
            VStack(alignment: .leading, spacing: 4) {
                Text("保险公司通常要求 (需您自行获取)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                ForEach(type.insurerRequires, id: \.self) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "square")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(.system(size: 12))
                    }
                }
            }

            Divider()

            // Vela records
            VStack(alignment: .leading, spacing: 4) {
                Text("您的设备记录中包含")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                ForEach(type.velaCanProvide, id: \.self) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(safe)
                        Text(item)
                            .font(.system(size: 12))
                    }
                }
            }

            Text(ClaimDisclaimer.checklistNote)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(lamp.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(lamp.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Step 2: Result

    private var resultStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(safe)

            Text("记录已导出")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ink)

            if let export = exportResult {
                VStack(spacing: 8) {
                    resultRow("导出编号", value: export.exportId)
                    resultRow("当事人", value: export.personName)
                    resultRow("事件日期", value: formatDateTime(export.incidentDate))
                    resultRow("导出时间", value: formatDateTime(export.exportedAt))
                    resultRow("哈希值", value: String(export.contentHash.prefix(16)) + "...")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.systemGray6))
                )
            }

            // Share PDF
            if pdfURL != nil {
                Button {
                    showShareSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("分享 PDF 文件")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(safe)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }
            }

            VStack(spacing: 4) {
                Text(ClaimDisclaimer.pdfHeader)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ForEach(ClaimDisclaimer.limitations, id: \.self) { line in
                    Text("· \(line)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Button("完成") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(safe)
                .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - API Call

    private func generateExport() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let request = ClaimMaterialRequest(
                incidentDate: incidentDate,
                windowHours: windowHours,
                description: userDescription.isEmpty ? nil : userDescription,
                insuranceType: selectedType?.rawValue,
                policyNumber: policyNumber.isEmpty ? nil : policyNumber,
                includeSOS: includeSOS,
                includeCheckIns: includeCheckIns,
                includeTimeline: includeTimeline,
                includeLocation: includeLocation,
                includeMedicalCard: includeMedicalCard
            )
            let result: ClaimMaterialExport = try await coordinator.apiClient.post(
                "/v1/insurance/claim-materials",
                body: request
            )
            await MainActor.run { exportResult = result }
        } catch {
            #if DEBUG
            print("[ClaimMaterials] API error, using local fallback: \(error)")
            let mock = buildLocalExport()
            await MainActor.run { exportResult = mock }
            #else
            await MainActor.run { errorMessage = "无法获取记录，请检查网络后重试。" }
            #endif
        }
    }

    private func buildLocalExport() -> ClaimMaterialExport {
        let now = Date()
        let halfWindow = TimeInterval(windowHours * 3600)
        let windowStart = incidentDate.addingTimeInterval(-halfWindow)
        let windowEnd = incidentDate.addingTimeInterval(halfWindow)

        let sosItems: [SOSRecordItem]? = includeSOS ? coordinator.timeline
            .filter { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }
            .filter { $0.description.contains("SOS") || $0.description.contains("求助") }
            .map { SOSRecordItem(triggeredAt: $0.timestamp.ISO8601Format(), triggerMethod: "长按", resolution: nil, latitude: nil, longitude: nil) }
            : nil

        let timelineItems: [TimelineRecordItem]? = includeTimeline ? coordinator.timeline
            .filter { $0.timestamp >= windowStart && $0.timestamp <= windowEnd }
            .map { TimelineRecordItem(timestamp: $0.timestamp.ISO8601Format(), type: nil, description: $0.description) }
            : nil

        let name = coordinator.currentUser?.displayName ?? "用户"
        let exportId = "EXP-\(UUID().uuidString.prefix(8).uppercased())"

        let content = "\(exportId)\(name)\(incidentDate)"
        let hash = sha256Hex(content)

        return ClaimMaterialExport(
            exportId: exportId,
            personName: name,
            exportedAt: now,
            incidentDate: incidentDate,
            window: ExportTimeWindow(start: windowStart, end: windowEnd),
            sosEvents: (sosItems?.isEmpty ?? true) ? nil : sosItems,
            checkIns: includeCheckIns ? [] : nil,
            timeline: (timelineItems?.isEmpty ?? true) ? nil : timelineItems,
            medicalSnapshot: includeMedicalCard ? MedicalSnapshot(
                bloodType: "A+", allergies: ["青霉素"], conditions: nil,
                insuranceProvider: nil, policyNumber: policyNumber.isEmpty ? nil : policyNumber
            ) : nil,
            contentHash: hash,
            disclaimer: ClaimDisclaimer.full
        )
    }

    private func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Helpers

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(safe)
        }
        .padding(.vertical, 2)
    }

    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func sectionCard<Content: View>(title: String, count: Int?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)
                if let count {
                    Text("\(count) 条")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func previewRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
    }

    private func resultRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ink)
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private func formatISOTime(_ iso: String) -> String {
        if let range = iso.range(of: "T") {
            let time = iso[range.upperBound...]
            if time.count >= 5 {
                return String(time.prefix(5))
            }
        }
        return String(iso.suffix(8))
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
