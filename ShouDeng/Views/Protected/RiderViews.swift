import SwiftUI
import MapKit
import AVFoundation
import CoreImage.CIFilterBuiltins

// MARK: - Rider mode screens
//
// Home (shift, big SOS, hands-free tips, quick actions), Crew (map, members, invite
// QR, create / join), the alert a crew mate's SOS opens, bike-tampering report, and the
// rider part of the SOS screen (street to read out, "say this to 000", bleeding control,
// crew answers). Model and API: Models/Rider.swift, AppCoordinator+Rider.swift.

private enum RC {
    static let ink = Color.appInk
    static let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    static let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    static let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    static let card = Color.paper(251, 248, 241, elevated: true)
}

// MARK: - Home

struct RiderHomeView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var showShiftStart = false
    @State private var showHandsFree = false
    @State private var showInvite = false
    @State private var confirmEnd = false

    /// Every guardian lives in another country: nobody can be there in minutes
    private var needsLocalContact: Bool {
        guard let country = coordinator.currentUser?.countryCode, !country.isEmpty else { return false }
        return !coordinator.myGuardians.contains { $0.user.countryCode == country }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(coordinator.crewAlerts) { alert in crewAlertBanner(alert) }
                shiftCard
                VStack(spacing: 8) {
                    BigSOSButton()
                        .coachMark(CoachAnchor.sosButton)
                    Text(lang.localized("rider.sos.hint")).font(.scaled(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                handsFreeRow
                Text(lang.localized("rider.quick")).font(.scaled(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                quickAction("exclamationmark.shield", lang.localized("rider.bike.title"), lang.localized("rider.bike.short"), RC.lamp) {
                    coordinator.showBikeReport = true
                }
                if needsLocalContact {
                    quickAction("person.2.badge.plus", lang.localized("rider.local.title"), lang.localized("rider.local.detail"), RC.safe) {
                        showInvite = true
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemBackground))
        .task {
            // Crew and crew alerts stay current while the home is open
            while !Task.isCancelled {
                await coordinator.refreshCrew()
                await coordinator.refreshCrewAlerts()
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .sheet(isPresented: $showShiftStart) { ShiftStartSheet().environmentObject(coordinator) }
        .sheet(isPresented: $showHandsFree) { HandsFreeSheet() }
        .sheet(isPresented: $showInvite) { InviteGuardianSheet().environmentObject(coordinator) }
        .confirmationDialog(lang.localized("rider.shift.endConfirm"), isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(lang.localized("rider.shift.end")) { Task { await coordinator.endShift() } }
            Button(lang.localized("common.cancel"), role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.localized("rider.title")).font(.scaled(size: 26, weight: .bold)).foregroundStyle(RC.ink)
                Text([coordinator.currentUser?.displayName, coordinator.currentUser?.cityName]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.scaled(size: 14)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "bicycle").font(.system(size: 28)).foregroundStyle(RC.safe)
        }
    }

    private func crewAlertBanner(_ alert: CrewAlert) -> some View {
        Button { coordinator.pendingCrewAlertId = alert.sosEventId } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: lang.localized("rider.crewAlert.title"), alert.riderName))
                        .font(.scaled(size: 16, weight: .bold))
                    Text(RiderFormat.distance(alert.distanceM).map { String(format: lang.localized("rider.away"), $0) }
                         ?? lang.localized("rider.crewAlert.open"))
                        .font(.scaled(size: 13))
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(RC.alert))
        }
        .buttonStyle(.plain)
    }

    private var shiftCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let shift = coordinator.riderShift {
                HStack {
                    Circle().fill(RC.safe).frame(width: 10, height: 10)
                    Text(lang.localized("rider.shift.on")).font(.scaled(size: 17, weight: .semibold))
                    Text(shift.startedAt, style: .timer).font(.scaled(size: 17, weight: .semibold)).monospacedDigit()
                    Spacer()
                    Button(lang.localized("rider.shift.end")) { confirmEnd = true }
                        .font(.scaled(size: 14, weight: .semibold)).foregroundStyle(RC.alert)
                }
                Label(String(format: lang.localized("rider.shift.sharing"), coordinator.crew?.members.count ?? 0 > 0
                             ? max(0, (coordinator.crew?.members.count ?? 1) - 1) : 0),
                      systemImage: "location.fill")
                    .font(.scaled(size: 13)).foregroundStyle(.secondary)
                if let end = shift.plannedEnd {
                    Label(String(format: lang.localized("rider.shift.check"), end.formatted(date: .omitted, time: .shortened)),
                          systemImage: "clock.badge.checkmark")
                        .font(.scaled(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    Circle().fill(.gray).frame(width: 10, height: 10)
                    Text(lang.localized("rider.shift.off")).font(.scaled(size: 17, weight: .semibold))
                    Spacer()
                }
                Button { showShiftStart = true } label: {
                    Label(lang.localized("rider.shift.start"), systemImage: "play.fill")
                        .font(.scaled(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(RC.safe))
                }
                .buttonStyle(.plain)
                Text(lang.localized("rider.shift.why")).font(.scaled(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(RC.card))
    }

    private var handsFreeRow: some View {
        Button { showHandsFree = true } label: {
            HStack(spacing: 8) {
                chip("button.horizontal.top.press", lang.localized("rider.handsfree.action"))
                chip("antenna.radiowaves.left.and.right", lang.localized("rider.handsfree.handlebar"))
                chip("waveform", lang.localized("rider.handsfree.siri"))
            }
        }
        .buttonStyle(.plain)
    }

    private func chip(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(RC.ink)
            Text(label).font(.scaled(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))
    }

    private func quickAction(_ icon: String, _ title: String, _ detail: String, _ color: Color, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.scaled(size: 15, weight: .semibold)).foregroundStyle(RC.ink)
                    Text(detail).font(.scaled(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Start shift

struct ShiftStartSheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var hasEnd = true
    @State private var end = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(lang.localized("rider.shift.plannedEnd"), isOn: $hasEnd).tint(RC.safe)
                    if hasEnd {
                        DatePicker(lang.localized("rider.shift.endsAt"), selection: $end, in: Date()..., displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text(lang.localized(hasEnd ? "rider.shift.endFooter" : "rider.shift.noEndFooter"))
                }
                Section {
                    Label(lang.localized("rider.shift.shares"), systemImage: "location.fill")
                    Label(lang.localized("rider.shift.cardNote"), systemImage: "lock.rectangle.stack")
                }
                .font(.scaled(size: 14))
            }
            .navigationTitle(lang.localized("rider.shift.start"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(lang.localized("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.localized("rider.shift.go")) {
                        let plannedEnd = hasEnd ? (end < Date() ? end.addingTimeInterval(86400) : end) : nil
                        Task { await coordinator.startShift(plannedEnd: plannedEnd) }
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Hands-free SOS help

struct HandsFreeSheet: View {
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                tip("button.horizontal.top.press", "rider.handsfree.action", "rider.handsfree.action.how")
                tip("antenna.radiowaves.left.and.right", "rider.handsfree.handlebar", "rider.handsfree.handlebar.how")
                tip("waveform", "rider.handsfree.siri", "rider.handsfree.siri.how")
                tip("cross.case", "rider.handsfree.medicalId", "rider.handsfree.medicalId.how")
            }
            .navigationTitle(lang.localized("rider.handsfree.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(lang.localized("common.done")) { dismiss() } } }
        }
    }

    private func tip(_ icon: String, _ title: String, _ how: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(RC.safe).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(lang.localized(title)).font(.scaled(size: 15, weight: .semibold))
                Text(lang.localized(how)).font(.scaled(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Crew

struct CrewView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var newName = ""
    @State private var code = ""
    @State private var error: String?
    @State private var busy = false
    @State private var showInvite = false
    @State private var confirmLeave = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(lang.localized("rider.tab.crew")).font(.scaled(size: 26, weight: .bold)).foregroundStyle(RC.ink)
                ForEach(coordinator.crewAlerts) { alert in
                    Button { coordinator.pendingCrewAlertId = alert.sosEventId } label: {
                        Label(String(format: lang.localized("rider.crewAlert.title"), alert.riderName), systemImage: "exclamationmark.triangle.fill")
                            .font(.scaled(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(RC.alert))
                    }
                    .buttonStyle(.plain)
                }
                if let crew = coordinator.crew { crewContent(crew) } else { noCrew }
                if let error { Text(error).font(.scaled(size: 13)).foregroundStyle(RC.alert) }
            }
            .padding(16)
        }
        .background(Color(.systemBackground))
        .task {
            await coordinator.refreshCrew()
            await coordinator.refreshCrewAlerts()
        }
        .refreshable {
            await coordinator.refreshCrew()
            await coordinator.refreshCrewAlerts()
        }
        .sheet(isPresented: $showInvite) {
            if let crew = coordinator.crew { CrewInviteSheet(crew: crew) }
        }
        .confirmationDialog(lang.localized("rider.crew.leaveConfirm"), isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(lang.localized("rider.crew.leave"), role: .destructive) {
                Task { try? await coordinator.leaveCrew() }
            }
        }
    }

    // MARK: No crew yet

    private var noCrew: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lang.localized("rider.crew.why")).font(.scaled(size: 14)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            card {
                Text(lang.localized("rider.crew.create")).font(.scaled(size: 17, weight: .semibold))
                TextField(lang.localized("rider.crew.namePlaceholder"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                primary(lang.localized("rider.crew.createButton"), disabled: newName.trimmingCharacters(in: .whitespaces).isEmpty) {
                    await run { try await coordinator.createCrew(name: newName) }
                }
            }
            card {
                Text(lang.localized("rider.crew.join")).font(.scaled(size: 17, weight: .semibold))
                TextField(lang.localized("rider.crew.codePlaceholder"), text: $code)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                primary(lang.localized("rider.crew.joinButton"), disabled: code.trimmingCharacters(in: .whitespaces).count < 6) {
                    await run { try await coordinator.joinCrew(code: code) }
                }
            }
        }
    }

    // MARK: In a crew

    @ViewBuilder
    private func crewContent(_ crew: Crew) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(crew.name).font(.scaled(size: 18, weight: .semibold))
                Text(String(format: lang.localized("rider.crew.count"), crew.members.count, crew.members.filter(\.onShift).count))
                    .font(.scaled(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showInvite = true } label: {
                Label(lang.localized("rider.crew.invite"), systemImage: "qrcode")
                    .font(.scaled(size: 14, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(RC.safe)).foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        CrewMapView(crew: crew, myId: coordinator.currentUser?.id ?? "")
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        if !crew.cautions.isEmpty {
            Label(String(format: lang.localized("rider.crew.cautions"), crew.cautions.count), systemImage: "exclamationmark.triangle.fill")
                .font(.scaled(size: 13)).foregroundStyle(RC.lamp)
        }
        VStack(spacing: 0) {
            ForEach(crew.members) { member in
                HStack(spacing: 10) {
                    Text(member.initial).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Circle().fill(member.onShift ? RC.safe : .gray))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(member.id == coordinator.currentUser?.id ? String(format: lang.localized("rider.crew.you"), member.name) : member.name)
                            .font(.scaled(size: 15, weight: .semibold))
                        Text(lang.localized(member.onShift ? "rider.shift.on" : "rider.shift.off"))
                            .font(.scaled(size: 12)).foregroundStyle(member.onShift ? RC.safe : .secondary)
                    }
                    Spacer()
                    if let d = RiderFormat.distance(member.distanceM) {
                        Text(d).font(.scaled(size: 13)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
        if coordinator.isDemo {
            // Demo only: see what a crew mate's SOS looks like on your phone
            Button { coordinator.demoCrewSOS() } label: {
                Label(lang.localized("rider.crew.practice"), systemImage: "play.circle")
                    .font(.scaled(size: 15, weight: .semibold)).foregroundStyle(RC.alert)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(RC.alert))
            }
            .buttonStyle(.plain)
        }
        Button(lang.localized("rider.crew.leave"), role: .destructive) { confirmLeave = true }
            .font(.scaled(size: 14))
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    // MARK: Helpers

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(RC.card))
    }

    private func primary(_ title: String, disabled: Bool, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Group {
                if busy { ProgressView().tint(.white) } else { Text(title) }
            }
            .font(.scaled(size: 15, weight: .semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(disabled ? Color.gray.opacity(0.4) : RC.safe))
        }
        .buttonStyle(.plain)
        .disabled(disabled || busy)
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        do { try await work() } catch {
            self.error = (error as? APIError).map { e -> String in
                switch e {
                case .notFound: return lang.localized("rider.crew.badCode")
                case .conflict: return lang.localized("rider.crew.conflict")
                default: return lang.localized("rider.crew.failed")
                }
            } ?? lang.localized("rider.crew.failed")
        }
        busy = false
    }
}

/// Crew mates on shift, caution spots, me.
struct CrewMapView: View {
    let crew: Crew
    let myId: String
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(crew.members) { m in
                if let c = m.coordinate {
                    Annotation(m.name, coordinate: c) {
                        Text(m.initial).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(m.id == myId ? Color.blue : RC.safe))
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            ForEach(crew.cautions) { c in
                Annotation(c.note, coordinate: c.coordinate) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 18))
                        .foregroundStyle(RC.lamp).padding(4).background(Circle().fill(.white))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

struct CrewInviteSheet: View {
    let crew: Crew
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text(lang.localized("rider.crew.inviteHow")).font(.scaled(size: 15)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let qr = Self.qr(crew.inviteURL.absoluteString) {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(width: 220, height: 220)
                }
                Text(crew.inviteCode).font(.system(size: 34, weight: .bold, design: .monospaced)).kerning(4)
                ShareLink(item: String(format: lang.localized("rider.crew.shareText"), crew.name, crew.inviteCode, crew.inviteURL.absoluteString)) {
                    Label(lang.localized("rider.crew.share"), systemImage: "square.and.arrow.up")
                        .font(.scaled(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(RC.safe))
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle(crew.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(lang.localized("common.done")) { dismiss() } } }
        }
    }

    static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Opened from a crew QR code / link: confirm joining.
struct CrewJoinSheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State var initialCode: String
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.3.fill").font(.system(size: 40)).foregroundStyle(RC.safe)
                Text(lang.localized("rider.crew.joinTitle")).font(.scaled(size: 20, weight: .bold))
                Text(initialCode).font(.system(size: 30, weight: .bold, design: .monospaced)).kerning(4)
                Text(lang.localized("rider.crew.joinNote")).font(.scaled(size: 14)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task {
                        do {
                            try await coordinator.joinCrew(code: initialCode)
                            dismiss()
                        } catch { self.error = lang.localized("rider.crew.badCode") }
                    }
                } label: {
                    Text(lang.localized("rider.crew.joinButton")).font(.scaled(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(RC.safe))
                }
                .buttonStyle(.plain)
                if let error { Text(error).foregroundStyle(RC.alert).font(.scaled(size: 13)) }
                Spacer()
            }
            .padding(24)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(lang.localized("common.cancel")) { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - A crew mate's SOS

struct CrewAlertView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    let sosEventId: String
    @State private var route: MKRoute?
    @State private var camera: MapCameraPosition = .automatic
    @State private var sending = false

    private var alert: CrewAlert? { coordinator.crewAlerts.first { $0.sosEventId == sosEventId } }
    private var me: CLLocationCoordinate2D? { coordinator.locationManager.bestAvailableLocation?.coordinate }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let alert { content(alert) } else { ended }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(lang.localized("common.close")) { dismiss() } } }
        }
        .task {
            // Answers and the rider's position keep coming in
            while !Task.isCancelled {
                await coordinator.refreshCrewAlerts()
                if route == nil, let target = alert?.coordinate { await loadRoute(to: target) }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private var ended: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 44)).foregroundStyle(RC.safe)
            Text(lang.localized("rider.crewAlert.ended")).font(.scaled(size: 18, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    @ViewBuilder
    private func content(_ alert: CrewAlert) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: lang.localized("rider.crewAlert.title"), alert.riderName))
                .font(.scaled(size: 26, weight: .bold)).foregroundStyle(RC.alert)
            if let d = RiderFormat.distance(alert.distanceM) {
                Label(route.map { String(format: lang.localized("rider.crewAlert.walk"), d, max(1, Int($0.expectedTravelTime / 60))) }
                      ?? String(format: lang.localized("rider.away"), d), systemImage: "figure.walk")
                    .font(.scaled(size: 15))
            }
            Map(position: $camera) {
                if let c = alert.coordinate {
                    Annotation(alert.riderName, coordinate: c) {
                        Circle().fill(RC.alert).frame(width: 20, height: 20).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                if let route { MapPolyline(route.polyline).stroke(RC.safe, lineWidth: 5) }
                if !coordinator.isDemo { UserAnnotation() }
                if coordinator.isDemo, let me {
                    Annotation("", coordinate: me) { Circle().fill(.blue).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2)) }
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Button {
                if let url = URL(string: "tel:\(coordinator.localEmergencyNumber)") { ExternalURL.open(url) }
            } label: {
                Label(String(format: lang.localized("rider.crewAlert.callFirst"), coordinator.localEmergencyNumber), systemImage: "phone.fill")
                    .font(.scaled(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 14).fill(RC.alert))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                answer(alert, going: true)
                answer(alert, going: false)
            }
            if let target = alert.coordinate {
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: target))
                    item.name = alert.riderName
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                } label: {
                    Label(lang.localized("sosmode.route.navigate"), systemImage: "location.north.line.fill")
                        .font(.scaled(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            Label(lang.localized("rider.crewAlert.safety"), systemImage: "info.circle")
                .font(.scaled(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !alert.responses.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lang.localized("rider.crew.answers")).font(.scaled(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    ForEach(alert.responses) { r in
                        Text("\(r.name) · \(lang.localized(r.isGoing ? "rider.answer.going" : "rider.answer.cant"))")
                            .font(.scaled(size: 14)).foregroundStyle(r.isGoing ? RC.safe : .secondary)
                    }
                }
            }
        }
        .padding(16)
    }

    private func answer(_ alert: CrewAlert, going: Bool) -> some View {
        let chosen = alert.myResponse == (going ? "going" : "cant_help")
        let color = going ? RC.safe : Color.gray
        return Button {
            sending = true
            Task {
                try? await coordinator.respondToCrewAlert(alert, going: going)
                sending = false
            }
        } label: {
            Label(lang.localized(going ? "rider.answer.goingButton" : "rider.answer.cantButton"),
                  systemImage: chosen ? "checkmark.circle.fill" : (going ? "figure.run" : "xmark"))
                .font(.scaled(size: 16, weight: .semibold))
                .foregroundStyle(chosen ? .white : color)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(chosen ? color : .clear))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(color, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(sending)
    }

    private func loadRoute(to target: CLLocationCoordinate2D) async {
        guard let me else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: me))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: target))
        request.transportType = .walking
        route = try? await MKDirections(request: request).calculate().routes.first
    }
}

// MARK: - Bike tampered with

struct BikeReportView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var logged: Date?
    @State private var failed = false

    private var policeNumber: String? {
        RiderFormat.policeAssistanceNumber(country: coordinator.currentUser?.countryCode ?? coordinator.emergencyCountryCode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hand.raised.slash.fill").font(.system(size: 22)).foregroundStyle(RC.alert)
                        Text(lang.localized("rider.bike.dontConfront"))
                            .font(.scaled(size: 16, weight: .semibold)).foregroundStyle(RC.alert)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(RC.alert.opacity(0.08)))

                    row("mappin.and.ellipse", "rider.bike.log", logged == nil ? "rider.bike.logDetail" : "rider.bike.logged") {
                        Task {
                            coordinator.addTimelineEntry(type: .arrivalReport, description: lang.localized("rider.bike.timeline"))
                            do {
                                if coordinator.crew != nil { try await coordinator.addCaution(note: lang.localized("rider.bike.caution")) }
                                logged = Date()
                            } catch { failed = true; logged = Date() }
                        }
                    }
                    row("camera.fill", "rider.bike.photo", "rider.bike.photoDetail", action: nil)
                    if let number = policeNumber {
                        row("phone.fill", String(format: lang.localized("rider.bike.police"), number), "rider.bike.policeDetail", rawTitle: true) {
                            if let url = URL(string: "tel:\(number)") { ExternalURL.open(url) }
                        }
                    }
                    row("exclamationmark.triangle.fill", String(format: lang.localized("rider.bike.threat"), coordinator.localEmergencyNumber),
                        "rider.bike.threatDetail", rawTitle: true) {
                        if let url = URL(string: "tel:\(coordinator.localEmergencyNumber)") { ExternalURL.open(url) }
                    }
                    if failed {
                        Text(lang.localized("rider.bike.crewFailed")).font(.scaled(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .navigationTitle(lang.localized("rider.bike.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(lang.localized("common.done")) { dismiss() } } }
        }
    }

    private func row(_ icon: String, _ title: String, _ detail: String, rawTitle: Bool = false, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(RC.ink).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rawTitle ? title : lang.localized(title)).font(.scaled(size: 16, weight: .semibold)).foregroundStyle(RC.ink)
                    Text(lang.localized(detail)).font(.scaled(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if action != nil { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - Rider part of the SOS screen

/// Street to read out, "say this to 000" (read aloud), bleeding control for whoever
/// is helping, crew answers. Shown in SOSActiveView when Rider mode is on.
struct RiderSOSPanel: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var speaking = false
    @State private var synth = AVSpeechSynthesizer()

    private var address: String? { coordinator.riderSOSAddress }

    /// The emergency operator's language, from the country (default English)
    private var operatorLanguage: (code: String, voice: String) {
        switch coordinator.emergencyCountryCode.uppercased() {
        case "CN", "TW", "HK": return ("zh", "zh-CN")
        case "FR": return ("fr", "fr-FR")
        case "JP": return ("ja", "ja-JP")
        case "AU": return ("en", "en-AU")
        case "GB", "IE": return ("en", "en-GB")
        default: return ("en", "en-US")
        }
    }

    private var phrase: String {
        let place = address ?? "—"
        let me = lang.current.rawValue.hasPrefix(operatorLanguage.code) ? nil : lang.localized("rider.speak.myLanguage")
        switch operatorLanguage.code {
        case "zh": return "需要救护车。有人重伤。我们在\(place)。"
        case "fr": return "Une ambulance s'il vous plaît. Quelqu'un est gravement blessé. Nous sommes à \(place)." + (me.map { " Je parle \($0)." } ?? "")
        case "ja": return "救急車をお願いします。重傷の人がいます。場所は\(place)です。"
        default: return "Ambulance please. Someone is badly hurt. We are at \(place)." + (me.map { " I speak \($0). Interpreter, please." } ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang.localized("rider.sos.youAreAt")).font(.scaled(size: 11, weight: .bold)).foregroundStyle(.secondary)
                Text(address ?? lang.localized("rider.sos.finding")).font(.scaled(size: 22, weight: .bold)).foregroundStyle(RC.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(RC.card))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(format: lang.localized("rider.sos.sayThis"), coordinator.localEmergencyNumber))
                        .font(.scaled(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: toggleSpeech) {
                        Label(lang.localized(speaking ? "rider.sos.stop" : "rider.sos.speak"),
                              systemImage: speaking ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.scaled(size: 13, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.inkSolid)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                Text("\"\(phrase)\"").font(.scaled(size: 17, weight: .medium)).foregroundStyle(RC.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator)))

            VStack(alignment: .leading, spacing: 8) {
                Text(lang.localized("rider.sos.helping")).font(.scaled(size: 11, weight: .bold)).foregroundStyle(RC.alert)
                step("1", "hand.raised.fill", lang.localized("rider.sos.step1"))
                step("2", "phone.fill", String(format: lang.localized("rider.sos.step2"), coordinator.localEmergencyNumber))
                step("3", "heart.fill", String(format: lang.localized("rider.sos.step3"), coordinator.localEmergencyNumber))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(RC.alert.opacity(0.08)))

            if let status = coordinator.ownSOSStatus, (status.crewNotified ?? 0) > 0 || !(status.crewResponses ?? []).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: lang.localized("rider.sos.crewAlerted"), status.crewNotified ?? 0))
                        .font(.scaled(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    ForEach(status.crewResponses ?? []) { r in
                        HStack {
                            Text(r.name).font(.scaled(size: 15, weight: .semibold))
                            if let d = RiderFormat.distance(r.distanceM) { Text(d).font(.scaled(size: 13)).foregroundStyle(.secondary) }
                            Spacer()
                            Text(lang.localized(r.isGoing ? "rider.answer.going" : "rider.answer.cant"))
                                .font(.scaled(size: 13, weight: .medium)).foregroundStyle(r.isGoing ? RC.safe : .secondary)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            }
        }
        .onAppear { if coordinator.riderSOSAddress == nil { coordinator.updateRiderCardForSOS() } }
        .onDisappear { synth.stopSpeaking(at: .immediate) }
    }

    private func toggleSpeech() {
        if speaking {
            synth.stopSpeaking(at: .immediate)
            speaking = false
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: operatorLanguage.voice)
        utterance.rate = 0.45
        synth.speak(utterance)
        speaking = true
    }

    private func step(_ n: String, _ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Circle().fill(RC.alert))
            Image(systemName: icon).foregroundStyle(RC.alert).frame(width: 20)
            Text(text).font(.scaled(size: 15)).foregroundStyle(RC.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
