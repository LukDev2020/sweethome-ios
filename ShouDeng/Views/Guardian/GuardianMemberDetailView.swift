import SwiftUI
import MapKit

// MARK: - Screen B3: Member Detail
//
// Shows real data for a specific protected person.
// Guardian navigates here by tapping a person card on the home screen.

struct GuardianMemberDetailView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    let personId: String

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    private var person: ProtectedPerson? {
        coordinator.protectedPersons.first { $0.id == personId }
    }

    var body: some View {
        ScrollView {
            if let person {
                VStack(spacing: 12) {
                    // Header
                    VStack(spacing: 2) {
                        Text(person.user.displayName)
                            .font(.scaled(size: 20, weight: .bold))
                        Text(headerSubtitle(person))
                            .font(.scaled(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Map with real location
                    locationMapSection(person)

                    // Status panel
                    statusPanel(person)

                    // Timeline
                    timelineSection

                    // Emergency contacts
                    NavigationLink {
                        EmergencyContactsView(
                            personName: person.user.displayName,
                            countryCode: person.user.countryCode.isEmpty ? "CN" : person.user.countryCode
                        )
                        .environmentObject(coordinator)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.arrow.up.right.fill")
                                .font(.scaled(size: 14))
                                .foregroundStyle(.red)
                            Text(langManager.localized("guardian.member.emergency.phone"))
                                .font(.scaled(size: 13, weight: .medium))
                                .foregroundStyle(ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.scaled(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.15), lineWidth: 1)
                        )
                    }

                    // Action buttons
                    HStack(spacing: 8) {
                        actionButton(langManager.localized("guardian.member.send.message"), icon: "message.fill") {
                            if let phone = person.user.phone,
                               let url = URL(string: "sms:\(phone)") {
                                UIApplication.shared.open(url)
                            }
                        }
                        actionButton(langManager.localized("guardian.member.call"), icon: "phone.fill") {
                            if let phone = person.user.phone,
                               let url = URL(string: "tel://\(phone)") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            } else {
                ContentUnavailableView(
                    langManager.localized("guardian.member.not.found"),
                    systemImage: "person.slash",
                    description: Text(langManager.localized("guardian.member.may.removed"))
                )
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(langManager.localized("guardian.member.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(langManager.localized("guardian.member.on.duty"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(safe)
            }
        }
    }

    // MARK: - Header

    private func headerSubtitle(_ person: ProtectedPerson) -> String {
        var parts: [String] = []
        if !person.user.cityName.isEmpty {
            parts.append(person.user.cityName)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = person.user.timeZone
        parts.append(String(format: langManager.localized("guardian.member.local.time"), formatter.string(from: Date())))
        parts.append(String(format: langManager.localized("guardian.member.layers"), person.protectionLayers))
        return parts.joined(separator: " · ")
    }

    // MARK: - Location Map

    private func locationMapSection(_ person: ProtectedPerson) -> some View {
        Group {
            if let loc = person.lastKnownLocation {
                let coord = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    UserAnnotation()
                    Annotation(person.user.displayName, coordinate: coord) {
                        ZStack {
                            Circle().fill(lamp.opacity(0.25)).frame(width: 28, height: 28)
                            Circle().fill(lamp).frame(width: 14, height: 14)
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    if let addr = loc.address, !addr.isEmpty {
                        Text(addr)
                            .font(.scaled(size: 12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ink.opacity(0.7))
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .frame(height: 160)
                    VStack(spacing: 4) {
                        Image(systemName: "mappin.slash")
                            .font(.scaled(size: 28))
                            .foregroundStyle(.secondary)
                        Text(langManager.localized("guardian.member.no.location"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Status Panel

    private func statusPanel(_ person: ProtectedPerson) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("guardian.member.now"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            statusRow(langManager.localized("guardian.member.status"), value: statusText(person.status), isOk: person.status == .normal)
            if let battery = person.batteryLevel {
                statusRow(langManager.localized("guardian.member.battery"), value: "\(Int(battery * 100))%", isOk: battery > 0.2)
            } else {
                statusRow(langManager.localized("guardian.member.battery"), value: langManager.localized("guardian.member.unknown"), isOk: false)
            }
            if let lastActivity = person.lastPhoneActivity {
                let minutes = Int(Date().timeIntervalSince(lastActivity) / 60)
                statusRow(langManager.localized("guardian.member.phone"), value: minutes < 5 ? String(format: langManager.localized("guardian.member.online.minutes"), minutes) : String(format: langManager.localized("guardian.member.active.minutes"), minutes), isOk: minutes < 30)
            } else {
                statusRow(langManager.localized("guardian.member.phone"), value: langManager.localized("guardian.member.unknown"), isOk: false)
            }
            if let checkIn = person.lastCheckIn {
                let minutes = Int(Date().timeIntervalSince(checkIn) / 60)
                let text = minutes < 60 ? String(format: langManager.localized("guardian.member.minutes.ago"), minutes) : String(format: langManager.localized("guardian.member.hours.ago"), minutes / 60)
                statusRow(langManager.localized("guardian.member.last.checkin"), value: text, isOk: !person.isOverdue)
            } else {
                statusRow(langManager.localized("guardian.member.last.checkin"), value: langManager.localized("guardian.member.never"), isOk: false)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func statusText(_ status: SafetyStatus) -> String {
        switch status {
        case .normal: return langManager.localized("guardian.member.status.normal")
        case .pendingCheckIn: return langManager.localized("guardian.member.status.pending")
        case .overdue: return langManager.localized("guardian.member.status.overdue")
        case .alert: return langManager.localized("guardian.member.status.alert")
        case .unreachable: return langManager.localized("guardian.member.status.unreachable")
        }
    }

    private func statusRow(_ label: String, value: String, isOk: Bool) -> some View {
        HStack {
            Text(label).font(.scaled(size: 13))
            Spacer()
            Text(value)
                .font(.scaled(size: 12))
                .foregroundStyle(isOk ? safe : .primary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        // NOTE: TimelineEntry has no relatedPersonId field, so we cannot filter
        // by person yet. Once the model gains that field, filter here:
        //   coordinator.timeline.filter { $0.relatedPersonId == personId }.prefix(10)
        let personEntries = coordinator.timeline.prefix(10)

        return Group {
            if personEntries.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(personEntries)) { entry in
                        timelineRow(time: formatTime(entry.timestamp), event: entry.description)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func timelineRow(time: String, event: String) -> some View {
        HStack {
            Text(time)
                .font(.scaled(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Text(event)
                .font(.scaled(size: 12.5))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.scaled(size: 12))
                Text(title)
            }
            .font(.scaled(size: 14, weight: .medium))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ink.opacity(0.2), lineWidth: 1)
            )
        }
    }
}
