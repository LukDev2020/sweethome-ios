import SwiftUI

// MARK: - Insurance Report View
//
// Generate timestamped incident reports for insurance claims.
// Includes location trail, SOS events, check-ins during the incident window.

struct InsuranceReportView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    @State private var incidentDate = Date()
    @State private var description = ""
    @State private var isGenerating = false
    @State private var generatedReport: InsuranceClaimReport?

    var body: some View {
        NavigationStack {
            Group {
                if let report = generatedReport {
                    reportResult(report)
                } else {
                    reportForm
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("保险理赔报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: - Form

    private var reportForm: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(safe.opacity(0.6))
                    .padding(.top, 16)

                Text("生成事件报告")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ink)

                Text("系统将导出事件发生前后 24 小时内的\n位置轨迹、求助记录、签到数据。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("事件描述 (可选)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("简要描述发生了什么", text: $description, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                )

                Button {
                    Task { await generateReport() }
                } label: {
                    HStack(spacing: 8) {
                        if isGenerating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "doc.text.fill")
                        }
                        Text("生成报告")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(safe)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isGenerating)

                VStack(spacing: 4) {
                    Text("报告包含:")
                        .font(.system(size: 11, weight: .medium))
                    Text("位置轨迹 / SOS 记录 / 签到记录 / 医疗信息 / 数据完整性证明")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Result

    private func reportResult(_ report: InsuranceClaimReport) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(safe)

            Text("报告已生成")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ink)

            VStack(spacing: 8) {
                detailRow("报告编号", value: report.reportId)
                detailRow("当事人", value: report.personName)
                detailRow("事件日期", value: report.incidentDate.formatted(.dateTime.year().month().day().hour().minute()))
                detailRow("生成时间", value: report.generatedAt.formatted(.dateTime.year().month().day().hour().minute()))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemGray6))
            )

            Text("报告已存档。数据完整性可通过每日 SHA-256\nMerkle 根进行独立验证。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("完成") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(safe)
                .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func detailRow(_ label: String, value: String) -> some View {
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

    // MARK: - Action

    private func generateReport() async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            let report: InsuranceClaimReport = try await coordinator.apiClient.post(
                "/v1/insurance/claim-report",
                body: InsuranceClaimRequest(
                    incidentDate: incidentDate,
                    description: description.isEmpty ? nil : description,
                    protectedPersonId: nil
                )
            )
            await MainActor.run { generatedReport = report }
        } catch {
            #if DEBUG
            print("[Insurance] generate report error (using local fallback): \(error)")
            // Generate a local mock report so the UI is demonstrable
            let mockReport = InsuranceClaimReport(
                reportId: "RPT-\(UUID().uuidString.prefix(8).uppercased())",
                personName: coordinator.currentUser?.displayName ?? "测试用户",
                incidentDate: incidentDate,
                generatedAt: Date()
            )
            await MainActor.run { generatedReport = mockReport }
            #endif
        }
    }
}
