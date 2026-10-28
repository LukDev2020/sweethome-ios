import SwiftUI
import MapKit

struct TripDetailView: View {
    let tripId: String
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var trip: TripSummary?
    @State private var points: [TripPoint] = []
    @State private var isLoading = true
    @State private var position: MapCameraPosition = .automatic
    @State private var scrubberValue: Double = 1.0
    @State private var showExportSheet = false

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let routeColor = Color(red: 61/255, green: 154/255, blue: 192/255)

    private var visiblePoints: [TripPoint] {
        guard !points.isEmpty else { return [] }
        let count = max(1, Int(Double(points.count) * scrubberValue))
        return Array(points.prefix(count))
    }

    private var coordinates: [CLLocationCoordinate2D] {
        visiblePoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if points.isEmpty {
                Text(lang.localized("trip.detail.noPoints"))
                    .foregroundStyle(.secondary)
            } else {
                mapView
                overlayUI
            }
        }
        .navigationTitle(lang.localized("trip.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTrip() }
    }

    private var mapView: some View {
        Map(position: $position) {
            // Route polyline
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(routeColor, lineWidth: 4)
            }

            // Start pin
            if let first = coordinates.first {
                Annotation(lang.localized("trip.detail.start"), coordinate: first) {
                    Circle()
                        .fill(.green)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }

            // Current position (scrubber)
            if let last = coordinates.last, coordinates.count > 1 {
                Annotation("", coordinate: last) {
                    Circle()
                        .fill(routeColor)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(radius: 3)
                }
            }

            // End pin (only when fully scrubbed)
            if scrubberValue >= 1.0, let last = coordinates.last, coordinates.count > 1 {
                Annotation(lang.localized("trip.detail.end"), coordinate: last) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
            }
        }
        .mapStyle(.standard)
        .ignoresSafeArea()
    }

    private var overlayUI: some View {
        VStack {
            Spacer()

            VStack(spacing: 10) {
                // Scrubber
                if points.count > 1 {
                    VStack(spacing: 4) {
                        Slider(value: $scrubberValue, in: 0.01...1.0)
                            .tint(routeColor)
                        HStack {
                            Text(formatPointTime(visiblePoints.first))
                                .font(.scaled(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatPointTime(visiblePoints.last))
                                .font(.scaled(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Stats
                if let trip {
                    HStack(spacing: 16) {
                        statItem(icon: "arrow.triangle.swap", value: formatDistance(trip.totalDistanceMeters))
                        statItem(icon: "clock", value: formatDuration(trip.durationSeconds))
                        statItem(icon: "location.fill", value: "\(trip.pointCount) pts")
                        if let mode = trip.primaryTransportMode {
                            statItem(icon: transportIcon(mode), value: lang.localized("trip.mode.\(mode)"))
                        }
                    }
                }

                // Export button
                Button {
                    exportGPX()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.scaled(size: 13))
                        Text(lang.localized("trip.export.gpx"))
                    }
                    .font(.scaled(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(ink)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func statItem(icon: String, value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.scaled(size: 14))
                .foregroundStyle(safe)
            Text(value)
                .font(.scaled(size: 12, weight: .medium))
                .foregroundStyle(ink)
        }
    }

    private func transportIcon(_ mode: String?) -> String {
        switch mode {
        case "walking": return "figure.walk"
        case "cycling": return "bicycle"
        case "driving": return "car.fill"
        default: return "mappin"
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return String(format: "%dh %dm", h, m) }
        return String(format: "%dm", max(m, 1))
    }

    private func formatPointTime(_ point: TripPoint?) -> String {
        guard let point else { return "" }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: point.timestamp)
    }

    private func loadTrip() async {
        do {
            let response: TripDetailResponse = try await coordinator.apiClient.get("/v1/trip/\(tripId)")
            await MainActor.run {
                trip = response.trip
                points = response.points
                isLoading = false

                // Fit map to route
                if let first = coordinates.first {
                    let region = regionForCoordinates(coordinates)
                    position = .region(region)
                }
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    private func regionForCoordinates(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coords.isEmpty else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
                                      span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.3, 0.005),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.3, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private func exportGPX() {
        var gpx = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        gpx += "<gpx version=\"1.1\" creator=\"Lantern Care\">\n"
        gpx += "  <trk>\n    <name>Trip</name>\n    <trkseg>\n"

        let df = ISO8601DateFormatter()
        for p in points {
            gpx += "      <trkpt lat=\"\(p.latitude)\" lon=\"\(p.longitude)\">\n"
            if let alt = p.altitude { gpx += "        <ele>\(alt)</ele>\n" }
            gpx += "        <time>\(df.string(from: p.timestamp))</time>\n"
            if let spd = p.speed { gpx += "        <speed>\(spd)</speed>\n" }
            gpx += "      </trkpt>\n"
        }
        gpx += "    </trkseg>\n  </trk>\n</gpx>"

        // Share via UIActivityViewController
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("trip.gpx")
        try? gpx.write(to: tempURL, atomically: true, encoding: .utf8)

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let root = window.rootViewController else { return }
        let ac = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let popover = ac.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.maxY - 100, width: 0, height: 0)
        }
        root.present(ac, animated: true)
    }
}
