import SwiftUI
import MapKit
import Combine

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
    @State private var showInviteGuardian = false
    @State private var mapFocusId: String?
    @State private var checkInDone = false
    @State private var showHomeTimer = false
    @State private var showArrivalReport = false
    @State private var showItinerary = false
    @State private var showMedicalCard = false
    @State private var showEmergencyText = false
    @State private var showConsulate = false
    @State private var showClaimMaterials = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Design system colors from the HTML
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let creamBg = Color(red: 254/255, green: 252/255, blue: 247/255)
    private let offWhiteBg = Color(red: 251/255, green: 248/255, blue: 241/255)
    private let paneBorder = Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.13)

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    duoPaneLayout
                } else {
                    compactLayout
                }
            }
            .toolbar(sizeClass == .regular ? .hidden : .visible, for: .navigationBar)
            .navigationTitle("守灯")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(safe.opacity(0.08), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 5) {
                        AvatarView(user: coordinator.currentUser, size: 22)
                        if let name = coordinator.currentUser?.displayName, !name.isEmpty {
                            Text(name)
                                .font(.scaled(size: 12, weight: .medium))
                                .foregroundStyle(ink)
                        }
                        Text("·")
                            .font(.scaled(size: 11))
                            .foregroundStyle(safe.opacity(0.4))
                        Image(systemName: "shield.fill")
                            .font(.scaled(size: 8))
                            .foregroundStyle(safe)
                        Text(toolbarLocation)
                            .font(.scaled(size: 12))
                            .foregroundStyle(ink.opacity(0.55))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(toolbarBattery)
                        .font(.scaled(size: 12))
                        .foregroundStyle(ink.opacity(0.55))
                }
            }
            .navigationDestination(for: String.self) { guardianId in
                ProtectedGuardianDetailView(guardianId: guardianId)
            }
            .sheet(isPresented: $showSOSActive) {
                SOSActiveView()
            }
            .sheet(isPresented: $showInviteGuardian) {
                InviteGuardianView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showHomeTimer) {
                HomeTimerView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showArrivalReport) {
                ArrivalReportView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showItinerary) {
                SharedItineraryView()
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
            .sheet(isPresented: $showClaimMaterials) {
                ClaimMaterialsView()
                    .environmentObject(coordinator)
            }
            .featureDisclosure(.sos, trigger: $sosDisclosureTrigger)
            .task {
                coordinator.locationManager.requestSingleLocation()
                await coordinator.fetchGuardians()
                await coordinator.fetchFamilyPosts()
                await coordinator.fetchTimeline()
            }
        }
    }

    // MARK: - Compact Layout (Standard Phones)

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 0) {
                globeSection
                worldClocks
                    .padding(.top, 4)
                locationCard
                    .padding(.top, 10)
                sendLocationButton
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                trackingPauseToggle
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                sosButton
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                checkInButton
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                hotlineSection
                quickActions
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                guardianList
                    .padding(.top, 20)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Duo Pane Layout (Inner Screen)

    private var duoPaneLayout: some View {
        HStack(spacing: 0) {
            // LEFT PANE: Overview
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("守灯")
                            .font(.scaled(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(ink)
                        Spacer()
                        Text(toolbarBattery)
                            .font(.scaled(size: 12))
                            .foregroundStyle(ink.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(ink.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    HStack(spacing: 6) {
                        AvatarView(user: coordinator.currentUser, size: 26)
                        if let name = coordinator.currentUser?.displayName, !name.isEmpty {
                            Text(name)
                                .font(.scaled(size: 13, weight: .medium))
                                .foregroundStyle(ink)
                        }
                        Text("·")
                            .font(.scaled(size: 11))
                            .foregroundStyle(safe.opacity(0.3))
                        Image(systemName: "shield.fill")
                            .font(.scaled(size: 8))
                            .foregroundStyle(safe)
                        Text(toolbarLocation)
                            .font(.scaled(size: 12))
                            .foregroundStyle(ink.opacity(0.55))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    globeSection
                    worldClocks
                        .padding(.top, 4)

                    Spacer(minLength: 16)
                }
            }
            .frame(width: 445)
            .background(creamBg)

            Rectangle()
                .fill(paneBorder)
                .frame(width: 1)

            // RIGHT PANE: Actions & Guardians
            ScrollView {
                VStack(spacing: 0) {
                    locationCard
                        .padding(.top, 10)
                    sendLocationButton
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                    trackingPauseToggle
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    sosButton
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    checkInButton
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    hotlineSection
                    quickActions
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    guardianList
                        .padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .background(offWhiteBg)
        }
    }

    // MARK: - Shared Inline Sections

    private var hotlineSection: some View {
        Group {
            if let hotline = coordinator.selectedHotline {
                HotlineCardView(
                    hotline: hotline,
                    onTapChange: { showConsulate = true },
                    onRemove: { coordinator.removeSelectedHotline() }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
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

    private var toolbarBattery: String {
        let level = UIDevice.current.batteryLevel
        if level >= 0 {
            return "电量 \(Int(level * 100))%"
        }
        return "电量 --%"
    }

    // MARK: - Globe Section

    private var globeSection: some View {
        let dynamicPins: [GlobeMapView.Pin]
        let dynamicLinks: [GlobeMapView.Link]
        let layersText: String
        let subtitleText: String

        if !coordinator.myGuardians.isEmpty {
            var p: [GlobeMapView.Pin] = []
            let myCity = coordinator.currentUser?.cityName ?? ""
            let myCountry = coordinator.currentUser?.countryCode ?? ""
            let myLocParts = [myCity, Self.countryName(myCountry)].filter { !$0.isEmpty }
            let myLabel = myLocParts.isEmpty ? "我" : "我 · \(myLocParts.joined(separator: ", "))"
            let myCoord: CLLocationCoordinate2D = {
                if let loc = coordinator.locationManager.lastReportedLocation {
                    return loc.coordinate
                }
                if let user = coordinator.currentUser, !user.cityName.isEmpty {
                    return Self.coordForCity( user.cityName)
                }
                return CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
            }()
            p.append(.init(label: myLabel, latitude: myCoord.latitude, longitude: myCoord.longitude, color: lamp, isMe: true))
            for g in coordinator.myGuardians {
                let c = Self.coordForCity( g.user.cityName)
                let gCity = g.user.cityName
                let gLabel = gCity.isEmpty ? g.user.displayName : "\(g.user.displayName) · \(gCity)"
                p.append(.init(label: gLabel, latitude: c.latitude, longitude: c.longitude, color: safe, isMe: false))
            }
            dynamicPins = p
            dynamicLinks = (1..<p.count).map { GlobeMapView.Link(from: $0, to: 0) }

            var cities = [String]()
            if let c = coordinator.currentUser?.cityName, !c.isEmpty { cities.append(c) }
            for g in coordinator.myGuardians { if !g.user.cityName.isEmpty && !cities.contains(g.user.cityName) { cities.append(g.user.cityName) } }
            layersText = "\(coordinator.myGuardians.count) 位守护者"
            subtitleText = cities.isEmpty
                ? "守护中"
                : cities.prefix(3).joined(separator: " · ")
        } else {
            // No guardians yet — show just me
            var p: [GlobeMapView.Pin] = []
            let myCity = coordinator.currentUser?.cityName ?? ""
            let myCountry = coordinator.currentUser?.countryCode ?? ""
            let myLocStr = [myCity, Self.countryName(myCountry)].filter { !$0.isEmpty }.joined(separator: ", ")
            let myLabel = myLocStr.isEmpty ? "我" : "我 · \(myLocStr)"
            let fallbackCoord: CLLocationCoordinate2D = {
                if let loc = coordinator.locationManager.lastReportedLocation {
                    return loc.coordinate
                }
                if let user = coordinator.currentUser, !user.cityName.isEmpty {
                    return Self.coordForCity( user.cityName)
                }
                return CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
            }()
            p.append(.init(label: myLabel, latitude: fallbackCoord.latitude, longitude: fallbackCoord.longitude, color: lamp, isMe: true))
            dynamicPins = p
            dynamicLinks = []
            layersText = "守灯"
            subtitleText = "邀请家人加入守护"
        }

        return ZStack {
            // Dark card background
            RoundedRectangle(cornerRadius: 16)
                .fill(inkDeep)

            // Rotating globe with pins and arcs
            GlobeMapView(
                pins: dynamicPins,
                links: dynamicLinks,
                initialLongitude: -30
            )

            // Overlay: header + legend
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layersText)
                            .font(.scaled(size: 14, weight: .semibold, design: .serif))
                            .foregroundStyle(lamp)
                        Text(subtitleText)
                            .font(.scaled(size: 12))
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
                .font(.scaled(size: 11))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    // MARK: - World Clocks

    private var worldClocks: some View {
        let clocks: [(city: String, time: String, note: String, isMe: Bool)] = {
            var result: [(String, String, String, Bool)] = []
            // My time
            if let user = coordinator.currentUser {
                result.append((
                    user.cityName.isEmpty ? "我" : user.cityName,
                    localTime(user.timeZone),
                    "我在这",
                    true
                ))
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                result.append(("我", formatter.string(from: Date()), "我在这", true))
            }
            // Guardian times
            if !coordinator.myGuardians.isEmpty {
                for g in coordinator.myGuardians {
                    result.append((
                        g.user.cityName.isEmpty ? g.user.displayName : g.user.cityName,
                        localTime(g.user.timeZone),
                        timeOfDay(g.user.timeZone),
                        false
                    ))
                }
            }
            return result
        }()

        return HStack(spacing: 6) {
            ForEach(Array(clocks.enumerated()), id: \.offset) { _, clock in
                VStack(spacing: 2) {
                    Text(clock.city)
                        .font(.scaled(size: 11))
                        .foregroundStyle(ink.opacity(0.55))
                        .lineLimit(1)
                    Text(clock.time)
                        .font(.scaled(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(clock.isMe ? lamp : ink)
                    Text(clock.note)
                        .font(.scaled(size: 11))
                        .foregroundStyle(clock.isMe ? lamp : ink.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(clock.isMe ? lamp.opacity(0.11) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(clock.isMe ? lamp.opacity(0.4) : ink.opacity(0.13), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Location Card

    private var locationCard: some View {
        // Use best available location for fresher timestamp
        let deviceLocation = coordinator.locationManager.bestAvailableLocation
        let myCoord: CLLocationCoordinate2D = {
            if let loc = deviceLocation {
                return CLLocationCoordinate2D(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            }
            if let user = coordinator.currentUser, !user.cityName.isEmpty {
                return Self.coordForCity( user.cityName)
            }
            return CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4) // fallback: Beijing
        }()

        var pins: [LocationPin] = [
            LocationPin(id: "me", name: "我", coordinate: myCoord, color: lamp, isMe: true)
        ]
        // Show all guardians on the map
        if !coordinator.myGuardians.isEmpty {
            for g in coordinator.myGuardians {
                let coord = Self.coordForCity( g.user.cityName)
                pins.append(LocationPin(
                    id: g.id,
                    name: g.user.displayName,
                    coordinate: coord,
                    color: g.isOnDuty ? safe : Color(.systemGray3),
                    status: g.isOnDuty ? "值班中" : timeOfDay(g.user.timeZone)
                ))
            }
        }
        return LocationCardView(
            pins: pins,
            centerCoordinate: myCoord,
            lastUpdateMinutes: deviceLocation != nil ? Int(Date().timeIntervalSince(deviceLocation!.timestamp) / 60) : nil,
            label: "我的位置",
            focusedPinId: $mapFocusId
        )
    }

    // MARK: - Send Location Button

    private var sendLocationButton: some View {
        Button {
            shareMyLocation()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.scaled(size: 12))
                Text("发送我的位置给守护者")
                    .font(.scaled(size: 13, weight: .medium))
            }
            .foregroundStyle(safe)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(safe.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(safe.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private func shareMyLocation() {
        guard let loc = coordinator.locationManager.bestAvailableLocation else { return }
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        let mapURL = "https://maps.apple.com/?ll=\(lat),\(lng)&q=\(coordinator.currentUser?.displayName ?? "我的位置")"
        let items: [Any] = [mapURL]
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(ac, animated: true)
        }
    }

    private static func coordForCity(_ city: String) -> CLLocationCoordinate2D {
        switch city {
        case "多伦多", "Toronto": return CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
        case "上海", "Shanghai": return CLLocationCoordinate2D(latitude: 31.23, longitude: 121.47)
        case "悉尼", "Sydney": return CLLocationCoordinate2D(latitude: -33.87, longitude: 151.21)
        case "伦敦", "London": return CLLocationCoordinate2D(latitude: 51.50, longitude: -0.12)
        case "基辅", "Kyiv": return CLLocationCoordinate2D(latitude: 50.45, longitude: 30.52)
        case "北京", "Beijing": return CLLocationCoordinate2D(latitude: 39.90, longitude: 116.40)
        case "东京", "Tokyo": return CLLocationCoordinate2D(latitude: 35.68, longitude: 139.69)
        case "温哥华", "Vancouver": return CLLocationCoordinate2D(latitude: 49.28, longitude: -123.12)
        case "蒙特利尔", "Montreal": return CLLocationCoordinate2D(latitude: 45.50, longitude: -73.57)
        case "纽约", "New York": return CLLocationCoordinate2D(latitude: 40.71, longitude: -74.01)
        case "巴黎", "Paris": return CLLocationCoordinate2D(latitude: 48.86, longitude: 2.35)
        case "首尔", "Seoul": return CLLocationCoordinate2D(latitude: 37.57, longitude: 126.98)
        case "新加坡", "Singapore": return CLLocationCoordinate2D(latitude: 1.35, longitude: 103.82)
        case "香港", "Hong Kong": return CLLocationCoordinate2D(latitude: 22.32, longitude: 114.17)
        case "台北", "Taipei": return CLLocationCoordinate2D(latitude: 25.03, longitude: 121.57)
        case "广州", "Guangzhou": return CLLocationCoordinate2D(latitude: 23.13, longitude: 113.26)
        case "深圳", "Shenzhen": return CLLocationCoordinate2D(latitude: 22.54, longitude: 114.06)
        default: return CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0)
        }
    }

    private static func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? ""
    }

    // MARK: - Tracking Pause Toggle

    private var trackingPauseToggle: some View {
        let isPaused = coordinator.isTrackingPaused

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeInOut(duration: 0.3)) {
                if isPaused {
                    coordinator.resumeTracking()
                } else {
                    coordinator.pauseTracking()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isPaused ? "location.slash.fill" : "location.fill")
                    .font(.scaled(size: 13))
                    .foregroundStyle(isPaused ? .orange : safe)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isPaused ? "位置共享已暂停" : "位置共享中")
                        .font(.scaled(size: 13, weight: .medium))
                        .foregroundStyle(isPaused ? .orange : ink.opacity(0.7))

                    if isPaused {
                        let remaining = coordinator.trackingPauseRemainingMinutes
                        Text(remaining > 60 ? "\(remaining / 60)小时\(remaining % 60)分钟后自动恢复" : "\(remaining)分钟后自动恢复")
                            .font(.scaled(size: 11))
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                }

                Spacer()

                Text(isPaused ? "恢复" : "暂停")
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(isPaused ? .white : ink.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(isPaused ? Color.orange : ink.opacity(0.08)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPaused ? Color.orange.opacity(0.08) : safe.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isPaused ? Color.orange.opacity(0.2) : safe.opacity(0.1), lineWidth: 1)
                    )
            )
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
                    .font(.scaled(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 3.0)
                .onChanged { _ in
                    isSOSPressed = true
                    sosDisclosureTrigger = true
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    withAnimation(.linear(duration: 3.0)) {
                        sosProgress = 1.0
                    }
                }
                .onEnded { _ in
                    isSOSPressed = false
                    sosProgress = 0
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeInOut(duration: 0.3)) {
                checkInDone = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { checkInDone = false }
            }
        } label: {
            HStack(spacing: 6) {
                if checkInDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.scaled(size: 14))
                        .foregroundStyle(Color(red: 44/255, green: 107/255, blue: 81/255))
                    Text("已报平安")
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(Color(red: 44/255, green: 107/255, blue: 81/255))
                } else {
                    Text("今天我很好，报个平安")
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(Color(red: 44/255, green: 107/255, blue: 81/255))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(checkInDone ? safe.opacity(0.2) : safe.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .disabled(checkInDone)
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 8) {
            // Row 1: Daily use tools
            HStack(spacing: 8) {
                quickActionButton(
                    icon: "house.fill", label: "回家计时",
                    color: safe
                ) { showHomeTimer = true }

                quickActionButton(
                    icon: "mappin.circle.fill", label: "到达报告",
                    color: safe
                ) { showArrivalReport = true }

                quickActionButton(
                    icon: "airplane", label: "共享行程",
                    color: safe
                ) { showItinerary = true }
            }

            // Row 2: Emergency tools
            HStack(spacing: 8) {
                quickActionButton(
                    icon: "staroflife.fill", label: "医疗卡",
                    color: alert
                ) { showMedicalCard = true }

                quickActionButton(
                    icon: "text.bubble.fill", label: "多语言急救",
                    color: alert
                ) { showEmergencyText = true }

                quickActionButton(
                    icon: "building.columns.fill", label: "领事电话",
                    color: pro
                ) { showConsulate = true }
            }

            // Row 3: Insurance & records
            HStack(spacing: 8) {
                quickActionButton(
                    icon: "doc.text.magnifyingglass", label: "理赔材料",
                    color: safe
                ) { showClaimMaterials = true }

                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
    }

    private func quickActionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.scaled(size: 16))
                    .foregroundStyle(color)
                Text(label)
                    .font(.scaled(size: 12))
                    .foregroundStyle(ink.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
                                isOnDuty: true,
                                avatarPath: g.user.avatarLocalPath
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            withAnimation { mapFocusId = g.id }
                        })
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
                                isOnDuty: false,
                                avatarPath: g.user.avatarLocalPath
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            withAnimation { mapFocusId = g.id }
                        })
                    }
                }
            } else {
                // Empty state — no guardians linked yet
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.scaled(size: 28))
                        .foregroundStyle(ink.opacity(0.25))
                    Text("还没有守护者")
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(ink.opacity(0.6))
                    Text("邀请家人成为你的守护者，他们可以在紧急时刻收到你的求助信号。")
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 16)
            }

            // Add guardian button
            Button {
                showInviteGuardian = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.scaled(size: 16))
                    Text("邀请新的守护者")
                        .font(.scaled(size: 13, weight: .medium))
                }
                .foregroundStyle(safe)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(safe.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Footer
            VStack(spacing: 0) {
                Divider()
                Text("列表按「谁醒着」而非亲疏排序——慌乱时最需要知道的是谁最快能看到。")
                    .font(.scaled(size: 12))
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.scaled(size: 12))
            .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
            .padding(.horizontal, 18)
            .padding(.top, 4)
    }

    private func guardianCard(
        initial: String, name: String,
        tag: String?, tagColor: Color?,
        detail: String, time: String, timeNote: String,
        isOnDuty: Bool, isDimmed: Bool = false, isPro: Bool = false,
        avatarPath: String? = nil
    ) -> some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                AvatarView(user: nil, size: 34, initial: initial, avatarPath: avatarPath)

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
                        .font(.scaled(size: 13.5, weight: .medium))
                    if let tag, let tagColor {
                        Text(tag)
                            .font(.scaled(size: 11))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(tagColor.opacity(0.14))
                            .foregroundStyle(tagColor)
                            .clipShape(Capsule())
                    }
                }
                Text(detail)
                    .font(.scaled(size: 12))
                    .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.58))
                    .lineLimit(1)
            }

            Spacer()

            // Time
            VStack(alignment: .trailing, spacing: 1) {
                Text(time)
                    .font(.scaled(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                Text(timeNote)
                    .font(.scaled(size: 12))
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
    @State private var tick = Date()
    @State private var showClaimMaterialsPrompt = false
    @State private var showClaimMaterials = false
    nonisolated(unsafe) private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Persistent SOS banner — PDF: "SOS 进行中界面须常驻一行"
                Text(DisclaimerCopy.SOS.persistentBanner)
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(alert)

                // Network failure warning
                if coordinator.sosDeliveryFailed {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .font(.scaled(size: 12))
                        Text("求助信号暂未送达服务器，已存入离线队列，恢复网络后将自动重发")
                            .font(.scaled(size: 12))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                }

                ScrollView {
                    VStack(spacing: 16) {
                        // SOS circle
                        ZStack {
                            Circle()
                                .fill(alert)
                                .frame(width: 142, height: 142)
                            VStack(spacing: 2) {
                                Text("已发出")
                                    .font(.scaled(size: 26, weight: .black, design: .serif))
                                    .foregroundStyle(.white)
                                Text(sosTimeLocation)
                                    .font(.scaled(size: 12))
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
                            showClaimMaterialsPrompt = true
                        } label: {
                            Text("取消求助（我没事）")
                                .font(.scaled(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("求助已发出")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(timer) { tick = $0 }
            .alert("需要整理相关记录吗？", isPresented: $showClaimMaterialsPrompt) {
                Button("整理材料") { showClaimMaterials = true }
                Button("不需要", role: .cancel) { dismiss() }
            } message: {
                Text("导出事件前后的设备记录，供您自行使用。")
            }
            .sheet(isPresented: $showClaimMaterials, onDismiss: { dismiss() }) {
                ClaimMaterialsView().environmentObject(coordinator)
            }
        }
    }

    private var sosTimeLocation: String {
        if let sos = coordinator.activeSOSEvent {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let time = formatter.string(from: sos.triggeredAt)
            let city = coordinator.currentUser?.cityName ?? ""
            return city.isEmpty ? time : "\(time) · \(city)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private var escalationSteps: some View {
        let state = coordinator.activeSOSEvent?.escalationState ?? .initiated
        let guardianNames = escalationGuardianNames

        // Determine step states based on escalation
        let hop1Done: Bool = [.hop1_acknowledged, .hop2_allNotified, .hop3_voiceCalling, .hop3_exhausted, .frozen, .resolved].contains(state)
        let hop1Started: Bool = state == .hop1_notified || hop1Done
        let hop2Done: Bool = [.hop3_voiceCalling, .hop3_exhausted, .frozen, .resolved].contains(state)
        let hop2Started: Bool = state == .hop2_allNotified || hop2Done
        let hop3Started: Bool = [.hop3_voiceCalling, .hop3_exhausted].contains(state)

        let step1State: StepState = hop1Done ? .done : (hop1Started ? .live : .live)
        let step2State: StepState = hop2Done ? .done : (hop2Started ? .live : .waiting)
        let step3State: StepState = hop3Started ? .live : .waiting

        let elapsed = coordinator.activeSOSEvent.map {
            Int(tick.timeIntervalSince($0.triggeredAt))
        } ?? 0
        let mins = elapsed / 60
        let secs = elapsed % 60

        return VStack(spacing: 0) {
            HStack {
                Text("已进行 \(mins) 分 \(secs) 秒")
                    .font(.scaled(size: 11.5, weight: .medium))
                    .foregroundStyle(alert)
                Spacer()
            }
            .padding(12)
            .background(alert.opacity(0.09))

            stepRow(number: "1", title: "家人已收到",
                    detail: guardianNames.first.map { "\($0) 已通知" } ?? "正在通知家人",
                    state: step1State)
            stepRow(number: "2", title: "备用联系人已通知",
                    detail: guardianNames.count > 1 ? "\(guardianNames.dropFirst().joined(separator: "、")) 已收到" : "等待通知备用联系人",
                    state: step2State)
            stepRow(number: "3", title: "自动语音外呼",
                    detail: "系统将依次拨打家人电话，直到有人接听确认",
                    state: step3State)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private var escalationGuardianNames: [String] {
        return coordinator.myGuardians.map(\.user.displayName)
    }

    enum StepState { case done, live, waiting }

    private func stepRow(number: String, title: String, detail: String, state: StepState) -> some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                Circle()
                    .fill(state == .done ? safe : state == .live ? alert : Color(.systemGray5))
                    .frame(width: 19, height: 19)
                Text(number)
                    .font(.scaled(size: 12))
                    .foregroundStyle(state == .waiting ? Color.secondary : Color.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.scaled(size: 12.5, weight: .medium))
                Text(detail)
                    .font(.scaled(size: 12))
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
                .font(.scaled(size: 12))
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
            Text(label).font(.scaled(size: 13))
            Spacer()
            Text(value)
                .font(.scaled(size: 11.5))
                .foregroundStyle(isActive ? safe : .secondary)
        }
        .padding(.vertical, 2)
    }
}
