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
    @State private var showInviteSheet = false
    @State private var showMedicalCard = false
    @State private var showEmergencyText = false
    @State private var showConsulate = false
    @State private var showOrgDashboard = false
    @State private var showInsuranceReport = false

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

                    // Pinned hotline card
                    if let hotline = coordinator.selectedHotline {
                        HotlineCardView(
                            hotline: hotline,
                            onTapChange: { showConsulate = true },
                            onRemove: { coordinator.removeSelectedHotline() }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    // Guardian quick actions
                    guardianQuickActions
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    // Add button
                    Button { showInviteSheet = true } label: {
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
                    GuardianAlertResponseView(personId: personId)
                } else {
                    GuardianMemberDetailView(personId: personId)
                }
            }
            .sheet(isPresented: $showInviteSheet) {
                InviteGuardianView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showMedicalCard) {
                MedicalCardView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showEmergencyText) {
                EmergencyTextCardView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showConsulate) {
                ConsulateView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showOrgDashboard) {
                OrgDashboardView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showInsuranceReport) {
                ClaimMaterialsView()
                    .environmentObject(coordinator)
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
        let dynamicPins: [GlobeMapView.Pin]
        let dynamicLinks: [GlobeMapView.Link]
        let familyText: String
        let subtitleText: String

        if !coordinator.protectedPersons.isEmpty {
            var p: [GlobeMapView.Pin] = []
            // Me (guardian)
            let myCity = coordinator.currentUser?.cityName ?? ""
            let myLabel = myCity.isEmpty ? "你" : "你 · \(myCity)"
            let myCoord: CLLocationCoordinate2D = {
                if let loc = coordinator.locationManager.lastReportedLocation {
                    return loc.coordinate
                }
                return Self.coordForCity(myCity)
            }()
            p.append(.init(label: myLabel, latitude: myCoord.latitude, longitude: myCoord.longitude, color: safe, isMe: true))
            // Protected persons
            for person in coordinator.protectedPersons {
                let lat: Double
                let lng: Double
                if let loc = person.lastKnownLocation {
                    lat = loc.latitude; lng = loc.longitude
                } else {
                    let c = Self.coordForCity(person.user.cityName)
                    lat = c.latitude; lng = c.longitude
                }
                let label = person.user.cityName.isEmpty ? person.user.displayName : "\(person.user.displayName) · \(person.user.cityName)"
                p.append(.init(label: label, latitude: lat, longitude: lng, color: lamp, isMe: false))
            }
            // Response centers
            p.append(.init(label: "响应中心", latitude: 25.20, longitude: 55.27, color: pro, isMe: false))
            p.append(.init(label: "响应中心", latitude: 1.35, longitude: 103.82, color: pro, isMe: false))
            dynamicPins = p
            // Guardian → each protected person, response centers → first protected person
            var lnks: [GlobeMapView.Link] = []
            let protectedCount = coordinator.protectedPersons.count
            for i in 1...protectedCount { lnks.append(.init(from: 0, to: i)) }
            for i in (protectedCount + 1)..<p.count { lnks.append(.init(from: i, to: 1)) }
            dynamicLinks = lnks

            var countries = Set<String>()
            if let cc = coordinator.currentUser?.countryCode, !cc.isEmpty { countries.insert(cc) }
            for person in coordinator.protectedPersons { if !person.user.countryCode.isEmpty { countries.insert(person.user.countryCode) } }
            let totalFamily = coordinator.protectedPersons.count
            familyText = "\(totalFamily) 位家人"
            subtitleText = "分布在 \(max(countries.count, 1)) 个国家"
        } else {
            // No protected persons yet — show just me + response centers
            var p: [GlobeMapView.Pin] = []
            let myCity = coordinator.currentUser?.cityName ?? ""
            let myLabel = myCity.isEmpty ? "你" : "你 · \(myCity)"
            let myCoord: CLLocationCoordinate2D = {
                if let loc = coordinator.locationManager.lastReportedLocation {
                    return loc.coordinate
                }
                return Self.coordForCity(myCity)
            }()
            p.append(.init(label: myLabel, latitude: myCoord.latitude, longitude: myCoord.longitude, color: safe, isMe: true))
            p.append(.init(label: "响应中心", latitude: 25.20, longitude: 55.27, color: pro, isMe: false))
            p.append(.init(label: "响应中心", latitude: 1.35, longitude: 103.82, color: pro, isMe: false))
            dynamicPins = p
            dynamicLinks = [.init(from: 1, to: 0), .init(from: 2, to: 0)]
            familyText = "守护者"
            subtitleText = "邀请家人加入"
        }

        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(inkDeep)

            GlobeMapView(
                pins: dynamicPins,
                links: dynamicLinks,
                initialLongitude: 60
            )

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(familyText)
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .foregroundStyle(lamp)
                        Text(subtitleText)
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

    private static func coordForCity(_ city: String) -> CLLocationCoordinate2D {
        switch city {
        case "多伦多": return CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
        case "上海": return CLLocationCoordinate2D(latitude: 31.23, longitude: 121.47)
        case "悉尼": return CLLocationCoordinate2D(latitude: -33.87, longitude: 151.21)
        case "伦敦": return CLLocationCoordinate2D(latitude: 51.50, longitude: -0.12)
        case "基辅": return CLLocationCoordinate2D(latitude: 50.45, longitude: 30.52)
        case "北京": return CLLocationCoordinate2D(latitude: 39.90, longitude: 116.40)
        case "东京": return CLLocationCoordinate2D(latitude: 35.68, longitude: 139.69)
        default: return CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)
        }
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
        let pins: [LocationPin] = coordinator.protectedPersons.compactMap { person -> LocationPin? in
            guard let loc = person.lastKnownLocation else { return nil }
            return LocationPin(
                id: person.id,
                name: person.user.displayName,
                coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                color: person.status == .alert ? alert : lamp
            )
        }

        return Group {
            if !pins.isEmpty {
                LocationCardView(
                    pins: pins,
                    label: "家人位置",
                    focusedPinId: $mapFocusId
                )
            } else {
                // No location data yet
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.system(size: 22))
                        .foregroundStyle(ink.opacity(0.2))
                    Text("暂无家人位置信息")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(ink.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 16)
            }
        }
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
            }
        }
    }

    // MARK: - Guardian Quick Actions

    private var guardianQuickActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                gQuickButton(icon: "staroflife.fill", label: "医疗卡", color: alert) { showMedicalCard = true }
                gQuickButton(icon: "text.bubble.fill", label: "多语言急救", color: alert) { showEmergencyText = true }
                gQuickButton(icon: "building.columns.fill", label: "领事电话", color: pro) { showConsulate = true }
            }
            HStack(spacing: 8) {
                gQuickButton(icon: "building.2.fill", label: "机构看板", color: safe) { showOrgDashboard = true }
                gQuickButton(icon: "doc.text.magnifyingglass", label: "理赔材料", color: safe) { showInsuranceReport = true }
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1) // spacer
            }
        }
    }

    private func gQuickButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(ink.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
            } else if coordinator.protectedPersons.isEmpty {
                // Empty state — no protected persons linked yet
                VStack(spacing: 12) {
                    Image(systemName: "shield.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(ink.opacity(0.25))
                    Text("还没有守护对象")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ink.opacity(0.6))
                    Text("邀请家人加入，你将能看到他们的安全状态并在紧急时刻收到通知。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 16)
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
