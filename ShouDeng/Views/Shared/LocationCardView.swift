import SwiftUI
import MapKit

// MARK: - Location Card (Home Screen)
//
// Compact MapKit card showing real-time positions.
// - Protected person: shows own location + nearest guardian
// - Guardian: shows all protected persons' locations
// Tap to expand full-screen map (future).

struct LocationCardView: View {
    let pins: [LocationPin]
    var centerCoordinate: CLLocationCoordinate2D?
    var lastUpdateMinutes: Int?
    var label: String? // e.g. "我的位置", "家人位置"

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var position: MapCameraPosition

    init(pins: [LocationPin], centerCoordinate: CLLocationCoordinate2D? = nil,
         lastUpdateMinutes: Int? = nil, label: String? = nil) {
        self.pins = pins
        self.centerCoordinate = centerCoordinate
        self.lastUpdateMinutes = lastUpdateMinutes
        self.label = label

        // Compute initial camera
        let center = centerCoordinate ?? pins.first?.coordinate
            ?? CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
        let span = pins.count > 1 ? Self.spanForPins(pins) : 0.05
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Map
            Map(position: $position, interactionModes: []) {
                ForEach(pins) { pin in
                    Annotation(pin.name, coordinate: pin.coordinate) {
                        pinView(pin)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(height: 130)

            // Overlay label
            VStack(alignment: .leading, spacing: 2) {
                if let label {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ink.opacity(0.7))
                        .clipShape(Capsule())
                }
                if let mins = lastUpdateMinutes {
                    Text(mins < 1 ? "刚刚更新" : "\(mins) 分钟前更新")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(ink.opacity(0.5))
                        .clipShape(Capsule())
                }
            }
            .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ink.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func pinView(_ pin: LocationPin) -> some View {
        VStack(spacing: 1) {
            ZStack {
                Circle()
                    .fill(pin.color.opacity(0.25))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(pin.color)
                    .frame(width: 14, height: 14)
                if pin.isMe {
                    Circle()
                        .stroke(.white, lineWidth: 2)
                        .frame(width: 18, height: 18)
                }
            }
            Text(pin.name)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
    }

    // Compute span to fit all pins with some padding
    private static func spanForPins(_ pins: [LocationPin]) -> Double {
        guard pins.count > 1 else { return 0.05 }
        let lats = pins.map(\.coordinate.latitude)
        let lons = pins.map(\.coordinate.longitude)
        let latSpan = (lats.max()! - lats.min()!) * 1.5
        let lonSpan = (lons.max()! - lons.min()!) * 1.5
        return max(max(latSpan, lonSpan), 0.02)
    }
}

// MARK: - Location Pin Model

struct LocationPin: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let color: Color
    var isMe: Bool = false
    var status: String? // "12分钟前", "在线"
}
