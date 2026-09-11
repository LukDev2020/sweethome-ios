import SwiftUI

// MARK: - Privacy Policy View
//
// In-app privacy policy required by App Store.
// Shows both privacy policy and terms of service.

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        sectionTitle("隐私政策")
                        lastUpdated("2026 年 9 月 1 日")

                        sectionHeader("一、我们收集哪些信息")
                        bulletPoint("位置信息", detail: "用于安全区检测、紧急求助定位和行动轨迹记录。仅在您授权后收集，且仅与您指定的守护者共享。")
                        bulletPoint("运动传感器数据", detail: "用于跌倒检测。数据仅在设备本地处理，不上传服务器。")
                        bulletPoint("手机号码", detail: "用于账号注册和紧急短信通知。")
                        bulletPoint("设备信息", detail: "电量、在线状态等，用于守护者了解被守护设备是否正常工作。")

                        sectionHeader("二、我们如何使用信息")
                        bodyText("所有收集的信息仅用于以下目的：")
                        bulletPoint("紧急求助", detail: "在 SOS 触发时向守护者发送您的位置。")
                        bulletPoint("安全监测", detail: "检测异常情况（如跌倒、失联）并及时通知守护者。")
                        bulletPoint("报平安", detail: "让守护者了解您的安全状态。")
                    }

                    Group {
                        sectionHeader("三、数据保留")
                        bodyText("免费用户：位置数据保留 7 天，签到记录保留 30 天。\n付费用户：位置数据保留 90 天，签到记录永久保留。\nSOS 事件记录和知情同意审计日志永久保留。")

                        sectionHeader("四、数据共享")
                        bodyText("您的位置和安全信息仅与您明确授权的守护者共享。我们不会向任何第三方出售您的个人信息。紧急分享链接仅在您或系统升级链自动生成时创建，且有效期不超过 48 小时。")

                        sectionHeader("五、数据安全")
                        bodyText("所有数据传输使用 TLS 加密。敏感凭证存储在 iOS 钥匙串中。服务器端数据静态加密。每日生成 Merkle 树完整性证明，确保数据未被篡改。")

                        sectionHeader("六、您的权利")
                        bulletPoint("访问权", detail: "您可以随时在设置中导出您的全部数据。")
                        bulletPoint("删除权", detail: "您可以在设置中注销账号，永久删除所有数据。")
                        bulletPoint("撤回同意", detail: "您可以随时在系统设置中关闭位置或运动传感器权限。")
                    }

                    Group {
                        sectionHeader("七、联系我们")
                        bodyText("如您对隐私政策有任何疑问，请联系：\nprivacy@shoudeng.app")
                    }

                    Divider().padding(.vertical, 8)

                    Group {
                        sectionTitle("服务条款")
                        lastUpdated("2026 年 9 月 1 日")

                        sectionHeader("一、服务描述")
                        bodyText("守灯是一款个人安全守护应用，为被守护者和守护者提供紧急求助、位置共享、跌倒检测等安全功能。本应用不替代 110/119/120 等专业紧急服务。")

                        sectionHeader("二、免责声明")
                        bodyText("守灯作为辅助安全工具，不保证在所有情况下都能成功发送警报。网络故障、设备损坏、电量耗尽等因素可能影响服务可用性。在紧急情况下，请务必同时拨打专业急救电话。")

                        sectionHeader("三、订阅与付费")
                        bodyText("付费订阅通过 Apple App Store 处理。订阅自动续费，可在 Apple ID 设置中随时取消。取消后当前付费周期内仍可使用付费功能。")

                        sectionHeader("四、账号与数据")
                        bodyText("您有责任保管好账号安全。注销账号将永久删除所有相关数据，此操作不可撤销。")
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("隐私与条款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - Components

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .padding(.bottom, 4)
    }

    private func lastUpdated(_ date: String) -> some View {
        Text("最后更新：\(date)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .padding(.top, 4)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.primary.opacity(0.85))
            .lineSpacing(4)
    }

    private func bulletPoint(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }
}

// MARK: - About View (accessible from settings)

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivacy = false

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("守灯")
                    .font(.system(size: 24, weight: .bold, design: .serif))

                Text("让每一盏灯都不孤单")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text("版本 \(version) (\(build))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showPrivacy = true
                    } label: {
                        Text("隐私政策与服务条款")
                            .font(.system(size: 13))
                    }

                    Text("© 2026 守灯安全")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyPolicyView()
            }
        }
    }
}
