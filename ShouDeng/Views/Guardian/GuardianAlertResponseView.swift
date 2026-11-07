import SwiftUI
import MapKit
import Combine

// MARK: - Screen B2: Alert Response
//
// Shows the protected person's live SOS (GET /v1/guardian/sos/active): location,
// battery, how far the escalation got, who is handling it, elapsed time.
//   "I've got it" → POST /v1/sos/acknowledge (stops the automatic calls, tells the others)
//   "She's safe"  → POST /v1/sos/resolve (closes the SOS)

struct GuardianAlertResponseView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.dismiss) var dismiss
    let personId: String

    private let ink = Color.appInk
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var showClaimMaterialsPrompt = false
    @State private var showClaimMaterials = false
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var tick = Date()
    /// Follows the person while the SOS moves (re-centred when a new position arrives)
    @State private var sosCamera: MapCameraPosition = .automatic
    nonisolated(unsafe) private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var person: ProtectedPerson? {
        coordinator.protectedPersons.first { $0.id == personId }
    }

    private var sos: SOSStatus? {
        coordinator.guardianSOS[personId] ?? person?.activeSOS
    }

    private var iAcknowledged: Bool {
        guard let by = sos?.acknowledgedBy else { return false }
        return by == coordinator.authManager.currentUserId || by == coordinator.currentUser?.id
    }

    private var personName: String {
        person?.user.displayName ?? sos?.personName ?? langManager.localized("guardian.alert.protected.person")
    }

    private var personCity: String {
        person?.user.cityName ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header — real data
                VStack(spacing: 2) {
                    Text(String(format: langManager.localized("guardian.alert.seeking.help"), personName))
                        .font(.scaled(size: 20, weight: .bold))
                        .foregroundStyle(alert)
                    Text(headerSubtitle)
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                if sos == nil {
                    Text(langManager.localized("guardian.alert.noActiveSOS"))
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                }

                if let sos, let by = sos.acknowledgedByName ?? sos.acknowledgedBy {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.checkmark")
                        Text(iAcknowledged
                             ? langManager.localized("guardian.alert.youAreHandling")
                             : String(format: langManager.localized("sos.status.acknowledged"), by))
                            .font(.scaled(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(safe))
                }

                // Map with SOS or last-known location
                mapSection

                // Action buttons
                HStack(spacing: 8) {
                    Button {
                        if let phone = person?.user.phone,
                           let url = URL(string: "tel://\(phone)") {
                            ExternalURL.open(url)
                        }
                    } label: {
                        Text(langManager.localized("guardian.alert.call.now"))
                            .font(.scaled(size: 13.5, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(alert)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        acknowledge()
                    } label: {
                        Text(langManager.localized(sos?.acknowledgedBy == nil ? "guardian.alert.i.got.it" : "guardian.alert.acknowledged"))
                            .font(.scaled(size: 13.5, weight: .medium))
                            .foregroundStyle(ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(ink.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(sos == nil || sos?.acknowledgedBy != nil || isWorking)
                    .coachMark(CoachAnchor.acknowledge)
                    .accessibilityHint(langManager.localized("guardian.alert.ackHint"))
                }

                Button {
                    resolveSafe()
                } label: {
                    Label(String(format: langManager.localized("guardian.alert.markSafe"), personName), systemImage: "checkmark.shield")
                        .font(.scaled(size: 13.5, weight: .medium))
                        .foregroundStyle(safe)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(safe.opacity(0.4)))
                }
                .disabled(sos == nil || isWorking)

                if let errorText {
                    Text(errorText).font(.scaled(size: 12)).foregroundStyle(alert)
                }

                // Escalation chain
                escalationChain

                // Scene info
                sceneInfoPanel

                // For the police: everything about the last 24 h, ready to hand over
                IncidentReportButton(personId: person?.user.id ?? personId, compact: true)
                    .environmentObject(coordinator)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle(langManager.localized("guardian.alert.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await coordinator.fetchGuardianSOS(personId: personId) }
        .onReceive(timer) { now in
            tick = now
            if Int(now.timeIntervalSince1970) % 5 == 0 {
                Task { await coordinator.fetchGuardianSOS(personId: personId) }
            }
        }
        .alert(langManager.localized("guardian.alert.claim.prompt"), isPresented: $showClaimMaterialsPrompt) {
            Button(langManager.localized("guardian.alert.claim.organize")) { showClaimMaterials = true }
            Button(langManager.localized("guardian.alert.claim.no"), role: .cancel) { dismiss() }
        } message: {
            Text(langManager.localized("guardian.alert.claim.description"))
        }
        .sheet(isPresented: $showClaimMaterials, onDismiss: { dismiss() }) {
            ClaimMaterialsView().environmentObject(coordinator)
        }
    }

    // MARK: - Actions

    private func acknowledge() {
        guard let id = sos?.sosEventId else { return }
        isWorking = true
        errorText = nil
        Task {
            do {
                try await coordinator.acknowledgeSOS(sosEventId: id)
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
            await MainActor.run { isWorking = false }
        }
    }

    private func resolveSafe() {
        guard let id = sos?.sosEventId else { return }
        isWorking = true
        errorText = nil
        Task {
            do {
                try await coordinator.resolveSOSAsGuardian(sosEventId: id, personId: personId)
                await MainActor.run { showClaimMaterialsPrompt = true }
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
            await MainActor.run { isWorking = false }
        }
    }

    // MARK: - Header Subtitle

    private var headerSubtitle: String {
        var parts: [String] = []
        if !personCity.isEmpty {
            parts.append(personCity)
        }
        // Elapsed time (ticks every second)
        if let triggered = sos?.triggeredAt {
            let elapsed = max(0, Int(tick.timeIntervalSince(triggered)))
            let mins = elapsed / 60
            let secs = elapsed % 60
            parts.append(String(format: langManager.localized("guardian.alert.elapsed"), mins, secs))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Group {
            if let lat = sos?.latitude, let lng = sos?.longitude {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                let trail = (sos?.trail ?? []).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                Map(position: $sosCamera) {
                    // Explore Mode: MapKit draws the device's real position — hide it in the demo.
                    if !ExploreMode.isActive { UserAnnotation() }
                    if trail.count > 1 {
                        MapPolyline(coordinates: trail + [coord])
                            .stroke(alert.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                    if let route = sos?.route {
                        Marker(route.name, systemImage: routeIcon(route.mode),
                               coordinate: CLLocationCoordinate2D(latitude: route.latitude, longitude: route.longitude))
                            .tint(safe)
                    }
                    Annotation(personName, coordinate: coord) {
                        ZStack {
                            Circle().fill(alert.opacity(0.3)).frame(width: 32, height: 32)
                            Circle().fill(alert).frame(width: 16, height: 16)
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onAppear { recenter(on: coord) }
                .onChange(of: lat) { recenter(on: CLLocationCoordinate2D(latitude: lat, longitude: lng)) }
                .onChange(of: lng) { recenter(on: CLLocationCoordinate2D(latitude: lat, longitude: lng)) }
                .onChange(of: sos?.route?.name) { recenter(on: coord) }
                // Top-leading: the Apple Maps logo and Legal link sit bottom-leading and must stay visible.
                .overlay(alignment: .topLeading) {
                    Text(langManager.localized("guardian.alert.sosLocation"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(alert.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(6)
                }
                sosLocationNotes
                OpenInAppleMapsButton(coordinate: coord, name: personName)
            } else if let loc = person?.lastKnownLocation {
                let coord = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    // Explore Mode: MapKit draws the device's real position — hide it in the demo.
                    if !ExploreMode.isActive { UserAnnotation() }
                    Annotation(personName, coordinate: coord) {
                        ZStack {
                            Circle().fill(alert.opacity(0.3)).frame(width: 32, height: 32)
                            Circle().fill(alert).frame(width: 16, height: 16)
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    Text(langManager.localized("guardian.alert.last.known"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(6)
                }
                OpenInAppleMapsButton(coordinate: coord, name: personName)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .frame(height: 180)
                    VStack(spacing: 4) {
                        Image(systemName: "mappin.slash")
                            .font(.scaled(size: 28))
                            .foregroundStyle(alert)
                        Text(langManager.localized("guardian.alert.no.location"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// With a shared destination, fit both; otherwise stay close on the person.
    private func recenter(on coord: CLLocationCoordinate2D) {
        if sos?.route != nil {
            sosCamera = .automatic
        } else {
            sosCamera = .region(MKCoordinateRegion(center: coord,
                                                   span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
        }
    }

    private func routeIcon(_ mode: String) -> String {
        switch mode {
        case "driving": return "car.fill"
        case "transit": return "tram.fill"
        default: return "figure.walk"
        }
    }

    /// "Heading to …" and "Location updated 14:32" under the map
    @ViewBuilder
    private var sosLocationNotes: some View {
        if let route = sos?.route {
            HStack(spacing: 8) {
                Image(systemName: routeIcon(route.mode))
                Text(String(format: langManager.localized("guardian.alert.headingTo"), route.name))
                    .font(.scaled(size: 14, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(safe)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(safe.opacity(0.1)))
        }
        if let updated = sos?.locationUpdatedAt ?? sos?.triggeredAt {
            Text(String(format: langManager.localized("guardian.alert.locationUpdated"), formatTime(updated)))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Escalation Chain

    private var escalationChain: some View {
        let notified = sos?.guardiansNotified ?? 0
        let acknowledged = sos?.acknowledgedBy != nil
        let calls = sos?.callsPlaced ?? 0

        let step1State: StepState = notified > 0 ? .done : .live
        let step2State: StepState = sos?.shareLinkSent == true ? .done : (acknowledged ? .waiting : .live)
        let step3State: StepState = acknowledged ? .done : (calls > 0 ? .live : .waiting)

        return VStack(spacing: 0) {
            HStack {
                Text(langManager.localized("guardian.alert.escalation"))
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(alert)
                Spacer()
            }
            .padding(12)
            .background(alert.opacity(0.09))

            stepRow(number: "1", title: langManager.localized("guardian.alert.step1.title"),
                    detail: notified > 0
                        ? String(format: langManager.localized("sos.status.guardiansNotified"), notified)
                        : langManager.localized("guardian.alert.notifying"),
                    state: step1State)
            if DisclaimerCopy.EscalationChannels.phoneEnabled {
                stepRow(number: "2", title: langManager.localized("sos.status.linkTitle"),
                        detail: langManager.localized(sos?.shareLinkSent == true ? "sos.status.linkSent" : "sos.status.linkNext"),
                        state: step2State)
                stepRow(number: "3", title: langManager.localized("sos.status.callsTitle"),
                        detail: acknowledged
                            ? langManager.localized("sos.status.callsStopped")
                            : (calls > 0 ? String(format: langManager.localized("sos.status.calling"), calls) : langManager.localized("sos.status.callsNext")),
                        state: step3State)
            } else {
                // Texts and calls are off (push only): show only what really happens
                let everyoneAlerted = acknowledged || tick.timeIntervalSince(sos?.triggeredAt ?? tick) >= 30
                stepRow(number: "2", title: langManager.localized("sos.status.allTitle"),
                        detail: langManager.localized(everyoneAlerted ? "sos.status.allSent" : "sos.status.allNext"),
                        state: everyoneAlerted ? .done : .live)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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

    // MARK: - Scene Info

    private var sceneInfoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("guardian.alert.scene.info"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            if let battery = sos?.batteryLevel ?? person?.batteryLevel {
                let pct = Int(battery * 100)
                infoRow(langManager.localized("guardian.alert.battery"), value: "\(pct)%\(pct < 20 ? " \(langManager.localized("guardian.alert.declining"))" : "")", isAlert: pct < 20)
            } else {
                infoRow(langManager.localized("guardian.alert.battery"), value: langManager.localized("guardian.alert.unknown"), isAlert: false)
            }
            if let lastActivity = person?.lastPhoneActivity {
                let minutes = Int(Date().timeIntervalSince(lastActivity) / 60)
                infoRow(langManager.localized("guardian.alert.last.interaction"), value: String(format: langManager.localized("guardian.alert.minutes.ago"), minutes), isAlert: minutes > 10)
            }
            if let raw = sos?.triggerMethod, let method = SOSTriggerMethod(rawValue: raw) {
                infoRow(langManager.localized("guardian.alert.trigger.method"), value: triggerMethodText(method), isAlert: false)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func triggerMethodText(_ method: SOSTriggerMethod) -> String {
        switch method {
        case .longPress: return langManager.localized("guardian.alert.trigger.longpress")
        case .watchQuickAction: return "Apple Watch"
        case .bluetoothButton: return langManager.localized("guardian.alert.trigger.bluetooth")
        case .duressPassword: return langManager.localized("guardian.alert.trigger.duress")
        case .fallDetection: return langManager.localized("guardian.alert.trigger.fall")
        case .voiceWakeWord: return langManager.localized("guardian.alert.trigger.voice.wake")
        case .audioDistress: return langManager.localized("guardian.alert.trigger.audio")
        case .voiceCommand: return langManager.localized("guardian.alert.trigger.voice.command")
        case .widgetTap: return langManager.localized("guardian.alert.trigger.widget")
        case .deadManSwitch: return langManager.localized("guardian.alert.trigger.deadman")
        }
    }

    private func infoRow(_ label: String, value: String, isAlert: Bool) -> some View {
        HStack {
            Text(label).font(.scaled(size: 13))
            Spacer()
            Text(value)
                .font(.scaled(size: 12))
                .foregroundStyle(isAlert ? alert : .secondary)
        }
        .padding(.vertical, 2)
    }
}
