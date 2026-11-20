import SwiftUI
import MapKit

struct TripDetailView: View {
    let tripId: String
    /// Whose trip (a guardian looking at someone's) — the PDF report's name
    var personName: String? = nil
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var trip: TripSummary?
    @State private var points: [TripPoint] = []
    @State private var isLoading = true
    @State private var position: MapCameraPosition = .automatic
    @State private var scrubberValue: Double = 1.0
    @State private var showExportSheet = false
    @State private var exportingPDF = false
    @State private var didFit = false

    /// A trip still being recorded is reloaded this often (guardians watch it grow)
    static let livePollSeconds: UInt64 = 15
    private var isLive: Bool { trip?.status == "recording" }

    private let ink = Color.appInk
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
        .toolbar {
            if isLive {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 5) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text(lang.localized("trip.detail.live"))
                            .font(.scaled(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.12), in: Capsule())
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .task {
            await loadTrip()
            // Live: keep reloading while it is being recorded and this screen is open
            while !Task.isCancelled, isLive {
                try? await Task.sleep(nanoseconds: Self.livePollSeconds * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await loadTrip()
            }
        }
    }

    private var mapView: some View {
        Map(position: $position) {
            // Route, coloured by speed (same bands as the live track and the PDF)
            ForEach(Array(TrackRun.runs(visiblePoints).enumerated()), id: \.offset) { _, run in
                MapPolyline(coordinates: run.coordinates)
                    .stroke(Color(uiColor: run.band.uiColor),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
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
                if let last = coordinates.last {
                    OpenInAppleMapsButton(coordinate: last, name: lang.localized("trip.detail.end"))
                }

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
                        statItem(icon: "location.fill", value: String(format: lang.localized("trip.points.count"), trip.pointCount))
                        if let mode = trip.primaryTransportMode {
                            statItem(icon: transportIcon(mode), value: lang.localized("trip.mode.\(mode)"))
                        }
                    }
                }

                // Export: PDF report and GPX
                HStack(spacing: 10) {
                    Button {
                        Task { await exportPDF() }
                    } label: {
                        HStack(spacing: 6) {
                            if exportingPDF { ProgressView().tint(.white) } else {
                                Image(systemName: "doc.richtext").font(.scaled(size: 13))
                            }
                            Text(lang.localized("report.trip.export"))
                        }
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.inkSolid)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(exportingPDF)
                    .accessibilityIdentifier("trip.exportPDF")

                    Button {
                        exportGPX()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.scaled(size: 13))
                            Text(lang.localized("trip.export.gpx"))
                        }
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(Color.inkSolid)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.inkSolid.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
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

                // Fit map to route — once: a live reload must not undo the person's panning
                if !coordinates.isEmpty, !didFit {
                    didFit = true
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

    @MainActor
    private func exportPDF() async {
        exportingPDF = true
        defer { exportingPDF = false }
        let input = TripReportInput(personName: personName ?? coordinator.currentUser?.displayName ?? "",
                                    points: points, inProgress: isLive)
        let data = await TripReportPDF.render(input)
        guard let url = try? TripReportPDF.write(data, input: input) else { return }
        TripReportShare.present(url)
    }

    private func exportGPX() {
        var gpx = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        gpx += "<gpx version=\"1.1\" creator=\"Beaconify\">\n"
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

        // Present from the top-most controller: this screen is itself inside a
        // sheet, and the root (already presenting it) would refuse
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let ac = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let popover = ac.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.maxY - 100, width: 0, height: 0)
        }
        top.present(ac, animated: true)
    }
}
