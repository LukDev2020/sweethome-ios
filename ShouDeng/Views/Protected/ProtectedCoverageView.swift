import SwiftUI

// MARK: - Screen A5: Coverage & Offline Pack
//
// Design from shoudeng-full-design.html:
//   - Current country detection (Ukraine · Kyiv)
//   - Local resources panel (emergency number, embassy, rescue partners)
//   - Offline pack panel (emergency numbers, SMS templates, offline map)
//   - Weak network degradation toggles

struct ProtectedCoverageView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var smsDowngrade = true
    @State private var lowPowerSaving = true

    private var countryName: String {
        let code = coordinator.currentUser?.countryCode ?? "CN"
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private var cityName: String {
        coordinator.currentUser?.cityName ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 2) {
                    Text("所在地覆盖")
                        .font(.system(size: 20, weight: .bold))
                    Text("换个国家，保护跟着换")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Local resources
                localResourcesPanel

                // Offline pack
                offlinePackPanel

                // Weak network
                weakNetworkPanel

                Text("覆盖能力需要真实的本地对接与人力，是免费产品最难复制的部分。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("所在地覆盖")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Local Resources

    private var localResourcesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(countryName)\(cityName.isEmpty ? "" : " · \(cityName)")（已自动识别）")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            resourceRow("当地紧急号码", value: "112 已预置", isOk: true)
            resourceRow("响应中心语言", value: "中 / 英 / 俄", isOk: true)
            resourceRow("中国使馆直线", value: "已收录", isOk: true)
            resourceRow("本地救援伙伴", value: "2 家已对接", isOk: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Offline Pack

    private var offlinePackPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("离线包 · 没有网络时仍可用")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            resourceRow("紧急号码与使馆信息", value: "已下载", isOk: true)
            resourceRow("短信求助模板", value: "已下载", isOk: true)
            resourceRow("离线地图\(cityName.isEmpty ? "" : " · \(cityName)")", value: "未下载 · 42MB", isOk: false)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Weak Network

    private var weakNetworkPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("弱网降级")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            toggleRow("无数据网络时改走短信", isOn: $smsDowngrade)
            toggleRow("低电量时降低上报频率", isOn: $lowPowerSaving)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func resourceRow(_ label: String, value: String, isOk: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(isOk ? safe : alert)
        }
        .padding(.vertical, 2)
    }

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
}
