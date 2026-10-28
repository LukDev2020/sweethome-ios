import SwiftUI

struct TripHistoryView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var trips: [TripSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// If set, fetch trips for this user (guardian viewing protected person)
    var targetUserId: String?
    var targetUserName: String?

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if trips.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(ink.opacity(0.3))
                        Text(lang.localized("trip.history.empty"))
                            .font(.scaled(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(trips) { trip in
                        NavigationLink {
                            TripDetailView(tripId: trip.id)
                                .environmentObject(coordinator)
                        } label: {
                            tripRow(trip)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(targetUserName != nil
                ? String(format: lang.localized("trip.history.titleFor"), targetUserName!)
                : lang.localized("trip.history.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task { await loadTrips() }
        }
    }

    private func tripRow(_ trip: TripSummary) -> some View {
        HStack(spacing: 12) {
            // Transport icon
            Image(systemName: transportIcon(trip.primaryTransportMode))
                .font(.system(size: 18))
                .foregroundStyle(safe)
                .frame(width: 36, height: 36)
                .background(safe.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                // Date + time
                Text(formatDate(trip.startTime))
                    .font(.scaled(size: 14, weight: .medium))
                    .foregroundStyle(ink)

                // Distance + duration
                HStack(spacing: 8) {
                    Text(formatDistance(trip.totalDistanceMeters))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                    Text(formatDuration(trip.durationSeconds))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                    if trip.pointCount > 0 {
                        Text(String(format: lang.localized("trip.points.count"), trip.pointCount))
                            .font(.scaled(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if trip.status == "recording" {
                Text(lang.localized("trip.status.recording"))
                    .font(.scaled(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private func transportIcon(_ mode: String?) -> String {
        switch mode {
        case "walking": return "figure.walk"
        case "cycling": return "bicycle"
        case "driving": return "car.fill"
        case "flying": return "airplane"
        default: return "mappin.and.ellipse"
        }
    }

    private func formatDate(_ isoString: String?) -> String {
        guard let isoString else { return "—" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else { return isoString }
        let df = DateFormatter()
        df.dateFormat = lang.current == .chinese ? "M月d日 HH:mm" : "MMM d, HH:mm"
        return df.string(from: date)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return String(format: "%dh %dm", h, m) }
        return String(format: "%dm", max(m, 1))
    }

    private func loadTrips() async {
        isLoading = true
        do {
            var path = "/v1/trip/list"
            if let uid = targetUserId { path += "?userId=\(uid)" }
            let response: TripListResponse = try await coordinator.apiClient.get(path)
            await MainActor.run {
                trips = response.trips
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
