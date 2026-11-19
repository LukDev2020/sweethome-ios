import SwiftUI
import MapKit

// MARK: - Interactive Globe (Apple Maps)
//
// Apple's satellite globe (MapKit imagery, realistic elevation): drag to spin,
// pinch to zoom in on a city. Family members are glowing dots, each linked to
// the hub by a great-circle arc. Labels are one per place (see labelGroups).

struct GlobeMapView: View {

    struct Pin {
        let label: String
        let latitude: Double
        let longitude: Double
        let color: Color
        let isMe: Bool

        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    struct Link {
        let from: Int
        let to: Int
    }

    let pins: [Pin]
    var links: [Link] = []
    /// Where the globe faces when there are no pins.
    var initialLongitude: Double = -40
    /// Shows an "Open map" button (full-screen map: search, nearby places, routes)
    var onExpand: (() -> Void)?

    /// Far enough out that the whole Earth shows as a globe
    static let globeDistance: CLLocationDistance = 26_000_000

    @State private var position: MapCameraPosition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Slow spin, like the old drawn globe; stops for good once the user touches it
    @State private var spinning = true
    @State private var centerLongitude: Double = 0
    private let spinTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(pins: [Pin], links: [Link] = [], initialLongitude: Double = -40, onExpand: (() -> Void)? = nil) {
        self.pins = pins
        self.links = links
        self.initialLongitude = initialLongitude
        self.onExpand = onExpand
        _position = State(initialValue: Self.globeCamera(pins: pins, fallbackLongitude: initialLongitude))
        _centerLongitude = State(initialValue: Self.globeCenter(pins: pins, fallbackLongitude: initialLongitude).longitude)
    }

    var body: some View {
        globeMap
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(globeAccessibilityLabel)
            .overlay(alignment: .topTrailing) {
                if let onExpand {
                    Button(action: onExpand) {
                        HStack(spacing: 5) {
                            Image(systemName: "map.fill")
                            Text(LanguageManager.shared.localized("globe.openMap"))
                        }
                        .font(.scaled(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    }
                    .padding(10)
                    .accessibilityHint(LanguageManager.shared.localized("globe.openMap.hint"))
                }
            }
    }

    private var globeMap: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                if link.from < pins.count, link.to < pins.count {
                    MapPolyline(coordinates: [pins[link.from].coordinate, pins[link.to].coordinate],
                                contourStyle: .geodesic)
                        .stroke(Self.lamp.opacity(0.85),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))
                }
            }
            ForEach(Array(Self.labelGroups(pins).enumerated()), id: \.offset) { _, group in
                let members = group.pinIndices.map { pins[$0] }
                let isMe = members.contains(where: \.isMe)
                let color = (members.first(where: \.isMe) ?? members[0]).color
                Annotation(group.label, coordinate: .init(latitude: group.latitude, longitude: group.longitude)) {
                    GlowDot(color: color, isMe: isMe)
                }
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControls { }
        .background(Color.black)
        .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { _ in spinning = false })
        .simultaneousGesture(MagnifyGesture().onChanged { _ in spinning = false })
        .onReceive(spinTimer) { _ in
            guard spinning, !reduceMotion else { return }
            centerLongitude = centerLongitude >= 180 ? centerLongitude - 357.5 : centerLongitude + 2.5
            let lat = Self.globeCenter(pins: pins, fallbackLongitude: initialLongitude).latitude
            withAnimation(.linear(duration: 1)) {
                position = .camera(MapCamera(centerCoordinate: .init(latitude: lat, longitude: centerLongitude),
                                             distance: Self.globeDistance, heading: 0, pitch: 0))
            }
        }
        // Family moved / joined: face the globe toward them again
        .onChange(of: pinsKey) { _, _ in
            let center = Self.globeCenter(pins: pins, fallbackLongitude: initialLongitude)
            centerLongitude = center.longitude
            withAnimation(.easeInOut(duration: 0.8)) {
                position = Self.globeCamera(pins: pins, fallbackLongitude: initialLongitude)
            }
        }
    }

    /// Changes when someone is added, removed or moves more than ~100 km
    private var pinsKey: String {
        pins.map { "\(Int($0.latitude))/\(Int($0.longitude))" }.joined(separator: ",")
    }

    /// The camera over the middle of everyone (3-D mean of their positions),
    /// pulled back to show the whole globe.
    static func globeCamera(pins: [Pin], fallbackLongitude: Double) -> MapCameraPosition {
        .camera(MapCamera(centerCoordinate: globeCenter(pins: pins, fallbackLongitude: fallbackLongitude),
                          distance: globeDistance, heading: 0, pitch: 0))
    }

    static func globeCenter(pins: [Pin], fallbackLongitude: Double) -> CLLocationCoordinate2D {
        let rad = Double.pi / 180
        var x = 0.0, y = 0.0, z = 0.0
        for p in pins {
            let la = p.latitude * rad, lo = p.longitude * rad
            x += cos(la) * cos(lo); y += cos(la) * sin(lo); z += sin(la)
        }
        let len = sqrt(x * x + y * y + z * z)
        // Nobody, or people on opposite sides of the Earth: fall back to "me" / the default view
        guard len > 0.3 else {
            if let me = pins.first(where: \.isMe) ?? pins.first {
                return .init(latitude: max(-30, min(30, me.latitude)), longitude: me.longitude)
            }
            return .init(latitude: 20, longitude: fallbackLongitude)
        }
        // MapKit pulls a camera over high latitudes in to ~11 000 km (the globe no longer fits): stay near the tropics
        return .init(latitude: max(-30, min(30, asin(z / len) / rad)), longitude: atan2(y, x) / rad)
    }

    private var globeAccessibilityLabel: String {
        let lm = LanguageManager.shared
        if pins.isEmpty { return lm.localized("globe.a11y.empty") }
        let names = Self.labelGroups(pins).map(\.label).joined(separator: "; ")
        return String(format: lm.localized("globe.a11y.members"), pins.count, names)
    }

    // MARK: - Label grouping

    /// One label per place: people closer than `mergeKm` share a single dot label
    /// ("Xiulan Chen, Jianguo Chen · Chengdu") instead of drawing overlapping text.
    struct LabelGroup: Equatable {
        let label: String
        let latitude: Double
        let longitude: Double
        let pinIndices: [Int]
    }

    static let mergeKm: Double = 40

    static func labelGroups(_ pins: [Pin]) -> [LabelGroup] {
        var groups: [[Int]] = []
        for (i, pin) in pins.enumerated() {
            if let g = groups.firstIndex(where: { group in
                group.contains { distanceKm(pins[$0], pin) < mergeKm }
            }) {
                groups[g].append(i)
            } else {
                groups.append([i])
            }
        }
        return groups.map { idx in
            let members = idx.map { pins[$0] }
            return LabelGroup(
                label: mergedLabel(members.map(\.label)),
                latitude: members[0].latitude,
                longitude: members[0].longitude,
                pinIndices: idx
            )
        }
    }

    /// "A · City" + "B · City" → "A, B · City"; 3+ names → "A +2 · City".
    static func mergedLabel(_ labels: [String]) -> String {
        guard labels.count > 1 else { return labels.first ?? "" }
        let parts = labels.map { $0.components(separatedBy: " · ") }
        let names = parts.map { $0[0] }
        let suffixes = Set(parts.map { $0.count > 1 ? $0.dropFirst().joined(separator: " · ") : "" })
        let who = names.count > 2 ? "\(names[0]) +\(names.count - 1)" : names.joined(separator: ", ")
        if suffixes.count == 1, let suffix = suffixes.first, !suffix.isEmpty {
            return "\(who) · \(suffix)"
        }
        return who
    }

    private static func distanceKm(_ a: Pin, _ b: Pin) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad
        let dLon = (b.longitude - a.longitude) * rad
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }
}

// MARK: - Dot

private struct GlowDot: View {
    let color: Color
    let isMe: Bool

    var body: some View {
        let core: CGFloat = isMe ? 11 : 8
        ZStack {
            Circle().fill(color.opacity(0.22)).frame(width: core * 2.6, height: core * 2.6)
            Circle().fill(color.opacity(0.4)).frame(width: core * 1.6, height: core * 1.6)
            Circle().fill(color).frame(width: core, height: core)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: isMe ? 1.5 : 1))
        }
    }
}

// MARK: - Colours

extension GlobeMapView {
    static let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
}
