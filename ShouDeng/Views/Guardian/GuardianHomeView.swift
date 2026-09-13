import SwiftUI
import MapKit

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
    @State private var mapFocusId: String?

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    private var dynamicClocks: [(city: String, time: String, note: String, isYou: Bool)] {
        var result: [(String, String, String, Bool)] = []
        // My time (guardian)
        if let user = coordinator.currentUser {
            result.append((
                user.cityName.isEmpty ? "我" : user.cityName,
                localTime(user.timeZone),
                "你在这",
                true
            ))
        }
        // Protected persons' times
        if !coordinator.protectedPersons.isEmpty {
            for p in coordinator.protectedPersons {
                let tz = p.user.timeZone
                result.append((
                    p.user.cityName.isEmpty ? p.user.displayName : p.user.cityName,
                    localTime(tz),
                    timeOfDay(tz),
                    false
                ))
            }
        } else {
            // Demo fallback
            result.append(contentsOf: [
                ("基辅", "14:07", "白天", false),
                ("上海", "20:07", "夜晚", false),
                ("伦敦", "12:07", "白天", false),
            ])
            if result.isEmpty {
                result.insert(("多伦多", "07:07", "你在这", true), at: 0)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    globeSection
                    worldClocks
                        .padding(.top, 4)

                    // Location card
                    locationCard
                        .padding(.top, 10)

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
            .toolbarBackground(pro.opacity(0.06), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 5) {
                        AvatarView(user: coordinator.currentUser, size: 22)
                        if let name = coordinator.currentUser?.displayName, !name.isEmpty {
                            Text(name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ink)
                        }
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundStyle(pro.opacity(0.4))
                        Image(systemName: "eye.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(pro)
                        Text(toolbarLocation)
                            .font(.system(size: 10))
                            .foregroundStyle(ink.opacity(0.42))
                    }
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
                await coordinator.fetchFamilyPosts()
            }
        }
    }

    private var toolbarLocation: String {
        if let user = coordinator.currentUser {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = user.timeZone
            let time = formatter.string(from: Date())
            return user.cityName.isEmpty ? time : "\(user.cityName) \(time)"
        }
        return ""
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
            ForEach(Array(dynamicClocks.enumerated()), id: \.offset) { _, clock in
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

    // MARK: - Location Card

    private var locationCard: some View {
        // Demo pins for protected persons
        let demoPins: [LocationPin] = [
            LocationPin(id: "xiaoyu", name: "小雨", coordinate: CLLocationCoordinate2D(latitude: 50.45, longitude: 30.52), color: lamp, status: "12分钟前"),
            LocationPin(id: "nainai", name: "奶奶", coordinate: CLLocationCoordinate2D(latitude: 31.23, longitude: 121.47), color: lamp, status: "14小时前"),
            LocationPin(id: "didi", name: "弟弟", coordinate: CLLocationCoordinate2D(latitude: 51.50, longitude: -0.12), color: lamp, status: "在线"),
            LocationPin(id: "baba", name: "爸爸", coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38), color: safe, isMe: true, status: "在线"),
        ]

        // Use real data if available, else demo
        let pins: [LocationPin]
        if !coordinator.protectedPersons.isEmpty {
            pins = coordinator.protectedPersons.compactMap { person -> LocationPin? in
                guard let loc = person.lastKnownLocation else { return nil }
                return LocationPin(
                    id: person.id,
                    name: person.user.displayName,
                    coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                    color: person.status == .alert ? alert : lamp
                )
            }
        } else {
            pins = demoPins
        }

        return LocationCardView(
            pins: pins.isEmpty ? demoPins : pins,
            lastUpdateMinutes: 12,
            label: "家人位置",
            focusedPinId: $mapFocusId
        )
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
                                layers: person.protectionLayers, isWarning: true,
                                avatarPath: person.user.avatarLocalPath
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            withAnimation { mapFocusId = person.id }
                        })
                    }
                }
            } else {
                // Demo fallback when no real data
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("需要处理")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
                        Spacer()
                        Text("演示数据")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.6))
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    protectedPersonCard(
                        initial: "奶", name: "奶奶",
                        tag: "14 小时未打卡", tagColor: Color(red: 138/255, green: 100/255, blue: 40/255),
                        tagBg: lamp,
                        detail: "上海 · 当地已是晚上八点",
                        layers: 2, isWarning: true
                    )
                    .onTapGesture { withAnimation { mapFocusId = mapFocusId == "nainai" ? nil : "nainai" } }
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
                                layers: person.protectionLayers,
                                avatarPath: person.user.avatarLocalPath
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            withAnimation { mapFocusId = person.id }
                        })
                    }
                }
            } else {
                // Demo fallback
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("一切正常")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
                        Spacer()
                        Text("演示数据")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.6))
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    protectedPersonCard(
                        initial: "雨", name: "小雨",
                        tag: "专业响应", tagColor: pro,
                        detail: "基辅 · 12 分钟前报平安",
                        layers: 3
                    )
                    .onTapGesture { withAnimation { mapFocusId = mapFocusId == "xiaoyu" ? nil : "xiaoyu" } }

                    protectedPersonCard(
                        initial: "弟", name: "弟弟",
                        tag: nil, tagColor: nil,
                        detail: "伦敦 · 在学校 · 电量 82%",
                        layers: 1
                    )
                    .onTapGesture { withAnimation { mapFocusId = mapFocusId == "didi" ? nil : "didi" } }

                    protectedPersonCard(
                        initial: "爸", name: "爸爸",
                        tag: nil, tagColor: nil,
                        detail: "多伦多 · 在家 · 在线",
                        layers: 2, isDimmed: true
                    )
                    .onTapGesture { withAnimation { mapFocusId = mapFocusId == "baba" ? nil : "baba" } }
                }
            }
        }
    }

    private func localTime(_ tz: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = tz
        return formatter.string(from: Date())
    }

    private func timeOfDay(_ tz: TimeZone) -> String {
        var cal = Calendar.current
        cal.timeZone = tz
        let hour = cal.component(.hour, from: Date())
        if hour >= 6 && hour < 9 { return "清晨" }
        if hour >= 9 && hour < 12 { return "上午" }
        if hour >= 12 && hour < 14 { return "中午" }
        if hour >= 14 && hour < 18 { return "下午" }
        if hour >= 18 && hour < 22 { return "晚上" }
        return "深夜"
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
        isWarning: Bool = false, isDimmed: Bool = false,
        avatarPath: String? = nil
    ) -> some View {
        HStack(spacing: 10) {
            // Avatar
            AvatarView(user: nil, size: 34, initial: initial, avatarPath: avatarPath)
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
