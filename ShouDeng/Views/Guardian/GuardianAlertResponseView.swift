import SwiftUI

// MARK: - Screen B2: Alert Response
//
// Design from shoudeng-full-design.html:
//   - Header: "小雨正在求助" with location & time
//   - Map placeholder with pin
//   - Two buttons: "立即拨号" + "我已接手"
//   - Escalation chain with 3 steps
//   - Scene info panel (battery, last interaction)

struct GuardianAlertResponseView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Header
                    VStack(spacing: 2) {
                        Text("小雨正在求助")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(alert)
                        Text("基辅市中心 · 4 分 12 秒前")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Map placeholder
                    mapPlaceholder

                    // Action buttons
                    HStack(spacing: 8) {
                        Button {
                            // Open phone dialer — in production would use protected person's phone
                            if let url = URL(string: "tel://112") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("立即拨号")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(alert)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            coordinator.cancelSOS()
                            dismiss()
                        } label: {
                            Text("我已接手")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(ink.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Escalation chain
                    escalationChain

                    // Scene info
                    sceneInfoPanel
                }
                .padding(.horizontal, 16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("警报中")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("警报中")
                        .font(.system(size: 11))
                        .foregroundStyle(alert)
                }
            }
        }
    }

    // MARK: - Map Placeholder

    private var mapPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(height: 180)

            VStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(alert)
                Text("基辅市中心 · 精度约 8 米")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Escalation Chain

    private var escalationChain: some View {
        VStack(spacing: 0) {
            HStack {
                Text("升级链")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(alert)
                Spacer()
            }
            .padding(12)
            .background(alert.opacity(0.09))

            stepRow(number: "1", title: "你已收到并查看", detail: "07:07 送达 · 07:08 已读", state: .done)
            stepRow(number: "2", title: "备用联系人已通知", detail: "姑姑、邻居 Olena · 等待确认", state: .live)
            stepRow(number: "3", title: "自动语音外呼", detail: "系统将拨打电话直到有人接听 · 点「我已接手」可停止", state: .waiting)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    enum StepState { case done, live, waiting }

    private func stepRow(number: String, title: String, detail: String, state: StepState) -> some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                Circle()
                    .fill(state == .done ? safe : state == .live ? alert : Color(.systemGray5))
                    .frame(width: 19, height: 19)
                Text(number)
                    .font(.system(size: 10.5))
                    .foregroundStyle(state == .waiting ? Color.secondary : Color.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(state == .waiting ? 0.5 : 1.0)
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.2))
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Scene Info

    private var sceneInfoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("现场信息")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            infoRow("手机电量", value: "12% 持续下降", isAlert: true)
            infoRow("最后一次交互", value: "2 分钟前", isAlert: false)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func infoRow(_ label: String, value: String, isAlert: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(isAlert ? alert : .secondary)
        }
        .padding(.vertical, 2)
    }
}
