import SwiftUI
import MapKit

// MARK: - Location Card (Home Screen)
//
// Compact MapKit card showing real-time positions.
// - Protected person: shows own location + nearest guardian
// - Guardian: shows all protected persons' locations
// Supports focusedPinId: when a family card is tapped, the map
// animates to that person's location and shows a callout.

struct LocationCardView: View {
    let pins: [LocationPin]
    var centerCoordinate: CLLocationCoordinate2D?
    var lastUpdateMinutes: Int?
    var label: String?
    @Binding var focusedPinId: String?

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var position: MapCameraPosition

    init(pins: [LocationPin], centerCoordinate: CLLocationCoordinate2D? = nil,
         lastUpdateMinutes: Int? = nil, label: String? = nil,
         focusedPinId: Binding<String?> = .constant(nil)) {
        self.pins = pins
        self.centerCoordinate = centerCoordinate
        self.lastUpdateMinutes = lastUpdateMinutes
        self.label = label
        self._focusedPinId = focusedPinId

        let center = centerCoordinate ?? pins.first?.coordinate
            ?? CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
        let span = pins.count > 1 ? Self.spanForPins(pins) : 0.05
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )))
    }

    private var isFocused: Bool { focusedPinId != nil }
    private var focusedPin: LocationPin? {
        guard let id = focusedPinId else { return nil }
        return pins.first { $0.id == id }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Map
            mapContent
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(height: isFocused ? 220 : 130)

            // Overlay labels
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
                if let pin = focusedPin {
                    // Focused person info
                    HStack(spacing: 4) {
                        Circle().fill(pin.color).frame(width: 6, height: 6)
                        Text(pin.name)
                            .font(.system(size: 10, weight: .medium))
                        if let status = pin.status {
                            Text("· \(status)")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(pin.color.opacity(0.85))
                    .clipShape(Capsule())
                } else if let mins = lastUpdateMinutes {
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

            // Collapse button when focused
            if isFocused {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                focusedPinId = nil
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.right.and.arrow.up.left")
                                    .font(.system(size: 9))
                                Text("收起")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ink.opacity(0.6))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(8)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isFocused ? (focusedPin?.color ?? ink).opacity(0.4) : ink.opacity(0.12), lineWidth: isFocused ? 1.5 : 1)
        )
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.3), value: isFocused)
        .onChange(of: focusedPinId) { _, newId in
            if let newId, let pin = pins.first(where: { $0.id == newId }) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    position = .region(MKCoordinateRegion(
                        center: pin.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    ))
                }
            } else {
                // Reset to show all pins
                let center = centerCoordinate ?? pins.first?.coordinate
                    ?? CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
                let span = pins.count > 1 ? Self.spanForPins(pins) : 0.05
                withAnimation(.easeInOut(duration: 0.5)) {
                    position = .region(MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                    ))
                }
            }
        }
    }

    private var mapContent: some View {
        let modes: MapInteractionModes = isFocused ? [.pan, .zoom] : []
        let style: MapStyle = .standard(pointsOfInterest: .excludingAll)
        return Map(position: $position, interactionModes: modes) {
            ForEach(pins) { pin in
                Annotation(pin.name, coordinate: pin.coordinate) {
                    pinView(pin, isFocused: pin.id == focusedPinId)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                focusedPinId = focusedPinId == pin.id ? nil : pin.id
                            }
                        }
                }
            }
        }
        .mapStyle(style)
    }

    @ViewBuilder
    private func pinView(_ pin: LocationPin, isFocused: Bool) -> some View {
        VStack(spacing: 1) {
            ZStack {
                if isFocused {
                    // Pulsing ring for focused pin
                    Circle()
                        .stroke(pin.color.opacity(0.4), lineWidth: 2)
                        .frame(width: 36, height: 36)
                }
                Circle()
                    .fill(pin.color.opacity(0.25))
                    .frame(width: isFocused ? 32 : 28, height: isFocused ? 32 : 28)
                Circle()
                    .fill(pin.color)
                    .frame(width: isFocused ? 16 : 14, height: isFocused ? 16 : 14)
                if pin.isMe {
                    Circle()
                        .stroke(.white, lineWidth: 2)
                        .frame(width: 18, height: 18)
                }
            }
            Text(pin.name)
                .font(.system(size: isFocused ? 9 : 8, weight: isFocused ? .semibold : .medium))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
    }

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
    var status: String?
}
