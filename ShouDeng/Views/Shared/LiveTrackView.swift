import SwiftUI
import MapKit

// MARK: - Live Track (Garmin LiveTrack style)
//
// The trip being recorded, drawn as it happens: the line is coloured by speed,
// an arrow shows where the person is heading, and the camera follows them until
// they move the map. Big numbers underneath; "Export PDF" works during the trip
// and after it ends.

struct LiveTrackView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject var recorder: TripRecordingService
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var following = true
    @State private var showStopConfirm = false
    @State private var exporting = false
    @State private var exportFailed = false

    static let followDistance: CLLocationDistance = 1500
    static let followPitch: Double = 40

    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
    private let red = Color(red: 214/255, green: 69/255, blue: 65/255)
    private let green = Color(red: 63/255, green: 143/255, blue: 110/255)

    /// Recording: the live line. Ended: the trip that just finished.
    private var points: [TripPoint] {
        recorder.isRecording ? recorder.livePoints : (recorder.lastFinishedTrip?.points ?? [])
    }

    private var stats: TripStats { TripStats.compute(points) }

    var body: some View {
        ZStack(alignment: .top) {
            map
            topBar
            VStack {
                Spacer()
                mapButtons
                panel
            }
        }
        .onChange(of: recorder.livePoints.count) { _, _ in follow(animated: true) }
        .onAppear { follow(animated: false) }
        .alert(lang.localized("trip.record.stop"), isPresented: $showStopConfirm) {
            Button(lang.localized("settings.action.confirm"), role: .destructive) {
                Task { _ = try? await recorder.stopRecording() }
            }
            Button(lang.localized("settings.action.cancel"), role: .cancel) {}
        } message: {
            Text(lang.localized("trip.record.confirm.end"))
        }
        .alert(lang.localized("live.exportFailed"), isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $position) {
            ForEach(Array(TrackRun.runs(points).enumerated()), id: \.offset) { _, run in
                MapPolyline(coordinates: run.coordinates)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: run.coordinates)
                    .stroke(Color(uiColor: run.band.uiColor),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let first = points.first {
                Annotation(lang.localized("trip.detail.start"), coordinate: first.coordinate) {
                    Circle().fill(green).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2.5))
                }
            }
            if let last = points.last, points.count > 1 {
                Annotation("", coordinate: last.coordinate) {
                    if recorder.isRecording {
                        HeadingArrow(bearing: heading)
                    } else {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(red, in: Circle())
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        // Moving the map yourself stops the camera chasing the arrow
        .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in following = false })
        .ignoresSafeArea()
    }

    /// Direction of travel over the last few fixes (one fix alone is jittery)
    private var heading: Double {
        guard points.count > 1 else { return 0 }
        let last = points[points.count - 1]
        let earlier = points[max(0, points.count - 4)]
        return TripStats.bearing(from: earlier.coordinate, to: last.coordinate)
    }

    private func follow(animated: Bool) {
        guard following, let last = points.last else { return }
        let camera = MapCamera(centerCoordinate: last.coordinate, distance: Self.followDistance,
                               heading: 0, pitch: Self.followPitch)
        if animated {
            withAnimation(.easeInOut(duration: 0.8)) { position = .camera(camera) }
        } else {
            position = .camera(camera)
        }
    }

    private func showWholeRoute() {
        following = false
        guard points.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.8)) {
            position = .region(TripReportPDF.region(for: points))
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(navy)
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(lang.localized("common.close"))

            HStack(spacing: 7) {
                if recorder.isRecording {
                    Circle().fill(red).frame(width: 9, height: 9)
                    Text(lang.localized("live.title")).font(.scaled(size: 14, weight: .bold))
                    Text(recorder.elapsedFormatted)
                        .font(.scaled(size: 14, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "flag.checkered")
                    Text(lang.localized("live.finished")).font(.scaled(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(navy)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.regularMaterial, in: Capsule())

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var mapButtons: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                mapButton(icon: following ? "location.fill" : "location", label: lang.localized("live.follow"),
                          active: following) {
                    following = true
                    follow(animated: true)
                }
                mapButton(icon: "point.topleft.down.to.point.bottomright.curvepath", label: lang.localized("live.overview"),
                          active: false) { showWholeRoute() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func mapButton(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? .white : navy)
                .frame(width: 44, height: 44)
                .background(active ? AnyShapeStyle(navy) : AnyShapeStyle(.regularMaterial),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel(label)
    }

    private var panel: some View {
        VStack(spacing: 12) {
            if points.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(lang.localized("live.waiting")).font(.scaled(size: 14)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                // Big number: speed now (during the trip) or average (after)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", (recorder.isRecording ? recorder.currentSpeed : stats.averageSpeed) * 3.6))
                        .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(navy)
                    Text("km/h").font(.scaled(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(lang.localized(recorder.isRecording ? "live.speedNow" : "report.trip.avgSpeed"))
                        .font(.scaled(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    // Recording: the same clock as the top bar (not first-to-last fix)
                    stat(lang.localized("live.time"),
                         recorder.isRecording ? recorder.elapsedFormatted : TripFormat.duration(stats.durationSeconds))
                    stat(lang.localized("report.trip.distance"), TripFormat.distance(stats.distanceMeters))
                    stat(lang.localized("report.trip.avgSpeed"), TripFormat.speed(stats.averageSpeed))
                    stat(lang.localized("report.trip.maxSpeed"), TripFormat.speed(stats.maxSpeed))
                    stat(lang.localized("report.trip.elevGain"), TripFormat.metres(stats.elevationGain))
                    stat(lang.localized("report.trip.points"), "\(points.count)")
                }

                speedLegend
            }

            HStack(spacing: 10) {
                if recorder.isRecording {
                    Button { showStopConfirm = true } label: {
                        Label(lang.localized("trip.record.stop"), systemImage: "stop.fill")
                            .font(.scaled(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .accessibilityIdentifier("live.stop")
                }
                Button { Task { await exportPDF() } } label: {
                    HStack(spacing: 6) {
                        if exporting { ProgressView().tint(.white) } else { Image(systemName: "doc.richtext") }
                        Text(lang.localized("report.trip.export"))
                    }
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(points.count < 2 || exporting)
                .opacity(points.count < 2 ? 0.5 : 1)
                .accessibilityIdentifier("live.exportPDF")
            }

            if recorder.isRecording && !recorder.isLocalOnly {
                Text(lang.localized("live.shared"))
                    .font(.scaled(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.scaled(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.scaled(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(navy)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speedLegend: some View {
        HStack(spacing: 10) {
            ForEach(TrackSpeedBand.allCases, id: \.rawValue) { band in
                HStack(spacing: 4) {
                    Capsule().fill(Color(uiColor: band.uiColor)).frame(width: 14, height: 5)
                    Text(band.rangeLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    // MARK: Export

    @MainActor
    private func exportPDF() async {
        exporting = true
        defer { exporting = false }
        let input = TripReportInput(personName: coordinator.currentUser?.displayName ?? "",
                                    points: points, inProgress: recorder.isRecording)
        let data = await TripReportPDF.render(input)
        guard let url = try? TripReportPDF.write(data, input: input) else {
            exportFailed = true
            return
        }
        TripReportShare.present(url)
    }
}

// MARK: - Pieces

extension TripPoint {
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

private struct HeadingArrow: View {
    let bearing: Double

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.18)).frame(width: 38, height: 38)
            Circle().fill(.white).frame(width: 26, height: 26).shadow(radius: 2)
            Image(systemName: "location.north.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 1/255, green: 69/255, blue: 129/255))
                .rotationEffect(.degrees(bearing))
        }
        .accessibilityHidden(true)
    }
}

/// The share sheet for a report file, from whatever is on screen (these views sit in sheets)
enum TripReportShare {
    @MainActor
    static func present(_ url: URL) {
        guard let top = AppCoordinator.topViewController() else { return }
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = ac.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 100, width: 0, height: 0)
        }
        top.present(ac, animated: true)
    }
}
