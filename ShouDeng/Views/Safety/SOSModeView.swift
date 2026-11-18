import SwiftUI
import Combine
import MapKit
import LocalAuthentication
import MessageUI
import CoreLocation

// MARK: - SOS mode (protected person)
//
// Shown from the moment an SOS is sent until the person ends it:
//  - red header: running time, live-location sharing, delivery problems
//  - who has been told / who is handling it
//  - two big calls: the guardian on duty, and the local emergency number
//  - if the server can't be reached (offline, or Google/Firebase blocked, e.g. on a
//    mainland-China network): "Text my guardians" opens Messages with their saved
//    numbers and my location filled in (SOSTextFallback); the queued SOS keeps retrying
//  - map: my live position and path, map styles, nearby help (hospitals, police,
//    pharmacies, fire stations, consulates, staffed places, transit) and routes,
//    which can be opened in Maps and sent to the family
//  - "I'm safe, end SOS": confirmed with Face ID / Touch ID / passcode; if a duress
//    code is set, entering it makes the SOS *look* ended while the family keeps
//    getting the live location
// The location sharing itself runs in AppCoordinator (SOS location mode) and keeps
// going with the screen closed or the phone locked.

struct SOSActiveView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lang = LanguageManager.shared
    @State private var showEnd = false
    @State private var showClaimPrompt = false
    @State private var showClaimMaterials = false
    @State private var textDraft: SOSTextDraft?
    @State private var textNote: String?
    private let pollTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color.appInk

    private var status: SOSStatus? { coordinator.ownSOSStatus }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    if status?.noGuardians == true { noGuardiansPanel }
                    guardiansPanel
                    // Re-checked every second so the text fallback shows up once the
                    // server has been silent for SOSTextFallback.waitForServer seconds.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(spacing: 12) {
                            if offersTextFallback(at: context.date) { textFallbackPanel }
                            callButtons
                        }
                    }
                    // Rider mode: street to read out, "say this to 000", bleeding control, crew
                    if coordinator.isRiderMode { RiderSOSPanel() }
                    SOSMapPanel()
                    endButton
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()   // swiping it away by accident must not hide an SOS
        .onReceive(pollTimer) { _ in Task { await coordinator.refreshOwnSOSStatus() } }
        .task { await coordinator.refreshOwnSOSStatus() }
        .sheet(isPresented: $showEnd) {
            EndSOSSheet(
                onEnd: {
                    showEnd = false
                    coordinator.cancelSOS()
                    showClaimPrompt = true
                },
                onConceal: {
                    showEnd = false
                    coordinator.concealSOS()
                }
            )
            .presentationDetents([.height(340), .medium, .large]) // drag up for large text
        }
        .alert(lang.localized("protected.home.claimPrompt"), isPresented: $showClaimPrompt) {
            Button(lang.localized("protected.home.claimOrganize")) { showClaimMaterials = true }
            Button(lang.localized("protected.home.claimNo"), role: .cancel) { dismiss() }
        } message: {
            Text(lang.localized("protected.home.claimDescription"))
        }
        .sheet(isPresented: $showClaimMaterials, onDismiss: { dismiss() }) {
            ClaimMaterialsView().environmentObject(coordinator)
        }
        .sheet(item: $textDraft) { draft in
            MessageComposer(draft: draft) { result in
                textDraft = nil
                if result == .sent { textNote = lang.localized("sos.text.sent") }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { coordinator.isSOSScreenPresented = false } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(lang.localized("sosmode.minimize"))
                Label(lang.localized(ended ? "sosmode.ended" : "sosmode.title"),
                      systemImage: ended ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.scaled(size: 20, weight: .bold))
                Spacer()
                if let started = coordinator.activeSOSEvent?.triggeredAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.elapsed(from: started, to: context.date))
                            .font(.scaled(size: 18, weight: .semibold).monospacedDigit())
                    }
                }
            }
            Text(headerDetail)
                .font(.scaled(size: 13))
                .opacity(0.95)
                .fixedSize(horizontal: false, vertical: true)
            if coordinator.isDemo {
                Text(lang.localized("explore.sos.practiceBanner"))
                    .font(.scaled(size: 12))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(ended ? safe : alert)
        .overlay(alignment: .bottom) {
            if coordinator.sosDeliveryFailed && status == nil && !ended {
                Label(lang.localized("protected.home.sosOfflineWarning"), systemImage: "wifi.slash")
                    .font(.scaled(size: 12))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .offset(y: 28)
            }
        }
        .zIndex(1)
    }

    /// Ended here (the claim-materials question is still on screen)
    private var ended: Bool { coordinator.activeSOSEvent == nil }

    private var headerDetail: String {
        if ended { return lang.localized("sosmode.ended.detail") }
        if status == nil { return lang.localized("sos.status.sending") }
        let count = max(status?.guardiansNotified ?? 0, coordinator.myGuardians.count)
        return lang.localized("sosmode.sharing", count: count)
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Who knows

    private var guardiansPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let ackName = status?.acknowledgedByName, status?.acknowledgedBy != nil {
                Label(String(format: lang.localized("sos.status.acknowledged"), ackName), systemImage: "person.fill.checkmark")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(safe))
            }
            ForEach(coordinator.myGuardians) { g in
                HStack {
                    Text(g.user.displayName).font(.scaled(size: 15, weight: g.isOnDuty ? .semibold : .regular))
                    if g.isOnDuty {
                        Text(lang.localized("sosmode.onDuty"))
                            .font(.scaled(size: 11)).foregroundStyle(safe)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(safe.opacity(0.12)))
                    }
                    Spacer()
                    Text(guardianState(g))
                        .font(.scaled(size: 13))
                        .foregroundStyle(status?.acknowledgedBy == g.user.id ? safe : .secondary)
                }
            }
        }
    }

    private func guardianState(_ g: Guardian) -> String {
        if status?.acknowledgedBy == g.user.id { return lang.localized("sosmode.handling") }
        if (status?.guardiansNotified ?? 0) > 0 { return lang.localized("sosmode.notified") }
        return lang.localized("sosmode.notifying")
    }

    private var noGuardiansPanel: some View {
        Text(String(format: lang.localized("sos.status.noGuardians"), coordinator.localEmergencyNumber))
            .font(.scaled(size: 14, weight: .semibold))
            .foregroundStyle(alert)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(alert.opacity(0.08)))
    }

    // MARK: Calls

    private var dutyGuardian: Guardian? {
        coordinator.myGuardians.first(where: { $0.isOnDuty && !($0.user.phone ?? "").isEmpty })
            ?? coordinator.myGuardians.first(where: { !($0.user.phone ?? "").isEmpty })
    }

    private var callButtons: some View {
        HStack(spacing: 10) {
            if let g = dutyGuardian, let phone = g.user.phone {
                callButton(title: String(format: lang.localized("sosmode.call"), g.user.displayName),
                           icon: "phone.fill", color: Color(red: 47/255, green: 111/255, blue: 143/255), number: phone)
            }
            callButton(title: String(format: lang.localized("sosmode.callEmergency"), coordinator.localEmergencyNumber),
                       icon: "cross.case.fill", color: Color(red: 139/255, green: 30/255, blue: 23/255),
                       number: coordinator.localEmergencyNumber)
        }
    }

    private func callButton(title: String, icon: String, color: Color, number: String) -> some View {
        Button {
            let digits = number.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:\(digits)") { ExternalURL.open(url) }
        } label: {
            Label(title, systemImage: icon)
                .font(.scaled(size: 17, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(RoundedRectangle(cornerRadius: 16).fill(color))
        }
        .buttonStyle(.plain)
    }

    // MARK: Text the guardians (server unreachable)

    private func offersTextFallback(at now: Date) -> Bool {
        SOSTextFallback.shouldOffer(ended: ended,
                                    reachedServer: coordinator.sosReachedServer,
                                    deliveryFailed: coordinator.sosDeliveryFailed,
                                    triggeredAt: coordinator.activeSOSEvent?.triggeredAt,
                                    now: now)
    }

    /// Saved guardians' numbers (cached on the phone, so this works offline), on-duty first
    private var guardianNumbers: [String] {
        let guardians = coordinator.myGuardians.filter(\.isOnDuty) + coordinator.myGuardians.filter { !$0.isOnDuty }
        return SOSTextFallback.recipients(guardians.map(\.user.phone))
    }

    private var textFallbackPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(lang.localized("sos.text.title"), systemImage: "antenna.radiowaves.left.and.right.slash")
                .font(.scaled(size: 16, weight: .bold))
                .foregroundStyle(alert)
            Text(lang.localized("sos.text.detail"))
                .font(.scaled(size: 14))
                .fixedSize(horizontal: false, vertical: true)
            Button { textGuardians() } label: {
                Label(lang.localized("sos.text.button"), systemImage: "message.fill")
                    .font(.scaled(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: 16).fill(alert))
            }
            .buttonStyle(.plain)
            Text(lang.localized(guardianNumbers.isEmpty ? "sos.text.noNumbers" : "sos.text.tapSend"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let textNote {
                Text(textNote)
                    .font(.scaled(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(alert.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(alert, lineWidth: 1.5))
    }

    private func textGuardians() {
        // The demo never texts anyone (ExternalURL blocks sms: the same way)
        if coordinator.isDemo {
            textNote = lang.localized("sos.text.demoNote")
            return
        }
        guard MFMessageComposeViewController.canSendText() else {
            textNote = lang.localized("sos.text.cannotSend")
            return
        }
        let fix = coordinator.locationManager.bestAvailableLocation
        let body = SOSTextFallback.messageBody(name: coordinator.currentUser?.displayName ?? "",
                                               coordinate: fix?.coordinate,
                                               at: fix?.timestamp ?? Date(),
                                               locale: Locale(identifier: lang.current.rawValue),
                                               timeZone: .current,
                                               localize: lang.localized)
        textNote = nil
        textDraft = SOSTextDraft(recipients: guardianNumbers, body: body)
    }

    // MARK: End

    private var endButton: some View {
        Button { showEnd = true } label: {
            Text(lang.localized("sosmode.end"))
                .font(.scaled(size: 17, weight: .semibold))
                .foregroundStyle(safe)
                .frame(maxWidth: .infinity, minHeight: 54)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(safe, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

// MARK: - End SOS

/// Ending needs the phone owner (Face ID / Touch ID / passcode), so someone else
/// holding the phone can't simply end it. With a duress code set, "enter code" is
/// offered too: the duress code makes it look ended and keeps the SOS going.
struct EndSOSSheet: View {
    let onEnd: () -> Void
    let onConceal: () -> Void
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var enteringCode = false
    @State private var code = ""
    @State private var error: String?
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    private var duressCode: String? { KeychainHelper.shared.read(.duressCode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lang.localized("sosmode.end.title"))
                .font(.scaled(size: 20, weight: .bold))
            Text(lang.localized("sosmode.end.message"))
                .font(.scaled(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if enteringCode {
                SecureField(lang.localized("sosmode.end.codePlaceholder"), text: $code)
                    .keyboardType(.numberPad)
                    .font(.scaled(size: 20))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))
                if let error {
                    Text(error).font(.scaled(size: 13)).foregroundStyle(.red)
                }
                Button { checkCode() } label: { primaryLabel(lang.localized("settings.action.confirm")) }
                    .buttonStyle(.plain)
            } else {
                Button { authenticate() } label: { primaryLabel(lang.localized("sosmode.end.confirm")) }
                    .buttonStyle(.plain)
                if duressCode != nil {
                    Button(lang.localized("sosmode.end.useCode")) { enteringCode = true }
                        .font(.scaled(size: 15))
                        .frame(maxWidth: .infinity)
                }
            }
            if let error, !enteringCode {
                Text(error).font(.scaled(size: 13)).foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title)
            .font(.scaled(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 14).fill(safe))
    }

    private func checkCode() {
        if let duress = duressCode, code == duress {
            onConceal()
        } else {
            error = lang.localized("sosmode.end.wrongCode")
            code = ""
        }
    }

    private func authenticate() {
        // The sample family has no owner to check
        if coordinator.isDemo { onEnd(); return }
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            onEnd()   // no passcode on this phone: nothing to check against
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: lang.localized("sosmode.end.reason")) { ok, _ in
            DispatchQueue.main.async {
                if ok { onEnd() } else { error = lang.localized("sosmode.end.failed") }
            }
        }
    }
}

// MARK: - Map: my position, path, nearby help, routes

struct SOSMapPanel: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    enum Style: String, CaseIterable { case standard, satellite, hybrid, night }
    enum Camera: String, CaseIterable { case followMe, showAll }

    enum Category: String, CaseIterable, Identifiable {
        case hospital, pharmacy, police, fire, consulate, staffed, transit
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .hospital: return "cross.case.fill"
            case .pharmacy: return "pills.fill"
            case .police: return "shield.fill"
            case .fire: return "flame.fill"
            case .consulate: return "building.columns.fill"
            case .staffed: return "storefront.fill"
            case .transit: return "tram.fill"
            }
        }
        var poi: [MKPointOfInterestCategory] {
            switch self {
            case .hospital: return [.hospital]
            case .pharmacy: return [.pharmacy]
            case .police: return [.police]
            case .fire: return [.fireStation]
            case .consulate: return []
            case .staffed: return [.hotel, .store]
            case .transit: return [.publicTransport]
            }
        }
    }

    struct Place: Identifiable, Equatable {
        let id = UUID()
        let item: MKMapItem
        let distance: CLLocationDistance
        var name: String { item.name ?? "" }
        var coordinate: CLLocationCoordinate2D { item.placemark.coordinate }
        static func == (a: Place, b: Place) -> Bool { a.id == b.id }
    }

    @State private var style: Style = .standard
    @State private var camera: Camera = .followMe
    @State private var showsTraffic = false
    @State private var showsTrail = true
    @State private var showOptions = false
    @State private var category: Category?
    @State private var places: [Place] = []
    @State private var searching = false
    @State private var selected: Place?
    @State private var walking = true
    @State private var route: MKRoute?
    @State private var routeShared = false
    @State private var position: MapCameraPosition = .automatic

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let blue = Color(red: 47/255, green: 111/255, blue: 143/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private var locale: Locale { Locale(identifier: lang.current.rawValue) }

    private var me: CLLocationCoordinate2D? { coordinator.locationManager.bestAvailableLocation?.coordinate }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            map
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topTrailing) { mapButtons }

            if showOptions { optionsPanel }

            Text(lang.localized("sosmode.nearby"))
                .font(.scaled(size: 14, weight: .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Category.allCases) { c in
                        Button { pick(c) } label: {
                            Label(lang.localized("sosmode.cat.\(c.rawValue)"), systemImage: c.icon)
                                .font(.scaled(size: 13, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .foregroundStyle(category == c ? .white : .primary)
                                .background(Capsule().fill(category == c ? Color(red: 18/255, green: 32/255, blue: 58/255) : Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let selected { routePanel(selected) } else if category != nil { placeList }
        }
        .onAppear { recenter() }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $position) {
            if showsTrail, coordinator.sosLocalTrail.count > 1 {
                MapPolyline(coordinates: coordinator.sosLocalTrail)
                    .stroke(alert, style: StrokeStyle(lineWidth: 3, dash: [4, 4]))
            }
            if let route {
                MapPolyline(route.polyline).stroke(blue, lineWidth: 6)
            }
            ForEach(places) { p in
                Marker(p.name, systemImage: category?.icon ?? "mappin", coordinate: p.coordinate)
                    .tint(p == selected ? .black : blue)
            }
            if let me {
                Annotation(lang.localized("protected.home.me"), coordinate: me) {
                    ZStack {
                        Circle().fill(alert.opacity(0.25)).frame(width: 34, height: 34)
                        Circle().fill(alert).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                }
            }
        }
        .mapStyle(mapStyle)
        .environment(\.colorScheme, style == .night ? .dark : .light)
    }

    private var mapStyle: MapStyle {
        switch style {
        case .standard: return .standard(pointsOfInterest: .including([.hospital, .police, .pharmacy, .fireStation]), showsTraffic: showsTraffic)
        case .satellite: return .imagery
        case .hybrid: return .hybrid(showsTraffic: showsTraffic)
        case .night: return .standard(emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: showsTraffic)
        }
    }

    private var mapButtons: some View {
        VStack(spacing: 8) {
            mapButton("location.fill", label: "sosmode.camera.followMe") { camera = .followMe; recenter() }
            mapButton("square.3.layers.3d", label: "sosmode.mapOptions") { withAnimation { showOptions.toggle() } }
        }
        .padding(8)
    }

    private func mapButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.localized(label))
    }

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(lang.localized("sosmode.style"), selection: $style) {
                ForEach(Style.allCases, id: \.self) { s in Text(lang.localized("sosmode.style.\(s.rawValue)")).tag(s) }
            }
            .pickerStyle(.segmented)
            Picker(lang.localized("sosmode.camera"), selection: $camera) {
                ForEach(Camera.allCases, id: \.self) { c in Text(lang.localized("sosmode.camera.\(c.rawValue)")).tag(c) }
            }
            .pickerStyle(.segmented)
            .onChange(of: camera) { _, _ in recenter() }
            Toggle(lang.localized("sosmode.traffic"), isOn: $showsTraffic).font(.scaled(size: 14))
            Toggle(lang.localized("sosmode.trail"), isOn: $showsTrail).font(.scaled(size: 14))
        }
        .tint(safe)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func recenter() {
        guard let me else { return }
        if camera == .showAll, !places.isEmpty || route != nil {
            var rect = MKMapRect(origin: MKMapPoint(me), size: MKMapSize(width: 1, height: 1))
            for p in places { rect = rect.union(MKMapRect(origin: MKMapPoint(p.coordinate), size: MKMapSize(width: 1, height: 1))) }
            if let route { rect = rect.union(route.polyline.boundingMapRect) }
            withAnimation { position = .rect(rect.insetBy(dx: -rect.width * 0.25 - 300, dy: -rect.height * 0.25 - 300)) }
        } else {
            withAnimation { position = .region(MKCoordinateRegion(center: me, latitudinalMeters: 900, longitudinalMeters: 900)) }
        }
    }

    // MARK: Nearby

    private var placeList: some View {
        VStack(spacing: 0) {
            if searching {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if places.isEmpty {
                Text(lang.localized("sosmode.nearby.none"))
                    .font(.scaled(size: 14)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding()
            }
            ForEach(places) { p in
                Button { select(p) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: category?.icon ?? "mappin").foregroundStyle(blue).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.scaled(size: 15)).lineLimit(1)
                            Text(distanceText(p.distance)).font(.scaled(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if p.distance <= 5_000 { // past ~1 h on foot, the distance says enough
                            Text(String(format: lang.localized("sosmode.walkMinutes"), max(1, Int(p.distance / 75))))
                                .font(.scaled(size: 13)).foregroundStyle(blue)
                        }
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road).locale(locale))
    }

    private func pick(_ c: Category) {
        selected = nil; route = nil; routeShared = false
        if category == c { category = nil; places = []; return }
        category = c
        search(c)
    }

    private func search(_ c: Category) {
        guard let me else { places = []; return }
        searching = true
        Task {
            let region = MKCoordinateRegion(center: me, latitudinalMeters: 5000, longitudinalMeters: 5000)
            var items: [MKMapItem] = []
            if c.poi.isEmpty {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = lang.localized("sosmode.cat.consulate.query")
                request.region = region
                items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
            } else {
                let request = MKLocalPointsOfInterestRequest(center: me, radius: 3000)
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: c.poi)
                items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
                // Category lookup can come back empty (mainland China map data); search by name
                if items.isEmpty {
                    let byName = MKLocalSearch.Request()
                    byName.naturalLanguageQuery = lang.localized("sosmode.cat.\(c.rawValue)")
                    byName.region = region
                    items = (try? await MKLocalSearch(request: byName).start())?.mapItems ?? []
                }
            }
            let here = CLLocation(latitude: me.latitude, longitude: me.longitude)
            let found = items.map { item in
                Place(item: item, distance: here.distance(from: CLLocation(latitude: item.placemark.coordinate.latitude,
                                                                           longitude: item.placemark.coordinate.longitude)))
            }
            // The region is only a hint to search; keep what is actually near
            .filter { $0.distance <= 15_000 }
            .sorted { $0.distance < $1.distance }
            await MainActor.run {
                guard category == c else { return }
                places = Array(found.prefix(6))
                searching = false
                if camera == .showAll { recenter() }
            }
        }
    }

    // MARK: Route

    private func select(_ p: Place) {
        selected = p
        routeShared = false
        calculateRoute()
    }

    private func calculateRoute() {
        guard let p = selected, let me else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: me))
        request.destination = p.item
        request.transportType = walking ? .walking : .automobile
        Task {
            let r = try? await MKDirections(request: request).calculate()
            await MainActor.run {
                route = r?.routes.first
                camera = .showAll
                recenter()
            }
        }
    }

    private func routePanel(_ p: Place) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(p.name).font(.scaled(size: 17, weight: .semibold))
            if let route {
                Text(String(format: lang.localized("sosmode.route.summary"),
                            Int((route.expectedTravelTime / 60).rounded(.up)), distanceText(route.distance)))
                    .font(.scaled(size: 14)).foregroundStyle(.secondary)
            }
            Picker("", selection: $walking) {
                Text(lang.localized("sosmode.route.walk")).tag(true)
                Text(lang.localized("sosmode.route.drive")).tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: walking) { _, _ in calculateRoute() }

            Button {
                p.item.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: walking ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving
                ])
            } label: {
                Label(lang.localized("sosmode.route.navigate"), systemImage: "location.north.line.fill")
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(blue))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    Task {
                        let ok = await coordinator.shareSOSRoute(name: p.name, coordinate: p.coordinate,
                                                                 mode: walking ? "walking" : "driving")
                        routeShared = ok
                    }
                } label: {
                    Label(lang.localized(routeShared ? "sosmode.route.shared" : "sosmode.route.share"),
                          systemImage: routeShared ? "checkmark.circle.fill" : "paperplane.fill")
                        .font(.scaled(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .disabled(routeShared)
                Button {
                    selected = nil; route = nil; routeShared = false
                } label: {
                    Text(lang.localized("sosmode.route.another"))
                        .font(.scaled(size: 14))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
            }
            if routeShared {
                Text(lang.localized("sosmode.route.sharedNote")).font(.scaled(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.4)))
    }
}

// MARK: - Text fallback

/// When the SOS can't reach the server (no data, or Google/Firebase blocked — e.g. a
/// mainland-China SIM or Wi-Fi), the person can text their guardians from their own
/// number. iOS never sends a text silently: Messages opens filled in, they tap Send.
enum SOSTextFallback {
    /// How long the SOS screen waits for the server before offering the text
    static let waitForServer: TimeInterval = 15

    static func shouldOffer(ended: Bool, reachedServer: Bool, deliveryFailed: Bool,
                            triggeredAt: Date?, now: Date) -> Bool {
        guard !ended, !reachedServer else { return false }
        if deliveryFailed { return true }
        guard let triggeredAt else { return false }
        return now.timeIntervalSince(triggeredAt) >= waitForServer
    }

    /// Non-empty numbers, each once (compared by digits), in the given order
    static func recipients(_ phones: [String?]) -> [String] {
        var seen = Set<String>()
        return phones.compactMap { phone in
            let trimmed = (phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = trimmed.filter(\.isNumber)
            guard !digits.isEmpty, seen.insert(digits).inserted else { return nil }
            return trimmed
        }
    }

    /// Apple Maps opens this anywhere (in mainland China too); dot decimals in every language
    static func mapsLink(_ c: CLLocationCoordinate2D) -> String {
        String(format: "https://maps.apple.com/?ll=%.5f,%.5f", c.latitude, c.longitude)
    }

    /// "Nov 8, 2:05 PM GMT+8": with the time zone, since the family may be in another one
    static func timeText(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("MMMdjmmz")
        return f.string(from: date)
    }

    /// "SOS from <name>. I need help. Location: <link> (<time of the fix>)"
    static func messageBody(name: String, coordinate: CLLocationCoordinate2D?, at time: Date,
                            locale: Locale, timeZone: TimeZone, localize: (String) -> String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = trimmedName.isEmpty ? localize("sos.sms.headNoName")
                                       : String(format: localize("sos.sms.head"), trimmedName)
        let when = timeText(time, locale: locale, timeZone: timeZone)
        let place: String
        if let c = coordinate, CLLocationCoordinate2DIsValid(c), !(c.latitude == 0 && c.longitude == 0) {
            place = String(format: localize("sos.sms.location"), mapsLink(c), when)
        } else {
            place = String(format: localize("sos.sms.noLocation"), when)
        }
        return head + " " + place
    }
}

struct SOSTextDraft: Identifiable {
    let id = UUID()
    let recipients: [String]
    let body: String
}

/// Messages, filled in; the person taps Send
struct MessageComposer: UIViewControllerRepresentable {
    let draft: SOSTextDraft
    let onFinish: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = draft.recipients
        vc.body = draft.body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Delegate { Delegate(onFinish: onFinish) }

    final class Delegate: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (MessageComposeResult) -> Void
        init(onFinish: @escaping (MessageComposeResult) -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            onFinish(result)
        }
    }
}
