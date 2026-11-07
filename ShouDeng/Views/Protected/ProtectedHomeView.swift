import SwiftUI
import TipKit
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
    @State private var locationSent = false
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var isSOSPressed = false
    @State private var sosProgress: Double = 0
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
    @State private var showNoGuardianSOSWarning = false
    @State private var showTripHistory = false
    @State private var showTripStartConfirm = false
    @State private var showTripPreflight = false
    @State private var showTripEndConfirm = false
    @State private var showFakeCall = false
    @State private var showDeadManSwitch = false
    @State private var showTrackerDetection = false
    @State private var showDisguiseMode = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Design system colors from the HTML
    private let ink = Color.appInk
    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let creamBg = Color.paper(254, 252, 247)
    private let offWhiteBg = Color.paper(251, 248, 241, elevated: true)
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
            .navigationTitle(lang.localized("nav.title"))
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
            .alert(lang.localized("sos.no.guardian.title"), isPresented: $showNoGuardianSOSWarning) {
                Button(lang.localized("sos.send.anyway")) {
                    coordinator.requestSOS(method: .longPress)
                }
                Button(lang.localized("sos.invite.first"), role: .cancel) {
                    showInviteGuardian = true
                }
            } message: {
                Text(lang.localized("sos.no.guardian.message"))
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
            .sheet(isPresented: $showTripHistory) {
                TripHistoryView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showFakeCall) {
                FakeCallSettingsView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showDeadManSwitch) {
                DeadManSwitchView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showTrackerDetection) {
                TrackerDetectionView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showTripPreflight) {
                TripPreflightView {
                    Task { try? await coordinator.tripRecordingService.startRecording() }
                }
            }
            .alert(lang.localized("trip.record.start"), isPresented: $showTripStartConfirm) {
                Button(lang.localized("settings.action.confirm")) {
                    Task { try? await coordinator.tripRecordingService.startRecording() }
                }
                Button(lang.localized("settings.action.cancel"), role: .cancel) {}
            } message: {
                Text(lang.localized("trip.record.confirm.start"))
            }
            .alert(lang.localized("trip.record.stop"), isPresented: $showTripEndConfirm) {
                Button(lang.localized("settings.action.confirm")) {
                    Task { try? await coordinator.tripRecordingService.stopRecording() }
                }
                Button(lang.localized("settings.action.cancel"), role: .cancel) {}
            } message: {
                Text(lang.localized("trip.record.confirm.end"))
            }
            .featureDisclosure(.sos, trigger: $sosDisclosureTrigger, emergencyNumber: coordinator.localEmergencyNumber)
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
                liveTrackingBanner
                    .coachMark(CoachAnchor.tracking)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                if coordinator.myGuardians.isEmpty, let tip = AppTips.available(InviteGuardianTip()) {
                    TipView(tip) { action in
                        if action.id == "invite" { showInviteGuardian = true }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                globeSection
                    .coachMark(CoachAnchor.guardiansGlobe)
                worldClocks
                    .padding(.top, 4)

                // Quick action pills: Home Safe + Language + Font Size
                QuickPillRow()
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                locationCard
                    .padding(.top, 10)
                tripRecordingSection
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                sendLocationButton
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
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
                // Watch back the guardians (they agree; the carer's plan covers it)
                WatchBackPanel()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                Button {
                    coordinator.setHomeStyle(.simple)
                } label: {
                    Text(lang.localized("simple.switchToSimple"))
                        .font(.scaled(size: 14))
                        .foregroundStyle(.secondary)
                        .underline()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Duo Pane Layout (Inner Screen)

    private var duoPaneLayout: some View {
        FoldSplitView(dividerColor: paneBorder) {
            // LEFT PANE: Overview
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text(lang.localized("protected.home.appName"))
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

                    liveTrackingBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    globeSection
                    worldClocks
                        .padding(.top, 4)

                    Spacer(minLength: 16)
                }
            }
            .background(creamBg)
        } trailing: {
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
            return String(format: lang.localized("protected.home.battery"), Int(level * 100))
        }
        return lang.localized("protected.home.batteryUnknown")
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
            let myLabel = myLocParts.isEmpty ? lang.localized("protected.home.me") : "\(lang.localized("protected.home.me")) · \(myLocParts.joined(separator: ", "))"
            let myCoord: CLLocationCoordinate2D = {
                if let live = coordinator.locationService.currentLocation {
                    return live
                }
                if let loc = coordinator.locationManager.lastReportedLocation {
                    return loc.coordinate
                }
                if let user = coordinator.currentUser, !user.cityName.isEmpty {
                    return Self.coordForCity(user.cityName)
                }
                return CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
            }()
            p.append(.init(label: myLabel, latitude: myCoord.latitude, longitude: myCoord.longitude, color: lamp, isMe: true))
            for g in coordinator.myGuardians {
                let gCoord: CLLocationCoordinate2D = {
                    if let memberLoc = coordinator.locationService.memberLocations[g.user.id] {
                        return memberLoc.coordinate
                    }
                    return Self.coordForCity(g.user.cityName)
                }()
                let gCity = g.user.cityName
                let gLabel = gCity.isEmpty ? g.user.displayName : "\(g.user.displayName) · \(gCity)"
                p.append(.init(label: gLabel, latitude: gCoord.latitude, longitude: gCoord.longitude, color: safe, isMe: false))
            }
            dynamicPins = p
            dynamicLinks = (1..<p.count).map { GlobeMapView.Link(from: $0, to: 0) }

            var cities = [String]()
            if let c = coordinator.currentUser?.cityName, !c.isEmpty { cities.append(c) }
            for g in coordinator.myGuardians { if !g.user.cityName.isEmpty && !cities.contains(g.user.cityName) { cities.append(g.user.cityName) } }
            layersText = String(format: lang.localized("protected.home.guardianCount"), coordinator.myGuardians.count)
            subtitleText = cities.isEmpty
                ? lang.localized("protected.home.guarding")
                : cities.prefix(3).joined(separator: " · ")
        } else {
            // No guardians yet — show just me
            var p: [GlobeMapView.Pin] = []
            let myCity = coordinator.currentUser?.cityName ?? ""
            let myCountry = coordinator.currentUser?.countryCode ?? ""
            let myLocStr = [myCity, Self.countryName(myCountry)].filter { !$0.isEmpty }.joined(separator: ", ")
            let myLabel = myLocStr.isEmpty ? lang.localized("protected.home.me") : "\(lang.localized("protected.home.me")) · \(myLocStr)"
            let fallbackCoord: CLLocationCoordinate2D = {
                if let live = coordinator.locationService.currentLocation {
                    return live
                }
                if let loc = coordinator.locationManager.lastReportedLocation {
                    return loc.coordinate
                }
                if let user = coordinator.currentUser, !user.cityName.isEmpty {
                    return Self.coordForCity(user.cityName)
                }
                return CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
            }()
            p.append(.init(label: myLabel, latitude: fallbackCoord.latitude, longitude: fallbackCoord.longitude, color: lamp, isMe: true))
            dynamicPins = p
            dynamicLinks = []
            layersText = lang.localized("protected.home.appName")
            subtitleText = lang.localized("protected.home.inviteFamily")
        }

        return ZStack {
            // Dark card background
            RoundedRectangle(cornerRadius: 16)
                .fill(inkDeep)

            // Rotating globe with pins and arcs
            GlobeMapView(
                pins: dynamicPins,
                links: dynamicLinks,
                initialLongitude: -30,
                labelInsets: EdgeInsets(top: 46, leading: 0, bottom: 26, trailing: 0)
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
                    legendDot(color: lamp, label: lang.localized("protected.home.me"))
                    legendDot(color: safe, label: lang.localized("protected.home.guardian"))
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
                    user.cityName.isEmpty ? lang.localized("protected.home.me") : user.cityName,
                    localTime(user.timeZone),
                    lang.localized("protected.home.imHere"),
                    true
                ))
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                result.append((lang.localized("protected.home.me"), formatter.string(from: Date()), lang.localized("protected.home.imHere"), true))
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
            LocationPin(id: "me", name: lang.localized("protected.home.me"), coordinate: myCoord, color: lamp, isMe: true, role: .me)
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
                    status: g.isOnDuty ? lang.localized("protected.home.onDuty") : timeOfDay(g.user.timeZone),
                    role: .guardian
                ))
            }
        }
        return LocationCardView(
            pins: pins,
            centerCoordinate: myCoord,
            lastUpdateMinutes: deviceLocation.map { Int(Date().timeIntervalSince($0.timestamp) / 60) },
            label: lang.localized("protected.home.myLocation"),
            focusedPinId: $mapFocusId,
            locationService: coordinator.locationService
        )
    }

    // MARK: - Trip Recording Section

    @ViewBuilder
    private var tripRecordingSection: some View {
        if coordinator.tripRecordingService.isRecording {
            // Recording banner
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                Text(lang.localized("trip.record.recording"))
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(coordinator.tripRecordingService.elapsedFormatted)
                    .font(.scaled(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                Text(coordinator.tripRecordingService.distanceFormatted)
                    .font(.scaled(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    showTripEndConfirm = true
                } label: {
                    Text(lang.localized("trip.record.stop"))
                        .font(.scaled(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.25))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            // Start recording + view history
            HStack(spacing: 8) {
                Button {
                    // Preflight checklist (offline maps, Find My, satellite SOS) unless
                    // the person chose to skip it; then the plain confirmation.
                    if UserDefaults.standard.bool(forKey: TripPreflightView.skipKey) {
                        showTripStartConfirm = true
                    } else {
                        showTripPreflight = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "record.circle")
                            .font(.scaled(size: 13))
                        Text(lang.localized("trip.record.start"))
                            .font(.scaled(size: 13, weight: .medium))
                    }
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(ink.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    showTripHistory = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.scaled(size: 13))
                        Text(lang.localized("trip.history.title"))
                            .font(.scaled(size: 13, weight: .medium))
                    }
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(ink.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Send Location Button

    private var sendLocationButton: some View {
        Button {
            coordinator.sendLocationToGuardians()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { locationSent = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { locationSent = false } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: locationSent ? "checkmark.circle.fill" : "location.fill")
                    .font(.scaled(size: 12))
                Text(lang.localized(locationSent ? "home.locationSent" : "protected.home.sendLocation"))
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
        // Long press: send a Maps link with any app instead
        .contextMenu {
            Button { shareMyLocation() } label: {
                Label(lang.localized("home.shareMapsLink"), systemImage: "square.and.arrow.up")
            }
        }
    }

    private func shareMyLocation() {
        guard let loc = coordinator.locationManager.bestAvailableLocation else { return }
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        let mapURL = "https://maps.apple.com/?ll=\(lat),\(lng)&q=\(coordinator.currentUser?.displayName ?? lang.localized("protected.home.myLocation"))"
        let items: [Any] = [mapURL]
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        AppCoordinator.topViewController()?.present(ac, animated: true)
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
        code.isEmpty ? "" : RegionalEmergencyInfo.regionName(code)
    }

    // MARK: - Live Tracking Banner (loc-banner from prototype)

    private var liveTrackingBanner: some View {
        let isPaused = coordinator.isTrackingPaused
        let deviceLocation = coordinator.locationManager.bestAvailableLocation
        let guardianCount = coordinator.myGuardians.count

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
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 6) {
                    // Status badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isPaused ? alert : safe)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .fill(isPaused ? alert.opacity(0.3) : safe.opacity(0.3))
                                    .frame(width: 16, height: 16)
                            )

                        Text(isPaused
                             ? lang.localized("tracking.banner.paused", fallback: "Live Tracking: PAUSED")
                             : lang.localized("tracking.banner.on", fallback: "Live Tracking: ON"))
                            .font(.scaled(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    // Address
                    if let user = coordinator.currentUser, !user.cityName.isEmpty {
                        Text(user.cityName)
                            .font(.scaled(size: 12))
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    // Coordinates
                    if let loc = deviceLocation {
                        let lat = loc.coordinate.latitude
                        let lng = loc.coordinate.longitude
                        let latDir = lat >= 0 ? "N" : "S"
                        let lngDir = lng >= 0 ? "E" : "W"
                        Text(String(format: "%.4f° %@ , %.4f° %@", abs(lat), latDir, abs(lng), lngDir))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // Update time + guardian count
                    HStack(spacing: 4) {
                        if let loc = deviceLocation {
                            let mins = Int(Date().timeIntervalSince(loc.timestamp) / 60)
                            Text(mins < 1
                                 ? lang.localized("tracking.banner.justNow", fallback: "Updated just now")
                                 : String(format: lang.localized("tracking.banner.minsAgo", fallback: "Updated %d min ago"), mins))
                                .font(.scaled(size: 11))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        if guardianCount > 0 {
                            Text("·")
                                .font(.scaled(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                            Text(String(format: lang.localized("tracking.banner.sharing", fallback: "Sharing with %d guardians"), guardianCount))
                                .font(.scaled(size: 11))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Toggle indicator
                ZStack {
                    Capsule()
                        .fill(isPaused ? alert.opacity(0.4) : safe.opacity(0.4))
                        .frame(width: 44, height: 24)
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .offset(x: isPaused ? -10 : 10)
                        .animation(.easeInOut(duration: 0.2), value: isPaused)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: isPaused
                        ? [Color(red: 50/255, green: 30/255, blue: 30/255), Color(red: 80/255, green: 40/255, blue: 35/255)]
                        : [Color(red: 18/255, green: 32/255, blue: 58/255), Color(red: 30/255, green: 52/255, blue: 80/255)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
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
                    Text(isPaused ? lang.localized("protected.home.trackingPaused") : lang.localized("protected.home.trackingActive"))
                        .font(.scaled(size: 13, weight: .medium))
                        .foregroundStyle(isPaused ? .orange : ink.opacity(0.7))

                    if isPaused {
                        let remaining = coordinator.trackingPauseRemainingMinutes
                        Text(remaining > 60 ? String(format: lang.localized("protected.home.resumeHoursMinutes"), remaining / 60, remaining % 60) : String(format: lang.localized("protected.home.resumeMinutes"), remaining))
                            .font(.scaled(size: 11))
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                }

                Spacer()

                Text(isPaused ? lang.localized("protected.home.resume") : lang.localized("protected.home.pause"))
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

                Text(isSOSPressed ? lang.localized("home.sos.hold") : lang.localized("home.sos.hold"))
                    .font(.scaled(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: FloatingSOSButton.holdDuration, maximumDistance: FloatingSOSButton.holdTolerance)
                .onChanged { _ in
                    isSOSPressed = true
                    sosDisclosureTrigger = true
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    withAnimation(.linear(duration: FloatingSOSButton.holdDuration)) {
                        sosProgress = 1.0
                    }
                }
                .onEnded { _ in
                    isSOSPressed = false
                    sosProgress = 0
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    if coordinator.myGuardians.isEmpty {
                        showNoGuardianSOSWarning = true
                    } else {
                        coordinator.requestSOS(method: .longPress)
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    // Released before the hold completed
                    if sosProgress < 1.0 {
                        withAnimation {
                            isSOSPressed = false
                            sosProgress = 0
                        }
                    }
                }
        )
        .accessibilityLabel(lang.localized("protected.home.sosLabel"))
        .accessibilityHint(lang.localized("protected.home.sosHint"))
        .accessibilityAddTraits(.isButton)
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
                    Text(lang.localized("home.checkin.done"))
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(Color(red: 44/255, green: 107/255, blue: 81/255))
                } else {
                    Text(lang.localized("home.checkin"))
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
        .accessibilityLabel(checkInDone ? lang.localized("protected.home.checkedIn") : lang.localized("protected.home.checkIn"))
        .accessibilityHint(lang.localized("protected.home.checkInHint"))
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 8) {
            // Row 1: Daily use tools
            HStack(spacing: 8) {
                quickActionButton(
                    icon: "house.fill", label: lang.localized("home.timer"),
                    color: safe
                ) { showHomeTimer = true }

                quickActionButton(
                    icon: "mappin.circle.fill", label: lang.localized("home.arrivalReport"),
                    color: safe
                ) { showArrivalReport = true }

                quickActionButton(
                    icon: "airplane", label: lang.localized("home.itinerary"),
                    color: safe
                ) { showItinerary = true }
            }

            // Row 2: Emergency tools
            HStack(spacing: 8) {
                quickActionButton(
                    icon: "staroflife.fill", label: lang.localized("home.medical"),
                    color: alert
                ) { showMedicalCard = true }

                quickActionButton(
                    icon: "text.bubble.fill", label: lang.localized("home.emergency.text"),
                    color: alert
                ) { showEmergencyText = true }

                quickActionButton(
                    icon: "building.columns.fill", label: lang.localized("home.consulate"),
                    color: pro
                ) { showConsulate = true }
            }

            // Row 3: Safety tools
            HStack(spacing: 8) {
                quickActionButton(
                    icon: "phone.arrow.down.left.fill", label: lang.localized("home.fakeCall"),
                    color: pro
                ) { showFakeCall = true }

                quickActionButton(
                    icon: "timer.circle.fill", label: lang.localized("home.safetyTimer"),
                    color: lamp
                ) { showDeadManSwitch = true }

                quickActionButton(
                    icon: "antenna.radiowaves.left.and.right", label: lang.localized("home.trackerScan"),
                    color: alert
                ) { showTrackerDetection = true }
            }

            // Row 4: Insurance & records
            HStack(spacing: 8) {
                quickActionButton(
                    icon: "doc.text.magnifyingglass", label: lang.localized("home.claim"),
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
        .accessibilityLabel(label)
    }

    // MARK: - Guardian List

    private var guardianList: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !coordinator.myGuardians.isEmpty {
                let onDuty = coordinator.myGuardians.filter { $0.isOnDuty }
                let offDuty = coordinator.myGuardians.filter { !$0.isOnDuty }

                if !onDuty.isEmpty {
                    sectionHeader(lang.localized("protected.home.onDutySection"))
                    ForEach(onDuty) { g in
                        NavigationLink(value: g.id) {
                            guardianCard(
                                initial: g.user.avatarInitial, name: g.user.displayName,
                                tag: lang.localized("protected.home.onDuty"), tagColor: safe,
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
                    sectionHeader(lang.localized("protected.home.otherGuardians"))
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
                    Text(lang.localized("home.no.guardian"))
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(ink.opacity(0.6))
                    Text(lang.localized("protected.home.inviteDescription"))
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
                    Text(lang.localized("protected.home.inviteNew"))
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
                Text(lang.localized("protected.home.sortExplanation"))
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
        if p.canSeeLocation { parts.append(lang.localized("protected.home.permLocation")) }
        if p.canSeeBattery { parts.append(lang.localized("protected.home.permBattery")) }
        if p.canSeeHealth { parts.append(lang.localized("protected.home.permHealth")) }
        return parts.isEmpty ? lang.localized("protected.home.emergencyOnly") : parts.joined(separator: "、")
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
        if hour >= 6 && hour < 9 { return lang.localized("protected.home.earlyMorning") }
        if hour >= 9 && hour < 12 { return lang.localized("protected.home.morning") }
        if hour >= 12 && hour < 14 { return lang.localized("protected.home.noon") }
        if hour >= 14 && hour < 18 { return lang.localized("protected.home.afternoon") }
        if hour >= 18 && hour < 22 { return lang.localized("protected.home.evening") }
        return lang.localized("protected.home.lateNight")
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
