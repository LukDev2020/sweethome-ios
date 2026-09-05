import SwiftUI

// MARK: - Screen A4: My Records / Timeline
//
// Design from shoudeng-full-design.html:
//   - Timeline list with date groups and events
//   - Export panel (PDF with timestamps, GPX track)
//   - Upsell for full 90-day history

struct ProtectedRecordsView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 2) {
                    Text("我的记录")
                        .font(.system(size: 20, weight: .bold))
                    Text("90 天可查 · 专业版永久保存")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Timeline
                timelineSection

                // Export
                exportPanel

                // Upsell
                upsellCard
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("我的记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if coordinator.timeline.isEmpty {
                // Demo fallback
                timelineRow(date: "今天", event: "14:07 触发 SOS，4 分 12 秒后由妈妈确认安全", isBlurred: false)
                timelineRow(date: "今天", event: "09:12 报平安", isBlurred: false)
                timelineRow(date: "昨天", event: "21:40 离开安全区「住所」", isBlurred: false)
                timelineRow(date: "昨天", event: "08:55 报平安", isBlurred: false)
                timelineRow(date: "3天前", event: "18:20 在未知区域停留超过两小时", isBlurred: true)
                timelineRow(date: "5天前", event: "07:30 报平安", isBlurred: true)
            } else {
                ForEach(coordinator.timeline.prefix(20)) { entry in
                    timelineRow(
                        date: formatDate(entry.timestamp),
                        event: "\(formatTime(entry.timestamp)) \(entry.description)",
                        isBlurred: false
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        return "\(days)天前"
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func timelineRow(date: String, event: String, isBlurred: Bool) -> some View {
        HStack(alignment: .top) {
            Text(date)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Text(event)
                .font(.system(size: 12.5))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .opacity(isBlurred ? 0.4 : 1.0)
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Export Panel

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("导出")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            exportRow("带时间戳的 PDF", value: "需升级")
            exportRow("位置轨迹 GPX", value: "需升级")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func exportRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Upsell

    private var upsellCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("免费版仅保留 24 小时。升级后可查看 90 天完整时间线并导出——向警方、保险或律师说明情况时用得上。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {} label: {
                Text("升级查看全部记录")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pro)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(pro.opacity(0.06))
        )
    }
}
