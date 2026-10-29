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
        guard let maxLat = lats.max(), let minLat = lats.min(),
              let maxLon = lons.max(), let minLon = lons.min() else { return 0.05 }
        let latSpan = (maxLat - minLat) * 1.5
        let lonSpan = (maxLon - minLon) * 1.5
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

    // Search state
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var showSearchBar = false
    @State private var selectedSearchItem: MKMapItem?
    @FocusState private var searchFieldFocused: Bool

    // Trail time range
    @State private var trailTimeRange: TrailTimeRange = .h24

    enum TrailTimeRange: String, CaseIterable {
        case h1 = "1h"
        case h6 = "6h"
        case h24 = "24h"
        case d7 = "7d"
    }

    // Navigation route state
    @State private var activeRoute: MKRoute?
    @State private var routeTransportMode: RouteTransportMode = .walking
    @State private var isCalculatingRoute = false
    @State private var routeSteps: [MKRoute.Step] = []
    @State private var showRouteSteps = false

    enum RouteTransportMode: String, CaseIterable {
        case walking
        case cycling
        case driving
        case transit

        var icon: String {
            switch self {
            case .walking: return "figure.walk"
            case .cycling: return "bicycle"
            case .driving: return "car.fill"
            case .transit: return "bus.fill"
            }
        }

        var mkType: MKDirectionsTransportType {
            switch self {
            case .walking, .cycling: return .walking
            case .driving: return .automobile
            case .transit: return .transit
            }
        }

        var mapLaunchMode: String {
            switch self {
            case .walking: return MKLaunchOptionsDirectionsModeWalking
            case .cycling: return MKLaunchOptionsDirectionsModeWalking
            case .driving: return MKLaunchOptionsDirectionsModeDriving
            case .transit: return MKLaunchOptionsDirectionsModeTransit
            }
        }

        var color: Color {
            switch self {
            case .walking: return Color(red: 63/255, green: 143/255, blue: 110/255)
            case .cycling: return Color(red: 61/255, green: 154/255, blue: 192/255)
            case .driving: return Color(red: 107/255, green: 92/255, blue: 165/255)
            case .transit: return Color(red: 232/255, green: 163/255, blue: 61/255)
            }
        }
    }

    // POI categories
    private let poiCategories: [(icon: String, label: String, category: MKPointOfInterestCategory)] = [
        ("cross.fill", "map.search.hospital", .hospital),
        ("shield.fill", "map.search.police", .police),
        ("pills.fill", "map.search.pharmacy", .pharmacy),
        ("fuelpump.fill", "map.search.gas", .gasStation),
        ("fork.knife", "map.search.food", .restaurant),
        ("cup.and.saucer.fill", "map.search.cafe", .cafe),
    ]

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

                // Trail polylines
                ForEach(currentPins) { pin in
                    if let trail = trailCoordinates[pin.id], trail.count > 1 {
                        MapPolyline(coordinates: trail)
                            .stroke(pin.color.opacity(0.6), lineWidth: 3)
                    }
                }

                // Search result pin
                if let item = selectedSearchItem,
                   let coord = item.placemark.location?.coordinate {
                    Annotation(item.name ?? "", coordinate: coord) {
                        VStack(spacing: 2) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.red)
                                .background(Circle().fill(.white).frame(width: 20, height: 20))
                            Text(item.name ?? "")
                                .font(.scaled(size: 11, weight: .semibold))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

                // Navigation route polyline
                if let route = activeRoute {
                    MapPolyline(route.polyline)
                        .stroke(routeTransportMode.color, lineWidth: 5)
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

                    if !showSearchBar {
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
                    }

                    // Search toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSearchBar.toggle()
                            if !showSearchBar {
                                searchText = ""
                                searchResults = []
                                selectedSearchItem = nil
                                clearRoute()
                            } else {
                                searchFieldFocused = true
                            }
                        }
                    } label: {
                        Image(systemName: showSearchBar ? "xmark" : "magnifyingglass")
                            .font(.scaled(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(ink.opacity(0.65))
                            .clipShape(Circle())
                    }

                    if !showSearchBar {
                        // Trail time range picker
                        trailTimePicker
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 60)

                // Search bar
                if showSearchBar {
                    searchBarView
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // POI quick filters
                if showSearchBar && searchText.isEmpty {
                    poiChipsView
                        .padding(.top, 6)
                        .transition(.opacity)
                }

                // Search results list
                if !searchResults.isEmpty {
                    searchResultsView
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // Navigation route panel
                if activeRoute != nil {
                    routePanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // Navigate button for selected search result (no active route)
                else if selectedSearchItem != nil && activeRoute == nil {
                    navigateButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // Bottom info panel
                else if let pin = selectedPin {
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

    // MARK: - Navigate Button

    private var navigateButton: some View {
        Button {
            calculateRoute()
        } label: {
            HStack(spacing: 6) {
                if isCalculatingRoute {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.scaled(size: 14))
                }
                Text(LanguageManager.shared.localized("map.route.navigate"))
                    .font(.scaled(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(safe)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isCalculatingRoute)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Route Panel

    private var routePanel: some View {
        VStack(spacing: 10) {
            // ETA + distance
            if let route = activeRoute {
                HStack {
                    Image(systemName: routeTransportMode.icon)
                        .font(.scaled(size: 16))
                        .foregroundStyle(routeTransportMode.color)
                    Text(formatRouteDuration(route.expectedTravelTime))
                        .font(.scaled(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("·")
                        .foregroundStyle(.white.opacity(0.4))
                    Text(formatSearchDistance(route.distance))
                        .font(.scaled(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            clearRoute()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.scaled(size: 22))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            // Transport mode picker
            HStack(spacing: 4) {
                ForEach(RouteTransportMode.allCases, id: \.self) { mode in
                    Button {
                        routeTransportMode = mode
                        calculateRoute()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.scaled(size: 12))
                            Text(LanguageManager.shared.localized("map.route.\(mode.rawValue)"))
                                .font(.scaled(size: 11, weight: .medium))
                        }
                        .foregroundStyle(routeTransportMode == mode ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(routeTransportMode == mode ? mode.color.opacity(0.8) : ink.opacity(0.3))
                        .clipShape(Capsule())
                    }
                }
            }

            // Directions steps (collapsible)
            if !routeSteps.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showRouteSteps.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                            .font(.scaled(size: 12))
                        Text(String(format: LanguageManager.shared.localized("map.route.steps"), routeSteps.count))
                            .font(.scaled(size: 12))
                        Spacer()
                        Image(systemName: showRouteSteps ? "chevron.up" : "chevron.down")
                            .font(.scaled(size: 10))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }

                if showRouteSteps {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(routeSteps.enumerated()), id: \.offset) { idx, step in
                                if !step.instructions.isEmpty {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(idx + 1)")
                                            .font(.scaled(size: 11, weight: .bold))
                                            .foregroundStyle(routeTransportMode.color)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(step.instructions)
                                                .font(.scaled(size: 12))
                                                .foregroundStyle(.white)
                                            if step.distance > 0 {
                                                Text(formatSearchDistance(step.distance))
                                                    .font(.scaled(size: 10))
                                                    .foregroundStyle(.white.opacity(0.5))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
            }

            // Open in Apple Maps
            Button {
                openInAppleMaps()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "map.fill")
                        .font(.scaled(size: 12))
                    Text(LanguageManager.shared.localized("map.search.openInMaps"))
                        .font(.scaled(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(ink.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(ink.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Route Logic

    private func calculateRoute() {
        guard let item = selectedSearchItem,
              let destCoord = item.placemark.location?.coordinate,
              let myCoord = locationService.currentLocation else { return }

        isCalculatingRoute = true
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: myCoord))
        request.destination = item
        request.transportType = routeTransportMode.mkType

        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            isCalculatingRoute = false
            guard let response, let route = response.routes.first else {
                // Fallback: if transit not available, try automobile
                if routeTransportMode == .transit {
                    activeRoute = nil
                    routeSteps = []
                }
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                activeRoute = route
                routeSteps = route.steps
                // Fit map to show entire route
                let rect = route.polyline.boundingMapRect
                let padding = UIEdgeInsets(top: 80, left: 40, bottom: 200, right: 40)
                position = .rect(rect)
            }
        }
    }

    private func clearRoute() {
        activeRoute = nil
        routeSteps = []
        showRouteSteps = false
    }

    private func openInAppleMaps() {
        guard let item = selectedSearchItem else { return }
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: routeTransportMode.mapLaunchMode,
        ])
    }

    private func formatRouteDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins >= 60 {
            let hours = mins / 60
            let remainMins = mins % 60
            return String(format: LanguageManager.shared.localized("map.route.duration.hm"), hours, remainMins)
        }
        return String(format: LanguageManager.shared.localized("map.route.duration.m"), mins)
    }

    // MARK: - Search Bar

    private var searchBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.scaled(size: 14))
                .foregroundStyle(.white.opacity(0.6))
            TextField(LanguageManager.shared.localized("map.search.placeholder"), text: $searchText)
                .font(.scaled(size: 14))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($searchFieldFocused)
                .onSubmit { performSearch() }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                    selectedSearchItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.scaled(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(ink.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - POI Quick Filters

    private var poiChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(poiCategories, id: \.label) { poi in
                    Button {
                        searchPOI(category: poi.category)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: poi.icon)
                                .font(.scaled(size: 11))
                            Text(LanguageManager.shared.localized(poi.label))
                                .font(.scaled(size: 12))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ink.opacity(0.6))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Search Results

    private var searchResultsView: some View {
        VStack(spacing: 2) {
            ForEach(searchResults.prefix(5), id: \.self) { item in
                Button {
                    selectSearchResult(item)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.scaled(size: 16))
                            .foregroundStyle(safe)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name ?? LanguageManager.shared.localized("map.search.unknown"))
                                .font(.scaled(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if let address = item.placemark.title {
                                Text(address)
                                    .font(.scaled(size: 11))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if let location = item.placemark.location,
                           let myLoc = locationService.currentLocation {
                            let dist = location.distance(from: CLLocation(latitude: myLoc.latitude, longitude: myLoc.longitude))
                            Text(formatSearchDistance(dist))
                                .font(.scaled(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(ink.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Trail Time Picker

    private var trailTimePicker: some View {
        HStack(spacing: 2) {
            ForEach(TrailTimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        trailTimeRange = range
                    }
                } label: {
                    Text(range.rawValue)
                        .font(.scaled(size: 11, weight: trailTimeRange == range ? .bold : .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(trailTimeRange == range ? safe.opacity(0.7) : ink.opacity(0.4))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(ink.opacity(0.5))
        .clipShape(Capsule())
    }

    // MARK: - Search Logic

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText

        // Search near current map region
        if let coord = locationService.currentLocation ?? pins.first?.coordinate {
            request.region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false
            guard let response, error == nil else {
                searchResults = []
                return
            }
            searchResults = response.mapItems
        }
    }

    private func searchPOI(category: MKPointOfInterestCategory) {
        isSearching = true
        let request = MKLocalSearch.Request()
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [category])
        if let coord = locationService.currentLocation ?? pins.first?.coordinate {
            request.region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false
            guard let response, error == nil else {
                searchResults = []
                return
            }
            searchResults = response.mapItems
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        selectedSearchItem = item
        searchResults = []
        searchFieldFocused = false
        if let coord = item.placemark.location?.coordinate {
            withAnimation(.easeInOut(duration: 0.5)) {
                position = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
                isFollowing = false
            }
            addressText = item.name
        }
    }

    private func formatSearchDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
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
