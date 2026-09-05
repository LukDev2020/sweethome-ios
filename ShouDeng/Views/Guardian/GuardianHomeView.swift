import SwiftUI

// MARK: - Screen B1: Guardian Home
//
// Design from shoudeng-full-design.html:
//   - Globe showing family locations (placeholder)
//   - World clocks row (Kyiv, Shanghai, Toronto, London)
//   - "Needs attention" section with warning cards
//   - "All normal" section with status cards
//   - "Add protected person" button

struct GuardianHomeView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    // Demo data
    private let clocks: [(city: String, time: String, note: String, isYou: Bool)] = [
        ("基辅", "14:07", "白天", false),
        ("上海", "20:07", "夜晚", false),
        ("多伦多", "07:07", "你在这", true),
        ("伦敦", "12:07", "白天", false),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    globeSection
                    worldClocks
                        .padding(.top, 4)

                    // Needs attention
                    needsAttentionSection

                    // All normal
                    allNormalSection

                    // Add button
                    Button {} label: {
                        Text("添加要守护的人")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                                    .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.28))
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // Footer note
                    VStack(spacing: 0) {
                        Divider()
                        Text("世界钟解决跨国家庭每天都在做的心算：现在打过去会不会吵醒他。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 11)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 11)
                    .padding(.bottom, 24)
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
                    Text("你正在值班")
                        .font(.system(size: 10.5))
                        .foregroundStyle(safe)
                }
            }
            .navigationDestination(for: String.self) { personId in
                if coordinator.activeSOSEvent?.protectedPersonId == personId {
                    GuardianAlertResponseView()
                } else {
                    GuardianMemberDetailView()
                }
            }
            .task {
                await coordinator.fetchProtectedPersons()
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
        return "多伦多 07:07"
    }

    // MARK: - Globe Section

    private var globeSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(inkDeep)

            GlobeMapView(
                pins: GlobeMapView.guardianPins,
                links: GlobeMapView.guardianLinks,
                initialLongitude: 60
            )

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("4 位家人")
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .foregroundStyle(lamp)
                        Text("分布在 3 个国家")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Spacer()

                HStack(spacing: 11) {
                    Spacer()
                    legendDot(color: lamp, label: "被守护")
                    legendDot(color: safe, label: "守护者")
                    legendDot(color: pro, label: "响应中心")
                    Spacer()
                }
                .padding(.bottom, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(height: 240)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - World Clocks

    private var worldClocks: some View {
        HStack(spacing: 6) {
            ForEach(Array(clocks.enumerated()), id: \.offset) { _, clock in
                VStack(spacing: 2) {
                    Text(clock.city)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.55))
                        .lineLimit(1)
                    Text(clock.time)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(clock.isYou ? lamp : ink)
                    Text(clock.note)
                        .font(.system(size: 9))
                        .foregroundStyle(clock.isYou ? lamp : Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(clock.isYou ? lamp.opacity(0.11) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(clock.isYou ? lamp.opacity(0.4) : Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.13), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Needs Attention

    private var needsAttentionSection: some View {
        let warningPersons = coordinator.protectedPersons.filter { $0.isOverdue || $0.status == .overdue || $0.status == .alert }

        return Group {
            if !warningPersons.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("需要处理")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                    ForEach(warningPersons) { person in
                        NavigationLink(value: person.id) {
                            protectedPersonCard(
                                initial: person.user.avatarInitial, name: person.user.displayName,
                                tag: person.status == .alert ? "求助中" : "未打卡",
                                tagColor: person.status == .alert ? alert : Color(red: 138/255, green: 100/255, blue: 40/255),
                                tagBg: person.status == .alert ? alert : lamp,
                                detail: "\(person.user.cityName) · \(statusDetail(person))",
                                layers: person.protectionLayers, isWarning: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Demo fallback when no real data
                VStack(alignment: .leading, spacing: 7) {
                    Text("需要处理")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                    protectedPersonCard(
                        initial: "奶", name: "奶奶",
                        tag: "14 小时未打卡", tagColor: Color(red: 138/255, green: 100/255, blue: 40/255),
                        tagBg: lamp,
                        detail: "上海 · 当地已是晚上八点",
                        layers: 2, isWarning: true
                    )
                }
            }
        }
    }

    // MARK: - All Normal

    private var allNormalSection: some View {
        let normalPersons = coordinator.protectedPersons.filter { !$0.isOverdue && $0.status != .overdue && $0.status != .alert }

        return Group {
            if !normalPersons.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("一切正常")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                    ForEach(normalPersons) { person in
                        NavigationLink(value: person.id) {
                            protectedPersonCard(
                                initial: person.user.avatarInitial, name: person.user.displayName,
                                tag: nil, tagColor: nil,
                                detail: "\(person.user.cityName) · \(statusDetail(person))",
                                layers: person.protectionLayers
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Demo fallback
                VStack(alignment: .leading, spacing: 7) {
                    Text("一切正常")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                    protectedPersonCard(
                        initial: "雨", name: "小雨",
                        tag: "专业响应", tagColor: pro,
                        detail: "基辅 · 12 分钟前报平安",
                        layers: 3
                    )

                    protectedPersonCard(
                        initial: "弟", name: "弟弟",
                        tag: nil, tagColor: nil,
                        detail: "伦敦 · 在学校 · 电量 82%",
                        layers: 1
                    )

                    protectedPersonCard(
                        initial: "爸", name: "爸爸",
                        tag: nil, tagColor: nil,
                        detail: "多伦多 · 在家 · 在线",
                        layers: 2, isDimmed: true
                    )
                }
            }
        }
    }

    private func statusDetail(_ person: ProtectedPerson) -> String {
        if let checkIn = person.lastCheckIn {
            let minutes = Int(Date().timeIntervalSince(checkIn) / 60)
            if minutes < 60 {
                return "\(minutes) 分钟前报平安"
            } else {
                return "\(minutes / 60) 小时前报平安"
            }
        }
        return "尚未报平安"
    }

    // MARK: - Protected Person Card

    private func protectedPersonCard(
        initial: String, name: String,
        tag: String?, tagColor: Color?,
        tagBg: Color? = nil,
        detail: String, layers: Int,
        isWarning: Bool = false, isDimmed: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.08))
                    .frame(width: 34, height: 34)
                Text(initial)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(ink)
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
                            .background((tagBg ?? tagColor).opacity(tagBg != nil ? 0.22 : 0.14))
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

            // Protection layers
            VStack(spacing: 1) {
                Text("\(layers) 层")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                Text("保护")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isWarning ? lamp.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isWarning ? lamp.opacity(0.55) : Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.13), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}
