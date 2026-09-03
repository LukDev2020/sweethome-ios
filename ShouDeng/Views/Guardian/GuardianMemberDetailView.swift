import SwiftUI

// MARK: - Screen B3: Member Detail
//
// Design from shoudeng-full-design.html:
//   - Header: name, city, local time, protection layers
//   - Map placeholder with location
//   - "Right now" status panel (status, battery, phone, last check-in)
//   - Activity timeline (today's events)
//   - Action buttons: message, call

struct GuardianMemberDetailView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 2) {
                    Text("小雨")
                        .font(.system(size: 20, weight: .bold))
                    Text("基辅 · 当地 14:07 · 3 层保护")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Map placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .frame(height: 160)
                    VStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(safe)
                        Text("住所附近 · 12 分钟前")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                // Status panel
                statusPanel

                // Timeline
                timelineSection

                // Action buttons
                HStack(spacing: 8) {
                    actionButton("发消息")
                    actionButton("拨号")
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("成员详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("你正在值班")
                    .font(.system(size: 11))
                    .foregroundStyle(safe)
            }
        }
    }

    // MARK: - Status Panel

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("此刻")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            statusRow("状态", value: "正常", isOk: true)
            statusRow("电量", value: "78%", isOk: false)
            statusRow("手机", value: "在线 · 5 分钟前使用过", isOk: true)
            statusRow("上次报平安", value: "12 分钟前", isOk: false)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func statusRow(_ label: String, value: String, isOk: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(isOk ? safe : .primary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineRow(time: "14:00", event: "报平安")
            timelineRow(time: "11:20", event: "进入安全区「学校」")
            timelineRow(time: "08:40", event: "离开安全区「住所」")
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func timelineRow(time: String, event: String) -> some View {
        HStack {
            Text(time)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Text(event)
                .font(.system(size: 12.5))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func actionButton(_ title: String) -> some View {
        Button {} label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ink.opacity(0.2), lineWidth: 1)
                )
        }
    }
}
