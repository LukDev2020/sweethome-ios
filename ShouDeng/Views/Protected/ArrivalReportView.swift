import SwiftUI
import CoreLocation

// MARK: - Arrival Report View
//
// One-tap "I arrived safely" with optional place name.
// Notifies all guardians via push. Also counts as a check-in.

struct ArrivalReportView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    @State private var placeName = ""
    @State private var isSending = false
    @State private var didSend = false

    @ObservedObject private var lang = LanguageManager.shared

    private var quickPlaces: [String] {
        ["dorm", "school", "work", "hospital", "airport", "hotel", "friend"]
            .map { lang.localized("arrival.place.\($0)") }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                if didSend {
                    sentConfirmation
                } else {
                    reportForm
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .background(Color(.systemBackground))
            .navigationTitle(LanguageManager.shared.localized("home.arrivalReport"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label(lang.localized("arrival.close"), systemImage: "xmark") }
                }
            }
        }
    }

    // MARK: - Report Form

    private var reportForm: some View {
        VStack(spacing: 20) {
            Image(systemName: "mappin.circle.fill")
                .font(.scaled(size: 48))
                .foregroundStyle(safe)

            Text(lang.localized("arrival.heading"))
                .font(.scaled(size: 20, weight: .semibold))
                .foregroundStyle(ink)

            Text(lang.localized("arrival.subtitle"))
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)

            // Quick place tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPlaces, id: \.self) { place in
                        Button {
                            placeName = place
                        } label: {
                            Text(place)
                                .font(.scaled(size: 13))
                                .foregroundStyle(placeName == place ? .white : ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(placeName == place ? safe : Color(.systemGray6))
                                )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            TextField(lang.localized("arrival.placeholder"), text: $placeName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            Button {
                Task { await sendReport() }
            } label: {
                HStack(spacing: 8) {
                    if isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(lang.localized("arrival.send"))
                        .font(.scaled(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(safe)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isSending)
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Sent Confirmation

    private var sentConfirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.scaled(size: 56))
                .foregroundStyle(safe)

            Text(lang.localized("arrival.sent"))
                .font(.scaled(size: 20, weight: .semibold))
                .foregroundStyle(ink)

            if !placeName.isEmpty {
                Text(String(format: lang.localized("arrival.sentAt"), placeName))
                    .font(.scaled(size: 14))
                    .foregroundStyle(.secondary)
            }

            Button(lang.localized("arrival.done")) { dismiss() }
                .font(.scaled(size: 15, weight: .medium))
                .foregroundStyle(safe)
                .padding(.top, 8)
        }
    }

    // MARK: - Action

    private func sendReport() async {
        isSending = true
        defer { isSending = false }

        let lastLocation = coordinator.locationManager.lastReportedLocation
        do {
            let _: ArrivalReportResponse = try await coordinator.apiClient.post(
                "/v1/arrival-report",
                body: ArrivalReportRequest(
                    latitude: lastLocation?.coordinate.latitude,
                    longitude: lastLocation?.coordinate.longitude,
                    placeName: placeName.isEmpty ? nil : placeName
                )
            )
        } catch {
            #if DEBUG
            print("[ArrivalReport] send error (using local fallback): \(error)")
            #endif
        }
        // Always confirm locally so the UI responds even without backend
        coordinator.addTimelineEntry(
            type: .arrivalReport,
            description: placeName.isEmpty ? lang.localized("arrival.timeline")
                : String(format: lang.localized("arrival.timelineAt"), placeName)
        )
        await MainActor.run { didSend = true }
    }
}
