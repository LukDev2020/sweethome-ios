#if DEBUG
import SwiftUI

// MARK: - Screenshot Gallery
//
// Static mock screens for App Store screenshots.
// Avoids real views that trigger CLLocationManager dialogs.
// Uses simctl screenshot externally to capture each phase.

struct ScreenshotGalleryView: View {
    @State private var phaseIndex = 0

    private let labels = [
        "Onboarding 1", "Onboarding 2", "Onboarding 3",
        "Login",
        "Guardian Home", "Guardian Feed", "Guardian Records", "Guardian Settings",
        "Protected Home", "Protected Feed", "Protected Coverage", "Protected Records", "Protected Settings"
    ]

    var body: some View {
        ZStack {
            screenView
        }
        .task {
            // Phase 0 is already showing (initial @State value).
            // Start from phase 1 to avoid redundant re-set of phase 0.
            print("[Screenshot] Showing phase 0: \(labels[0])")
            for i in 1..<labels.count {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                phaseIndex = i
                print("[Screenshot] Showing phase \(i): \(labels[i])")
            }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            phaseIndex = labels.count
            print("[Screenshot] Done — \(labels.count) phases shown")
        }
    }

    @ViewBuilder
    private var screenView: some View {
        switch phaseIndex {
        case 0: OnboardingScreenshot(page: 0)
        case 1: OnboardingScreenshot(page: 1)
        case 2: OnboardingScreenshot(page: 2)
        case 3: LoginView()
        case 4: MockGuardianHome()
        case 5: MockFamilyFeed(role: .guardian)
        case 6: MockRecords(role: .guardian)
        case 7: MockSettings(role: .guardian)
        case 8: MockProtectedHome()
        case 9: MockFamilyFeed(role: .protected)
        case 10: MockCoverage()
        case 11: MockRecords(role: .protected)
        case 12: MockSettings(role: .protected)
        default:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("All \(labels.count) screens captured")
                    .font(.headline)
            }
        }
    }
}

// MARK: - Colors

private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
private let guardianPurple = Color(red: 107/255, green: 92/255, blue: 165/255)
private let protectedGreen = Color(red: 63/255, green: 143/255, blue: 110/255)

// MARK: - Mock Guardian Home

private struct MockGuardianHome: View {
    var body: some View {
        TabView(selection: .constant(0)) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        // Status card
                        VStack(spacing: 12) {
                            HStack {
                                Circle().fill(.green).frame(width: 12, height: 12)
                                Text("陈妈妈").font(.headline)
                                Spacer()
                                Text("在线").font(.caption).foregroundStyle(.green)
                            }
                            HStack {
                                Label("最后位置更新", systemImage: "location.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("2 分钟前").font(.caption).foregroundStyle(.secondary)
                            }
                            // Mock map placeholder
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray5))
                                .frame(height: 200)
                                .overlay {
                                    VStack {
                                        Image(systemName: "map.fill")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.secondary)
                                        Text("位置地图").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
                        .shadow(color: .black.opacity(0.05), radius: 8)

                        // Quick actions
                        HStack(spacing: 12) {
                            actionCard(icon: "phone.fill", label: "呼叫", color: .blue)
                            actionCard(icon: "message.fill", label: "消息", color: .green)
                            actionCard(icon: "bell.fill", label: "签到提醒", color: .orange)
                        }

                        // Recent activity
                        VStack(alignment: .leading, spacing: 12) {
                            Text("今日动态").font(.headline)
                            activityRow(icon: "checkmark.circle.fill", text: "陈妈妈 已报平安", time: "09:15", color: .green)
                            activityRow(icon: "location.fill", text: "到达 家", time: "08:30", color: .blue)
                            activityRow(icon: "battery.100", text: "电量 85%", time: "08:00", color: .green)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
                        .shadow(color: .black.opacity(0.05), radius: 8)
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("守护中心")
            }
            .tabItem { Label("首页", systemImage: "eye.fill") }
            .tag(0)
            Text("").tabItem { Label("家庭圈", systemImage: "bubble.left.and.bubble.right") }.tag(1)
            Text("").tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }.tag(2)
            Text("").tabItem { Label("设置", systemImage: "gearshape") }.tag(3)
        }
        .tint(guardianPurple)
    }

    private func actionCard(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.05), radius: 4)
    }

    private func activityRow(icon: String, text: String, time: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.subheadline)
            Spacer()
            Text(time).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Mock Protected Home

private struct MockProtectedHome: View {
    var body: some View {
        TabView(selection: .constant(0)) {
            NavigationStack {
                VStack(spacing: 0) {
                    Spacer()
                    // SOS Button
                    VStack(spacing: 24) {
                        Text("一切正常").font(.title2.weight(.medium)).foregroundStyle(.secondary)
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 220, height: 220)
                            Circle()
                                .fill(Color.red.opacity(0.3))
                                .frame(width: 180, height: 180)
                            Circle()
                                .fill(Color.red)
                                .frame(width: 140, height: 140)
                                .shadow(color: .red.opacity(0.4), radius: 20)
                            VStack(spacing: 4) {
                                Image(systemName: "sos")
                                    .font(.system(size: 36, weight: .bold))
                                Text("紧急求助")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                        }
                        Text("长按 3 秒发送紧急求助")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    // Check-in button
                    Button(action: {}) {
                        HStack {
                            Image(systemName: "hand.wave.fill")
                            Text("报平安")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(protectedGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    // Guardian status
                    HStack(spacing: 16) {
                        guardianBadge(name: "陈爸爸", online: true)
                        guardianBadge(name: "陈哥哥", online: true)
                        guardianBadge(name: "李阿姨", online: false)
                    }
                    .padding(.bottom, 8)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("首页")
            }
            .tabItem { Label("首页", systemImage: "shield.fill") }
            .tag(0)
            Text("").tabItem { Label("家庭圈", systemImage: "heart.text.square") }.tag(1)
            Text("").tabItem { Label("覆盖", systemImage: "globe.americas") }.tag(2)
            Text("").tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }.tag(3)
            Text("").tabItem { Label("设置", systemImage: "gearshape") }.tag(4)
        }
        .tint(protectedGreen)
    }

    private func guardianBadge(name: String, online: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(Color(.systemGray5)).frame(width: 44, height: 44)
                    .overlay { Text(String(name.prefix(1))).font(.headline) }
                Circle().fill(online ? .green : .gray).frame(width: 12, height: 12)
                    .overlay { Circle().stroke(.white, lineWidth: 2) }
            }
            Text(name).font(.caption2)
        }
    }
}

// MARK: - Mock Family Feed

private struct MockFamilyFeed: View {
    enum Role { case guardian, protected }
    let role: Role
    private var tint: Color { role == .guardian ? guardianPurple : protectedGreen }

    var body: some View {
        TabView(selection: .constant(1)) {
            if role == .guardian {
                Text("").tabItem { Label("首页", systemImage: "eye.fill") }.tag(0)
            } else {
                Text("").tabItem { Label("首页", systemImage: "shield.fill") }.tag(0)
            }
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        feedPost(name: "陈妈妈", time: "今天 09:30", text: "今天天气不错，去公园走了走 🌳", hasPhoto: true)
                        feedPost(name: "陈爸爸", time: "昨天 18:45", text: "晚饭做好了，大家快来吃！", hasPhoto: false)
                        feedPost(name: "陈哥哥", time: "昨天 12:00", text: "周末回家看你们", hasPhoto: false)
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("家庭圈")
            }
            .tabItem { Label("家庭圈", systemImage: role == .guardian ? "bubble.left.and.bubble.right" : "heart.text.square") }
            .tag(1)
            Text("").tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }.tag(role == .guardian ? 2 : 3)
            Text("").tabItem { Label("设置", systemImage: "gearshape") }.tag(role == .guardian ? 3 : 4)
            if role == .protected {
                Text("").tabItem { Label("覆盖", systemImage: "globe.americas") }.tag(2)
            }
        }
        .tint(tint)
    }

    private func feedPost(name: String, time: String, text: String, hasPhoto: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(Color(.systemGray4)).frame(width: 36, height: 36)
                    .overlay { Text(String(name.prefix(1))).font(.subheadline.weight(.medium)) }
                VStack(alignment: .leading) {
                    Text(name).font(.subheadline.weight(.medium))
                    Text(time).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(text).font(.subheadline)
            if hasPhoto {
                RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray5)).frame(height: 180)
                    .overlay { Image(systemName: "photo.fill").font(.title).foregroundStyle(.secondary) }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.05), radius: 6)
    }
}

// MARK: - Mock Records

private struct MockRecords: View {
    enum Role { case guardian, protected }
    let role: Role
    private var tint: Color { role == .guardian ? guardianPurple : protectedGreen }
    private var tabIndex: Int { role == .guardian ? 2 : 3 }

    var body: some View {
        TabView(selection: .constant(tabIndex)) {
            if role == .guardian {
                Text("").tabItem { Label("首页", systemImage: "eye.fill") }.tag(0)
                Text("").tabItem { Label("家庭圈", systemImage: "bubble.left.and.bubble.right") }.tag(1)
            } else {
                Text("").tabItem { Label("首页", systemImage: "shield.fill") }.tag(0)
                Text("").tabItem { Label("家庭圈", systemImage: "heart.text.square") }.tag(1)
                Text("").tabItem { Label("覆盖", systemImage: "globe.americas") }.tag(2)
            }
            NavigationStack {
                List {
                    Section("今天") {
                        recordRow(icon: "checkmark.circle.fill", text: "报平安", detail: "09:15", color: .green)
                        recordRow(icon: "location.fill", text: "到达安全区: 家", detail: "08:30", color: .blue)
                    }
                    Section("昨天") {
                        recordRow(icon: "checkmark.circle.fill", text: "报平安", detail: "20:00", color: .green)
                        recordRow(icon: "exclamationmark.triangle.fill", text: "电量低于 15%", detail: "18:45", color: .orange)
                        recordRow(icon: "location.fill", text: "离开安全区: 家", detail: "14:00", color: .blue)
                        recordRow(icon: "checkmark.circle.fill", text: "报平安", detail: "09:00", color: .green)
                    }
                    Section("10月19日") {
                        recordRow(icon: "sos", text: "紧急求助 (已解除)", detail: "16:30", color: .red)
                        recordRow(icon: "checkmark.circle.fill", text: "报平安", detail: "09:20", color: .green)
                    }
                }
                .navigationTitle("记录")
            }
            .tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }
            .tag(tabIndex)
            Text("").tabItem { Label("设置", systemImage: "gearshape") }.tag(role == .guardian ? 3 : 4)
        }
        .tint(tint)
    }

    private func recordRow(icon: String, text: String, detail: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color).frame(width: 28)
            Text(text)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Mock Settings

private struct MockSettings: View {
    enum Role { case guardian, protected }
    let role: Role
    private var tint: Color { role == .guardian ? guardianPurple : protectedGreen }
    private var tabIndex: Int { role == .guardian ? 3 : 4 }

    var body: some View {
        TabView(selection: .constant(tabIndex)) {
            if role == .guardian {
                Text("").tabItem { Label("首页", systemImage: "eye.fill") }.tag(0)
                Text("").tabItem { Label("家庭圈", systemImage: "bubble.left.and.bubble.right") }.tag(1)
                Text("").tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }.tag(2)
            } else {
                Text("").tabItem { Label("首页", systemImage: "shield.fill") }.tag(0)
                Text("").tabItem { Label("家庭圈", systemImage: "heart.text.square") }.tag(1)
                Text("").tabItem { Label("覆盖", systemImage: "globe.americas") }.tag(2)
                Text("").tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }.tag(3)
            }
            NavigationStack {
                List {
                    Section {
                        HStack(spacing: 14) {
                            Circle().fill(tint).frame(width: 56, height: 56)
                                .overlay { Text("陈").font(.title2).foregroundStyle(.white) }
                            VStack(alignment: .leading) {
                                Text(role == .guardian ? "陈爸爸" : "陈妈妈").font(.headline)
                                Text(role == .guardian ? "守护者" : "被守护者").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    Section("安全") {
                        Label("医疗卡", systemImage: "cross.case.fill")
                        Label("紧急联系人", systemImage: "person.2.fill")
                        Label("安全区", systemImage: "mappin.and.ellipse")
                    }
                    Section("通知") {
                        Label("推送设置", systemImage: "bell.fill")
                        Label("签到提醒", systemImage: "alarm.fill")
                    }
                    Section("订阅") {
                        HStack {
                            Label("当前方案", systemImage: "crown.fill")
                            Spacer()
                            Text("家庭版").foregroundStyle(.secondary)
                        }
                    }
                    Section("账号") {
                        Label("隐私政策", systemImage: "hand.raised.fill")
                        Label("服务条款", systemImage: "doc.text.fill")
                        Label("关于守灯", systemImage: "info.circle.fill")
                    }
                }
                .navigationTitle("设置")
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(tabIndex)
        }
        .tint(tint)
    }
}

// MARK: - Mock Coverage

private struct MockCoverage: View {
    var body: some View {
        TabView(selection: .constant(2)) {
            Text("").tabItem { Label("首页", systemImage: "shield.fill") }.tag(0)
            Text("").tabItem { Label("家庭圈", systemImage: "heart.text.square") }.tag(1)
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("换个国家，保护跟着换")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)

                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("China mainland（已自动识别）").font(.subheadline.weight(.medium))
                                row("当地紧急号码", "112 已预置")
                                row("响应中心语言", "中 / 英 / 俄")
                                row("中国使馆直线", "已收录")
                                row("本地救援伙伴", "2 家已对接")
                            }
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("离线包 · 没有网络时仍可用").font(.subheadline.weight(.medium))
                                row("紧急号码与协议", "已下载")
                                row("短信求助模板", "已下载")
                                row("离线地图", "下载 · 42MB")
                            }
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("弱网降级").font(.subheadline.weight(.medium))
                                HStack {
                                    Text("无数据网络自动切换").font(.subheadline)
                                    Spacer()
                                    Toggle("", isOn: .constant(true)).labelsHidden()
                                }
                                HStack {
                                    Text("低电量时降频").font(.subheadline)
                                    Spacer()
                                    Toggle("", isOn: .constant(true)).labelsHidden()
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("所在地覆盖")
            }
            .tabItem { Label("覆盖", systemImage: "globe.americas") }
            .tag(2)
            Text("").tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }.tag(3)
            Text("").tabItem { Label("设置", systemImage: "gearshape") }.tag(4)
        }
        .tint(protectedGreen)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(.blue)
        }
    }
}

// MARK: - Onboarding Screenshot

struct OnboardingScreenshot: View {
    let page: Int
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        ZStack {
            inkDeep.ignoresSafeArea(.all, edges: .all)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(0..<screens.count, id: \.self) { i in
                        Circle()
                            .fill(i <= page ? lamp : lamp.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 60)
                Spacer().frame(maxHeight: 60)
                Image(systemName: screens[page].icon)
                    .font(.scaled(size: 44, weight: .light))
                    .foregroundStyle(lamp)
                    .frame(height: 60)
                Text(screens[page].title)
                    .font(.scaled(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                Text(screens[page].body)
                    .font(.scaled(size: 16))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
                Spacer()
                Text(screens[page].buttonTitle)
                    .font(.scaled(size: 15, weight: .medium))
                    .foregroundStyle(inkDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(lamp)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, 28)
        }
    }

    private var screens: [DisclaimerCopy.Onboarding.Screen] {
        DisclaimerCopy.Onboarding.screens(for: lang.current)
    }
}
#endif
