import SwiftUI
import MapKit

// MARK: - Screen B2: Alert Response
//
// Shows real SOS event data for the guardian to respond to.
// Uses coordinator.activeSOSEvent and the associated protected person's data.

struct GuardianAlertResponseView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.dismiss) var dismiss
    let personId: String

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var showClaimMaterialsPrompt = false
    @State private var showClaimMaterials = false

    private var person: ProtectedPerson? {
        coordinator.protectedPersons.first { $0.id == personId }
    }

    private var sosEvent: SOSEvent? {
        coordinator.activeSOSEvent
    }

    private var personName: String {
        person?.user.displayName ?? langManager.localized("guardian.alert.protected.person")
    }

    private var personCity: String {
        person?.user.cityName ?? ""
    }

    var body: some View {
        NavigationStack {
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

                    // Map with real or last-known location
                    mapSection

                    // Action buttons
                    HStack(spacing: 8) {
                        Button {
                            if let phone = person?.user.phone,
                               let url = URL(string: "tel://\(phone)") {
                                UIApplication.shared.open(url)
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
                            coordinator.cancelSOS()
                            showClaimMaterialsPrompt = true
                        } label: {
                            Text(langManager.localized("guardian.alert.i.got.it"))
                                .font(.scaled(size: 13.5, weight: .medium))
                                .foregroundStyle(ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(ink.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Escalation chain
                    escalationChain

                    // Scene info
                    sceneInfoPanel
                }
                .padding(.horizontal, 16)
            }
            .background(Color(.systemBackground))
            .navigationTitle(langManager.localized("guardian.alert.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(langManager.localized("guardian.alert.title"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(alert)
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
    }

    // MARK: - Header Subtitle

    private var headerSubtitle: String {
        var parts: [String] = []
        // Location description
        if let loc = sosEvent?.location, let addr = loc.address, !addr.isEmpty {
            parts.append(addr)
        } else if !personCity.isEmpty {
            parts.append(personCity)
        }
        // Elapsed time
        if let sos = sosEvent {
            let elapsed = Int(Date().timeIntervalSince(sos.triggeredAt))
            let mins = elapsed / 60
            let secs = elapsed % 60
            parts.append(String(format: langManager.localized("guardian.alert.elapsed"), mins, secs))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Group {
            if let loc = sosEvent?.location {
                let coord = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                ))) {
                    UserAnnotation()
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
                .overlay(alignment: .bottomLeading) {
                    if let accuracy = sosEvent?.location?.accuracy {
                        Text(String(format: langManager.localized("guardian.alert.accuracy"), Int(accuracy)))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ink.opacity(0.7))
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }
            } else if let loc = person?.lastKnownLocation {
                let coord = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    UserAnnotation()
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
                .overlay(alignment: .bottomLeading) {
                    Text(langManager.localized("guardian.alert.last.known"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(6)
                }
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

    // MARK: - Escalation Chain

    private var escalationChain: some View {
        let state = sosEvent?.escalationState ?? .initiated

        let hop1Done: Bool = [.hop1_acknowledged, .hop2_allNotified, .hop3_voiceCalling, .hop3_exhausted, .frozen, .resolved].contains(state)
        let hop1Started: Bool = state == .hop1_notified || hop1Done
        let hop2Done: Bool = [.hop3_voiceCalling, .hop3_exhausted, .frozen, .resolved].contains(state)
        let hop2Started: Bool = state == .hop2_allNotified || hop2Done
        let hop3Started: Bool = [.hop3_voiceCalling, .hop3_exhausted].contains(state)

        let step1State: StepState = hop1Done ? .done : (hop1Started ? .live : .live)
        let step2State: StepState = hop2Done ? .done : (hop2Started ? .live : .waiting)
        let step3State: StepState = hop3Started ? .live : .waiting

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
                    detail: sosEvent.map { String(format: langManager.localized("guardian.alert.triggered.at"), formatTime($0.triggeredAt)) } ?? langManager.localized("guardian.alert.notifying"),
                    state: step1State)
            stepRow(number: "2", title: langManager.localized("guardian.alert.step2.title"),
                    detail: langManager.localized("guardian.alert.step2.detail"),
                    state: step2State)
            stepRow(number: "3", title: langManager.localized("guardian.alert.step3.title"),
                    detail: langManager.localized("guardian.alert.step3.detail"),
                    state: step3State)
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
            if let battery = person?.batteryLevel ?? sosEvent?.batteryLevel {
                let pct = Int(battery * 100)
                infoRow(langManager.localized("guardian.alert.battery"), value: "\(pct)%\(pct < 20 ? " \(langManager.localized("guardian.alert.declining"))" : "")", isAlert: pct < 20)
            } else {
                infoRow(langManager.localized("guardian.alert.battery"), value: langManager.localized("guardian.alert.unknown"), isAlert: false)
            }
            if let lastActivity = person?.lastPhoneActivity {
                let minutes = Int(Date().timeIntervalSince(lastActivity) / 60)
                infoRow(langManager.localized("guardian.alert.last.interaction"), value: String(format: langManager.localized("guardian.alert.minutes.ago"), minutes), isAlert: minutes > 10)
            }
            if let sos = sosEvent {
                infoRow(langManager.localized("guardian.alert.trigger.method"), value: triggerMethodText(sos.triggerMethod), isAlert: false)
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
