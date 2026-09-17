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
    @State private var addressText: String?
    @State private var showFullScreenMap = false

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
        VStack(spacing: 0) {
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
            // Expand button to open fullscreen map
            .overlay(alignment: .topTrailing) {
                Button {
                    showFullScreenMap = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(ink.opacity(0.65))
                        .clipShape(Circle())
                }
                .padding(8)
            }

            // Address from reverse geocoding
            if let address = addressText {
                Text(address)
                    .font(.system(size: 11))
                    .foregroundStyle(ink.opacity(0.6))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 5)
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.3), value: isFocused)
        .onTapGesture(count: 2) {
            showFullScreenMap = true
        }
        .fullScreenCover(isPresented: $showFullScreenMap) {
            FullScreenMapView(pins: pins, label: label, focusedPinId: $focusedPinId)
        }
        .task { await reverseGeocodeMainPin() }
        .onChange(of: focusedPinId) { _, newId in
            if let newId, let pin = pins.first(where: { $0.id == newId }) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    position = .region(MKCoordinateRegion(
                        center: pin.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    ))
                }
                Task { await reverseGeocode(pin.coordinate) }
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
                Task { await reverseGeocodeMainPin() }
            }
        }
    }

    private var mapContent: some View {
        let style: MapStyle = .standard(pointsOfInterest: .excludingAll)
        return Map(position: $position, interactionModes: [.pan, .zoom]) {
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

    static func spanForPins(_ pins: [LocationPin]) -> Double {
        guard pins.count > 1 else { return 0.05 }
        let lats = pins.map(\.coordinate.latitude)
        let lons = pins.map(\.coordinate.longitude)
        let latSpan = (lats.max()! - lats.min()!) * 1.5
        let lonSpan = (lons.max()! - lons.min()!) * 1.5
        return max(max(latSpan, lonSpan), 0.02)
    }

    // MARK: - Reverse Geocoding

    private func reverseGeocodeMainPin() async {
        let coord = centerCoordinate ?? pins.first?.coordinate
        guard let coord else { return }
        await reverseGeocode(coord)
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let parts = [
                    placemark.name,
                    placemark.thoroughfare,
                    placemark.subLocality,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.country
                ].compactMap { $0 }
                let unique = parts.reduce(into: [String]()) { result, part in
                    if !result.contains(part) { result.append(part) }
                }
                let address = unique.joined(separator: ", ")
                await MainActor.run { addressText = address }
            }
        } catch {
            // Geocoding failed silently — address just won't show
        }
    }
}

// MARK: - Full Screen Map View

struct FullScreenMapView: View {
    let pins: [LocationPin]
    var label: String?
    @Binding var focusedPinId: String?
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var position: MapCameraPosition
    @State private var selectedPin: LocationPin?
    @State private var addressText: String?

    // Mock 24-hour trail for demo — in production this comes from server
    @State private var trailCoordinates: [String: [CLLocationCoordinate2D]] = [:]

    init(pins: [LocationPin], label: String? = nil, focusedPinId: Binding<String?>) {
        self.pins = pins
        self.label = label
        self._focusedPinId = focusedPinId

        let center = pins.first?.coordinate
            ?? CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
        let span = pins.count > 1 ? LocationCardView.spanForPins(pins) : 0.05
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Full screen map
            Map(position: $position, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
                // Pins
                ForEach(pins) { pin in
                    Annotation(pin.name, coordinate: pin.coordinate) {
                        fullPinView(pin)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedPin = selectedPin?.id == pin.id ? nil : pin
                                    position = .region(MKCoordinateRegion(
                                        center: pin.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    ))
                                }
                                Task { await reverseGeocode(pin.coordinate) }
                            }
                    }
                }

                // 24-hour trail polylines
                ForEach(pins) { pin in
                    if let trail = trailCoordinates[pin.id], trail.count > 1 {
                        MapPolyline(coordinates: trail)
                            .stroke(pin.color.opacity(0.6), lineWidth: 3)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            // Top bar overlay
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, ink.opacity(0.6))
                    }

                    Spacer()

                    if let label {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(ink.opacity(0.7))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    // Trail legend
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(safe.opacity(0.6))
                            .frame(width: 16, height: 3)
                        Text("24h 轨迹")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ink.opacity(0.6))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 60)

                Spacer()

                // Bottom info panel
                if let pin = selectedPin {
                    selectedPinPanel(pin)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let address = addressText {
                    Text(address)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(ink.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 40)
                }

                // Pin list at bottom
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pins) { pin in
                            Button {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    selectedPin = pin
                                    position = .region(MKCoordinateRegion(
                                        center: pin.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    ))
                                }
                                Task { await reverseGeocode(pin.coordinate) }
                            } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(pin.color).frame(width: 8, height: 8)
                                    Text(pin.name)
                                        .font(.system(size: 12, weight: selectedPin?.id == pin.id ? .bold : .medium))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedPin?.id == pin.id ? pin.color.opacity(0.8) : ink.opacity(0.6))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedPin?.id)
    }

    private func selectedPinPanel(_ pin: LocationPin) -> some View {
        VStack(spacing: 6) {
            HStack {
                Circle().fill(pin.color).frame(width: 10, height: 10)
                Text(pin.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if let status = pin.status {
                    Text("· \(status)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button {
                    withAnimation { selectedPin = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            if let address = addressText {
                Text(address)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let trail = trailCoordinates[pin.id] {
                Text("过去 24 小时 · \(trail.count) 个位置记录")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(ink.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func fullPinView(_ pin: LocationPin) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(pin.color.opacity(0.25))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(pin.color)
                    .frame(width: 18, height: 18)
                if pin.isMe {
                    Circle()
                        .stroke(.white, lineWidth: 2.5)
                        .frame(width: 22, height: 22)
                }
            }
            Text(pin.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
    }

    // MARK: - Trail Data
    // Trail data requires a /v1/location/trail API endpoint (not yet implemented).
    // Until then, trails are empty — the map shows current pins only.

    // MARK: - Reverse Geocoding

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let parts = [
                    placemark.name,
                    placemark.thoroughfare,
                    placemark.subLocality,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.country
                ].compactMap { $0 }
                let unique = parts.reduce(into: [String]()) { result, part in
                    if !result.contains(part) { result.append(part) }
                }
                let address = unique.joined(separator: ", ")
                await MainActor.run { addressText = address }
            }
        } catch {
            // Geocoding failed silently
        }
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
