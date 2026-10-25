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

    /// Optional reactive location service for live updates
    @ObservedObject var locationService: ReactiveLocationService

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var position: MapCameraPosition
    @State private var addressText: String?
    @State private var showFullScreenMap = false
    @State private var mapDragged = false
    @State private var isFollowing = true

    init(pins: [LocationPin], centerCoordinate: CLLocationCoordinate2D? = nil,
         lastUpdateMinutes: Int? = nil, label: String? = nil,
         focusedPinId: Binding<String?> = .constant(nil),
         locationService: ReactiveLocationService = ReactiveLocationService()) {
        self.pins = pins
        self.centerCoordinate = centerCoordinate
        self.lastUpdateMinutes = lastUpdateMinutes
        self.label = label
        self._focusedPinId = focusedPinId
        self.locationService = locationService

        let center = centerCoordinate ?? pins.first?.coordinate
            ?? CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
        let span = pins.count > 1 ? Self.spanForPins(pins) : 0.05
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )))
    }

    /// Live pins: merge static pins with reactive location updates
    private var livePins: [LocationPin] {
        pins.map { pin in
            if pin.isMe, let liveCoord = locationService.currentLocation {
                var updated = pin
                updated = LocationPin(
                    id: pin.id,
                    name: pin.name,
                    coordinate: liveCoord,
                    color: pin.color,
                    isMe: pin.isMe,
                    status: pin.status,
                    role: pin.role
                )
                return updated
            }
            // Check for live member location updates
            if let member = locationService.memberLocations[pin.id] {
                return LocationPin(
                    id: pin.id,
                    name: pin.name,
                    coordinate: member.coordinate,
                    color: pin.color,
                    isMe: pin.isMe,
                    status: pin.status,
                    role: pin.role
                )
            }
            return pin
        }
    }

    /// Live update minutes
    private var liveUpdateMinutes: Int? {
        locationService.lastUpdateMinutes ?? lastUpdateMinutes
    }

    private var isFocused: Bool { focusedPinId != nil }
    private var focusedPin: LocationPin? {
        guard let id = focusedPinId else { return nil }
        return livePins.first { $0.id == id }
    }

    var body: some View {
        let currentPins = livePins
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Map
                mapContent
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .frame(height: isFocused ? 220 : 130)

                // Overlay: person switcher + labels
                VStack(alignment: .leading, spacing: 4) {
                    // Person icon strip (only show when >1 pin)
                    if currentPins.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(currentPins) { pin in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        focusedPinId = focusedPinId == pin.id ? nil : pin.id
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        ZStack {
                                            Circle()
                                                .fill(pin.color)
                                                .frame(width: 20, height: 20)
                                            Text(String(pin.name.prefix(1)))
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                        if focusedPinId == pin.id {
                                            Text(pin.name)
                                                .font(.scaled(size: 11, weight: .medium))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, focusedPinId == pin.id ? 6 : 0)
                                    .padding(.vertical, 2)
                                    .background(
                                        focusedPinId == pin.id
                                            ? Capsule().fill(pin.color.opacity(0.85))
                                            : Capsule().fill(ink.opacity(0.5))
                                    )
                                }
                            }
                        }
                    }

                    // Info labels
                    if let pin = focusedPin {
                        if let status = pin.status {
                            Text(status)
                                .font(.scaled(size: 11))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(pin.color.opacity(0.7))
                                .clipShape(Capsule())
                        }
                    } else {
                        if let label {
                            Text(label)
                                .font(.scaled(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ink.opacity(0.7))
                                .clipShape(Capsule())
                        }
                        if let mins = liveUpdateMinutes {
                            Text(mins < 1 ? LanguageManager.shared.localized("location.justUpdated") : String(format: LanguageManager.shared.localized("location.minutesAgoUpdated"), mins))
                                .font(.scaled(size: 11))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(ink.opacity(0.5))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(8)

                // Member card (upper right)
                if currentPins.count > 1 {
                    VStack {
                        HStack {
                            Spacer()
                            memberCard
                        }
                        Spacer()
                    }
                    .padding(6)
                }

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
                                        .font(.scaled(size: 9))
                                    Text(LanguageManager.shared.localized("location.collapse"))
                                        .font(.scaled(size: 12))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ink.opacity(0.6))
                                .clipShape(Capsule())
                            }
                            .accessibilityLabel(LanguageManager.shared.localized("location.collapseMap"))
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
                        .font(.scaled(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(ink.opacity(0.65))
                        .clipShape(Circle())
                }
                .accessibilityLabel(LanguageManager.shared.localized("location.expandMap"))
                .padding(8)
            }
            // Recenter button (appears after user drags the map)
            .overlay(alignment: .bottomLeading) {
                if mapDragged {
                    Button {
                        recenterMap()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.scaled(size: 13))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(safe.opacity(0.85))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                    .accessibilityLabel(LanguageManager.shared.localized("location.recenter"))
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // Address from reverse geocoding
            if let address = addressText {
                Text(address)
                    .font(.scaled(size: 12))
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
            FullScreenMapView(pins: livePins, label: label, focusedPinId: $focusedPinId, locationService: locationService)
        }
        .task { await reverseGeocodeMainPin() }
        .onChange(of: focusedPinId) { _, newId in
            let currentPins = livePins
            if let newId, let pin = currentPins.first(where: { $0.id == newId }) {
                isFollowing = false
                withAnimation(.easeInOut(duration: 0.5)) {
                    position = .region(MKCoordinateRegion(
                        center: pin.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    ))
                }
                Task { await reverseGeocode(pin.coordinate) }
            } else {
                // Reset to follow mode
                isFollowing = true
                let center = locationService.currentLocation
                    ?? centerCoordinate ?? currentPins.first?.coordinate
                    ?? CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
                let span = currentPins.count > 1 ? Self.spanForPins(currentPins) : 0.02
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
        let currentPins = livePins
        let style: MapStyle = .standard(pointsOfInterest: .excludingAll)
        return Map(position: $position, interactionModes: [.pan, .zoom]) {
            ForEach(currentPins) { pin in
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
        .onMapCameraChange { _ in
            if !mapDragged {
                withAnimation(.easeInOut(duration: 0.2)) {
                    mapDragged = true
                    isFollowing = false
                }
            }
        }
        // Auto-follow: when location updates and user hasn't dragged
        .onChange(of: locationService.currentLocation?.latitude) { _, _ in
            guard isFollowing, focusedPinId == nil,
                  let coord = locationService.currentLocation else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                position = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                ))
            }
        }
    }

    private func recenterMap() {
        let currentPins = livePins
        // Prefer live location for recenter
        let center = locationService.currentLocation
            ?? centerCoordinate ?? currentPins.first?.coordinate
            ?? CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
        let span = currentPins.count > 1 ? Self.spanForPins(currentPins) : 0.02
        withAnimation(.easeInOut(duration: 0.5)) {
            position = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            ))
            mapDragged = false
            isFollowing = true
            focusedPinId = nil
        }
    }

    @ViewBuilder
    private func pinView(_ pin: LocationPin, isFocused: Bool) -> some View {
        VStack(spacing: 1) {
            if pin.isMe {
                // "My location" — red circle with arrow, always visible
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: isFocused ? 40 : 34, height: isFocused ? 40 : 34)
                    Circle()
                        .stroke(Color.red, lineWidth: 2.5)
                        .frame(width: isFocused ? 32 : 26, height: isFocused ? 32 : 26)
                    Image(systemName: "location.fill")
                        .font(.system(size: isFocused ? 14 : 12, weight: .bold))
                        .foregroundStyle(Color.red)
                }
            } else {
                ZStack {
                    if isFocused {
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
                }
            }
            Text(pin.name)
                .font(.scaled(size: 11, weight: isFocused ? .semibold : .medium))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
    }

    // MARK: - Member Card (upper right translucent overlay)

    private var memberCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(livePins) { pin in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        focusedPinId = focusedPinId == pin.id ? nil : pin.id
                    }
                } label: {
                    HStack(spacing: 5) {
                        // Avatar circle
                        ZStack {
                            Circle()
                                .fill(pin.isMe ? Color.red.opacity(0.2) : pin.color.opacity(0.3))
                                .frame(width: 18, height: 18)
                            if pin.isMe {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.red)
                            } else {
                                Text(String(pin.name.prefix(1)))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        // Name
                        VStack(alignment: .leading, spacing: 0) {
                            Text(pin.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(memberRoleLabel(pin))
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        focusedPinId == pin.id
                            ? RoundedRectangle(cornerRadius: 6).fill(pin.color.opacity(0.4))
                            : RoundedRectangle(cornerRadius: 6).fill(Color.clear)
                    )
                }
            }
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func memberRoleLabel(_ pin: LocationPin) -> String {
        switch pin.role {
        case .me: return LanguageManager.shared.localized("location.roleMe")
        case .guardian: return pin.status ?? LanguageManager.shared.localized("location.roleGuardian")
        case .protected_: return pin.status ?? LanguageManager.shared.localized("location.roleProtected")
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
    @ObservedObject var locationService: ReactiveLocationService
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var position: MapCameraPosition
    @State private var selectedPin: LocationPin?
    @State private var addressText: String?
    @State private var fullMapDragged = false
    @State private var isFollowing = true

    @State private var trailCoordinates: [String: [CLLocationCoordinate2D]] = [:]

    init(pins: [LocationPin], label: String? = nil, focusedPinId: Binding<String?>,
         locationService: ReactiveLocationService = ReactiveLocationService()) {
        self.pins = pins
        self.label = label
        self._focusedPinId = focusedPinId
        self.locationService = locationService

        let center = pins.first?.coordinate
            ?? CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
        let span = pins.count > 1 ? LocationCardView.spanForPins(pins) : 0.05
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )))
    }

    /// Live pins with reactive updates
    private var livePins: [LocationPin] {
        pins.map { pin in
            if pin.isMe, let liveCoord = locationService.currentLocation {
                return LocationPin(
                    id: pin.id, name: pin.name, coordinate: liveCoord,
                    color: pin.color, isMe: true, status: pin.status, role: pin.role
                )
            }
            if let member = locationService.memberLocations[pin.id] {
                return LocationPin(
                    id: pin.id, name: pin.name, coordinate: member.coordinate,
                    color: pin.color, isMe: false, status: pin.status, role: pin.role
                )
            }
            return pin
        }
    }

    var body: some View {
        let currentPins = livePins
        ZStack(alignment: .top) {
            // Full screen map
            Map(position: $position, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
                // Pins
                ForEach(currentPins) { pin in
                    Annotation(pin.name, coordinate: pin.coordinate) {
                        fullPinView(pin)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedPin = selectedPin?.id == pin.id ? nil : pin
                                    position = .region(MKCoordinateRegion(
                                        center: pin.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    ))
                                    isFollowing = false
                                }
                                Task { await reverseGeocode(pin.coordinate) }
                            }
                    }
                }

                // 24-hour trail polylines
                ForEach(currentPins) { pin in
                    if let trail = trailCoordinates[pin.id], trail.count > 1 {
                        MapPolyline(coordinates: trail)
                            .stroke(pin.color.opacity(0.6), lineWidth: 3)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .ignoresSafeArea()
            .onMapCameraChange { _ in
                if !fullMapDragged {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        fullMapDragged = true
                        isFollowing = false
                    }
                }
            }
            // Auto-follow in full screen
            .onChange(of: locationService.currentLocation?.latitude) { _, _ in
                guard isFollowing, selectedPin == nil,
                      let coord = locationService.currentLocation else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    position = .region(MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }

            // Recenter button
            if fullMapDragged {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            recenterFullMap()
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.scaled(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(safe.opacity(0.9))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        }
                        .accessibilityLabel(LanguageManager.shared.localized("location.recenter"))
                        .padding(.trailing, 16)
                        .padding(.bottom, 130)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }

            // Top bar overlay
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.scaled(size: 28))
                            .foregroundStyle(.white, ink.opacity(0.6))
                    }
                    .accessibilityLabel(LanguageManager.shared.localized("location.closeMap"))

                    Spacer()

                    if let label {
                        Text(label)
                            .font(.scaled(size: 13, weight: .semibold))
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
                        Text(LanguageManager.shared.localized("location.trail24h"))
                            .font(.scaled(size: 12))
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
                        .font(.scaled(size: 12))
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
                        ForEach(currentPins) { pin in
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
                                        .font(.scaled(size: 12, weight: selectedPin?.id == pin.id ? .bold : .medium))
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
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if let status = pin.status {
                    Text("· \(status)")
                        .font(.scaled(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button {
                    withAnimation { selectedPin = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.scaled(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            if let address = addressText {
                Text(address)
                    .font(.scaled(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let trail = trailCoordinates[pin.id] {
                Text(String(format: LanguageManager.shared.localized("location.trailInfo"), trail.count))
                    .font(.scaled(size: 12))
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
            if pin.isMe {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Circle()
                        .stroke(Color.red, lineWidth: 3)
                        .frame(width: 34, height: 34)
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.red)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(pin.color.opacity(0.25))
                        .frame(width: 36, height: 36)
                    Circle()
                        .fill(pin.color)
                        .frame(width: 18, height: 18)
                }
            }
            Text(pin.name)
                .font(.scaled(size: 12, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
        }
    }

    private func recenterFullMap() {
        let currentPins = livePins
        let center = locationService.currentLocation
            ?? currentPins.first?.coordinate
            ?? CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
        let span = currentPins.count > 1 ? LocationCardView.spanForPins(currentPins) : 0.02
        withAnimation(.easeInOut(duration: 0.5)) {
            position = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            ))
            fullMapDragged = false
            isFollowing = true
            selectedPin = nil
        }
    }

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
    var role: PinRole = .me

    enum PinRole {
        case me
        case guardian
        case protected_
    }
}
