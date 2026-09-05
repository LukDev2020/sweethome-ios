import SwiftUI

// MARK: - Screen A1: Protected Person Home
//
// Design from shoudeng-full-design.html:
//   - Globe showing family locations (placeholder for now)
//   - "Long press to send SOS" button
//   - "I'm okay" check-in button
//   - Contact list sorted by "who's awake right now"
//   - Each contact shows: avatar, name, city, local time, duty status

struct ProtectedHomeView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var isSOSPressed = false
    @State private var sosProgress: Double = 0
    @State private var showSOSActive = false
    @State private var sosDisclosureTrigger = false

    // Design system colors from the HTML
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Globe placeholder
                    globeSection

                    // SOS Button
                    sosButton
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    // Check-in Button
                    checkInButton
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    // Guardian list
                    guardianList
                        .padding(.top, 20)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("守灯")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(toolbarLocation)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.42))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(toolbarBattery)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.42))
                }
            }
            .navigationDestination(for: String.self) { _ in
                ProtectedGuardianDetailView()
            }
            .sheet(isPresented: $showSOSActive) {
                SOSActiveView()
            }
            .featureDisclosure(.sos, trigger: $sosDisclosureTrigger)
            .task {
                await coordinator.fetchGuardians()
            }
        }
    }

    private var toolbarLocation: String {
        if let user = coordinator.currentUser {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = user.timeZone
            return "\(user.cityName) \(formatter.string(from: Date()))"
        }
        return "基辅 14:07"
    }

    private var toolbarBattery: String {
        let level = UIDevice.current.batteryLevel
        if level >= 0 {
            return "电量 \(Int(level * 100))%"
        }
        return "电量 --%"
    }

    // MARK: - Globe Section

    private var globeSection: some View {
        ZStack {
            // Dark card background
            RoundedRectangle(cornerRadius: 16)
                .fill(inkDeep)

            // Rotating globe with pins and arcs
            GlobeMapView(
                pins: GlobeMapView.protectedPersonPins,
                links: GlobeMapView.protectedPersonLinks,
                initialLongitude: -30
            )

            // Overlay: header + legend
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("3 层保护")
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .foregroundStyle(lamp)
                        Text("4 位家人在 3 个国家")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Spacer()

                HStack(spacing: 16) {
                    Spacer()
                    legendDot(color: lamp, label: "我")
                    legendDot(color: safe, label: "守护者")
                    legendDot(color: pro, label: "响应中心")
                    Spacer()
                }
                .padding(.bottom, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(height: 260)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    // MARK: - SOS Button

    private var sosButton: some View {
        Button(action: {}) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(alert)
                    .frame(height: 52)

                // Progress overlay for long-press
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 13)
                        .fill(.white.opacity(0.2))
                        .frame(width: geo.size.width * sosProgress)
                }
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13))

                Text(isSOSPressed ? "继续按住..." : "长按发送紧急求助")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 3.0)
                .onChanged { _ in
                    isSOSPressed = true
                    sosDisclosureTrigger = true
                    withAnimation(.linear(duration: 3.0)) {
                        sosProgress = 1.0
                    }
                }
                .onEnded { _ in
                    isSOSPressed = false
                    sosProgress = 0
                    coordinator.triggerSOS(method: .longPress)
                    showSOSActive = true
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    // Released before 3 seconds
                    if sosProgress < 1.0 {
                        withAnimation {
                            isSOSPressed = false
                            sosProgress = 0
                        }
                    }
                }
        )
    }

    // MARK: - Check-in Button

    private var checkInButton: some View {
        Button {
            coordinator.performCheckIn()
        } label: {
            HStack {
                Text("今天我很好，报个平安")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 44/255, green: 107/255, blue: 81/255))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(safe.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }
    }

    // MARK: - Guardian List

    private var guardianList: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !coordinator.myGuardians.isEmpty {
                let onDuty = coordinator.myGuardians.filter { $0.isOnDuty }
                let offDuty = coordinator.myGuardians.filter { !$0.isOnDuty }

                if !onDuty.isEmpty {
                    sectionHeader("正在值班")
                    ForEach(onDuty) { g in
                        NavigationLink(value: g.id) {
                            guardianCard(
                                initial: g.user.avatarInitial, name: g.user.displayName,
                                tag: "值班中", tagColor: safe,
                                detail: "\(g.user.cityName) · \(permissionSummary(g.permissions))",
                                time: localTime(g.user.timeZone), timeNote: timeOfDay(g.user.timeZone),
                                isOnDuty: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !offDuty.isEmpty {
                    sectionHeader("其他守护者")
                    ForEach(offDuty) { g in
                        NavigationLink(value: g.id) {
                            guardianCard(
                                initial: g.user.avatarInitial, name: g.user.displayName,
                                tag: nil, tagColor: nil,
                                detail: "\(g.user.cityName) · \(permissionSummary(g.permissions))",
                                time: localTime(g.user.timeZone), timeNote: timeOfDay(g.user.timeZone),
                                isOnDuty: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Demo fallback
                sectionHeader("正在值班")
                guardianCard(
                    initial: "妈", name: "妈妈", tag: "值班中", tagColor: safe,
                    detail: "多伦多 · 位置、电量、健康",
                    time: "07:07", timeNote: "清晨",
                    isOnDuty: true
                )

                sectionHeader("醒着")
                guardianCard(
                    initial: "姑", name: "姑姑", tag: nil, tagColor: nil,
                    detail: "悉尼 · 仅紧急时可见位置",
                    time: "22:07", timeNote: "夜晚",
                    isOnDuty: false
                )

                sectionHeader("在休息")
                guardianCard(
                    initial: "爸", name: "爸爸", tag: nil, tagColor: nil,
                    detail: "多伦多 · 位置、电量",
                    time: "07:07", timeNote: "清晨",
                    isOnDuty: false, isDimmed: true
                )

                guardianCard(
                    initial: "中", name: "响应中心", tag: "24h", tagColor: pro,
                    detail: "中英俄语 · 家人无响应时接手",
                    time: "在岗", timeNote: "常驻",
                    isOnDuty: false, isPro: true
                )
            }

            // Footer
            VStack(spacing: 0) {
                Divider()
                Text("列表按「谁醒着」而非亲疏排序——慌乱时最需要知道的是谁最快能看到。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 11)
            }
            .padding(.horizontal, 16)
            .padding(.top, 11)
            .padding(.bottom, 16)
        }
    }

    private func permissionSummary(_ p: GuardianPermissions) -> String {
        var parts: [String] = []
        if p.canSeeLocation { parts.append("位置") }
        if p.canSeeBattery { parts.append("电量") }
        if p.canSeeHealth { parts.append("健康") }
        return parts.isEmpty ? "仅紧急时可见" : parts.joined(separator: "、")
    }

    private func localTime(_ tz: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = tz
        return formatter.string(from: Date())
    }

    private func timeOfDay(_ tz: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        formatter.timeZone = tz
        let hour = Int(formatter.string(from: Date())) ?? 12
        if hour >= 6 && hour < 9 { return "清晨" }
        if hour >= 9 && hour < 12 { return "上午" }
        if hour >= 12 && hour < 14 { return "中午" }
        if hour >= 14 && hour < 18 { return "下午" }
        if hour >= 18 && hour < 22 { return "晚上" }
        return "深夜"
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5))
            .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
            .padding(.horizontal, 18)
            .padding(.top, 4)
    }

    private func guardianCard(
        initial: String, name: String,
        tag: String?, tagColor: Color?,
        detail: String, time: String, timeNote: String,
        isOnDuty: Bool, isDimmed: Bool = false, isPro: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(isPro ? pro.opacity(0.15) : Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.08))
                    .frame(width: 34, height: 34)
                Text(initial)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isPro ? pro : ink)

                if isOnDuty {
                    Circle()
                        .stroke(safe, lineWidth: 2)
                        .frame(width: 40, height: 40)
                }
            }
            .opacity(isDimmed ? 0.5 : 1.0)

            // Body
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(name)
                        .font(.system(size: 13.5, weight: .medium))
                    if let tag, let tagColor {
                        Text(tag)
                            .font(.system(size: 9.5))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(tagColor.opacity(0.14))
                            .foregroundStyle(tagColor)
                            .clipShape(Capsule())
                    }
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.58))
                    .lineLimit(1)
            }

            Spacer()

            // Time
            VStack(alignment: .trailing, spacing: 1) {
                Text(time)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                Text(timeNote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.13), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - SOS Active View (Screen A2)

struct SOSActiveView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss

    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Persistent SOS banner — PDF: "SOS 进行中界面须常驻一行"
                Text(DisclaimerCopy.SOS.persistentBanner)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(alert)

                ScrollView {
                    VStack(spacing: 16) {
                        // SOS circle
                        ZStack {
                            Circle()
                                .fill(alert)
                                .frame(width: 142, height: 142)
                            VStack(spacing: 2) {
                                Text("已发出")
                                    .font(.system(size: 26, weight: .black, design: .serif))
                                    .foregroundStyle(.white)
                                Text("14:07 · 基辅市中心")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .padding(.top, 16)

                        // Escalation steps
                        escalationSteps

                        // Auto-enabled during SOS
                        autoEnabledPanel

                        // Cancel button
                        Button {
                            coordinator.cancelSOS()
                            dismiss()
                        } label: {
                            Text("取消求助（我没事）")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("求助已发出")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var escalationSteps: some View {
        VStack(spacing: 0) {
            HStack {
                Text("已进行 4 分 12 秒")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(alert)
                Spacer()
            }
            .padding(12)
            .background(alert.opacity(0.09))

            stepRow(number: "1", title: "家人已收到", detail: "妈妈 14:08 已读，正在拨号", state: .done)
            stepRow(number: "2", title: "备用联系人已通知", detail: "姑姑、邻居 Olena 已收到", state: .live)
            stepRow(number: "3", title: "自动语音外呼", detail: "系统将依次拨打家人电话，直到有人接听确认", state: .waiting)
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

    private var autoEnabledPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("求助期间自动开启，结束后恢复")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            statusRow("高频位置上报", value: "进行中", isActive: true)
            statusRow("环境录音留证", value: "进行中", isActive: true)
            statusRow("低电量省电模式", value: "已启用", isActive: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func statusRow(_ label: String, value: String, isActive: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(isActive ? safe : .secondary)
        }
        .padding(.vertical, 2)
    }
}
