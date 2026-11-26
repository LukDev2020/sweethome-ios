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

    private let ink = Color.appInk
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
                                            Text(AvatarInitial.make(for: pin.name))
                                                .lineLimit(1).minimumScaleFactor(0.4)
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
                                            : Capsule().fill(Color.inkSolid.opacity(0.5))
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
                                .background(Color.inkSolid.opacity(0.7))
                                .clipShape(Capsule())
                        }
                        if let mins = liveUpdateMinutes {
                            Text(mins < 1 ? LanguageManager.shared.localized("location.justUpdated") : String(format: LanguageManager.shared.localized("location.minutesAgoUpdated"), mins))
                                .font(.scaled(size: 11))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.inkSolid.opacity(0.5))
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
                                .background(Color.inkSolid.opacity(0.6))
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
                        .background(Color.inkSolid.opacity(0.65))
                        .clipShape(Circle())
                }
                .accessibilityLabel(LanguageManager.shared.localized("location.expandMap"))
                .padding(8)
            }
            // Recenter button (appears after user drags the map). Bottom-trailing keeps the
            // Apple Maps logo and Legal link (bottom-leading) visible, as MapKit requires.
            .overlay(alignment: .bottomTrailing) {
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
                .annotationTitles(.hidden) // pinView draws the name; MapKit's title doubled it ("我 / 我")
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
                                Text(AvatarInitial.make(for: pin.name))
                                    .lineLimit(1).minimumScaleFactor(0.4)
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
                            if !pin.isMe { // "我" under "我" said nothing
                                Text(memberRoleLabel(pin))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
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
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: LanguageManager.shared.current.rawValue))
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

    private let ink = Color.appInk
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    /// Near-opaque so map labels don't show through the floating panels
    private let panel = Color(red: 18/255, green: 30/255, blue: 52/255).opacity(0.95)

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

    // Nearby places: the category being shown, its result markers, map style
    @State private var activeCategory: MapPlaceCategory?
    @State private var showResultList = false
    @State private var selectedResultIndex: Int?
    @State private var mapMode: MapDisplayMode = .standard
    @State private var visibleRegion: MKCoordinateRegion?
    @Environment(\.openURL) private var openURL

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


    /// Opened from the simple home: start on a category ("hospital") or with the
    /// search box ready to type
    private let startCategoryId: String?
    private let startTyping: Bool

    init(pins: [LocationPin], label: String? = nil, focusedPinId: Binding<String?>,
         locationService: ReactiveLocationService = ReactiveLocationService(),
         startCategoryId: String? = nil, startTyping: Bool = false) {
        self.pins = pins
        self.label = label
        self._focusedPinId = focusedPinId
        self.locationService = locationService
        self.startCategoryId = startCategoryId
        self.startTyping = startTyping

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
            Map(position: $position, interactionModes: [.pan, .zoom, .rotate, .pitch], selection: $selectedResultIndex) {
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
                    .annotationTitles(.hidden) // fullPinView draws its own name
                }

                // Trail polylines
                ForEach(currentPins) { pin in
                    if let trail = trailCoordinates[pin.id], trail.count > 1 {
                        MapPolyline(coordinates: trail)
                            .stroke(pin.color.opacity(0.6), lineWidth: 3)
                    }
                }

                // Nearby / search results: one marker each, tap to pick
                ForEach(Array(searchResults.enumerated()), id: \.offset) { idx, item in
                    if let coord = item.placemark.location?.coordinate {
                        Marker(item.name ?? "", systemImage: activeCategory?.icon ?? "mappin",
                               coordinate: coord)
                            .tint(activeCategory?.color ?? alert)
                            .tag(idx)
                    }
                }

                // Navigation route polyline
                if let route = activeRoute {
                    MapPolyline(route.polyline)
                        .stroke(routeTransportMode.color, lineWidth: 5)
                }
            }
            .mapStyle(mapMode.style)
            .mapControls { MapCompass(); MapScaleView() }
            .ignoresSafeArea()
            .onMapCameraChange(frequency: .onEnd) { ctx in visibleRegion = ctx.region }
            .onChange(of: selectedResultIndex) { _, idx in
                guard let idx, idx < searchResults.count else { return }
                selectSearchResult(searchResults[idx])
            }
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

            // Recenter button (out of the way while a place or route card is up)
            if fullMapDragged && selectedSearchItem == nil && activeRoute == nil {
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

                    searchBarView
                }
                .padding(.horizontal, 16)
                .padding(.top, 60)

                // Nearby places: emergency first, then everyday
                poiChipsView
                    .padding(.top, 8)

                if isSearching {
                    ProgressView().tint(.white)
                        .padding(8)
                        .background(panel, in: Capsule())
                        .padding(.top, 6)
                } else if showResultList {
                    searchResultsView
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack {
                    Spacer()
                    mapModeControls
                }
                .padding(.trailing, 16)
                .padding(.top, 8)

                Spacer()

                // Navigation route panel
                if activeRoute != nil {
                    routePanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // The picked place: call, directions, Apple Maps
                else if let item = selectedSearchItem {
                    placePanel(item)
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
                        .background(Color.inkSolid.opacity(0.7))
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
        // Globe sits in black space: white status bar there
        .preferredColorScheme(mapMode == .globe ? .dark : nil)
        .task {
            if let id = startCategoryId,
               let category = (MapPlaceCategory.emergency + MapPlaceCategory.daily).first(where: { $0.id == id }) {
                searchNearby(category)
            } else if startTyping {
                try? await Task.sleep(nanoseconds: 450_000_000)   // after the sheet has settled
                searchFieldFocused = true
            }
        }
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
        .background(panel)
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

    // MARK: - Place Panel

    private func placePanel(_ item: MKMapItem) -> some View {
        let lm = LanguageManager.shared
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: activeCategory?.icon ?? "mappin.circle.fill")
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(activeCategory?.color ?? alert, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? lm.localized("map.search.unknown"))
                        .font(.scaled(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let address = item.placemark.title {
                        Text(address)
                            .font(.scaled(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(2)
                    }
                    if let dist = distanceFromMe(item) {
                        Text(formatSearchDistance(dist))
                            .font(.scaled(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedSearchItem = nil
                        selectedResultIndex = nil
                        addressText = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.scaled(size: 22))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .accessibilityLabel(lm.localized("common.close"))
            }

            HStack(spacing: 8) {
                Button {
                    calculateRoute()
                } label: {
                    HStack(spacing: 5) {
                        if isCalculatingRoute {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        }
                        Text(lm.localized("map.route.navigate"))
                    }
                    .font(.scaled(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(safe, in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isCalculatingRoute)

                if let phone = item.phoneNumber, let url = Self.telURL(phone) {
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "phone.fill")
                            Text(lm.localized("map.place.call"))
                        }
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.blue.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("\(lm.localized("map.place.call")) \(phone)")
                }

                Button {
                    openInAppleMaps()
                } label: {
                    Image(systemName: "map.fill")
                        .font(.scaled(size: 15))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 42)
                        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel(lm.localized("map.search.openInMaps"))
            }
        }
        .padding(14)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    static func telURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    private func distanceFromMe(_ item: MKMapItem) -> CLLocationDistance? {
        guard let location = item.placemark.location,
              let me = locationService.currentLocation ?? pins.first(where: \.isMe)?.coordinate else { return nil }
        return location.distance(from: CLLocation(latitude: me.latitude, longitude: me.longitude))
    }

    // MARK: - Map Style

    private var mapModeControls: some View {
        VStack(spacing: 0) {
            ForEach(MapDisplayMode.allCases, id: \.self) { mode in
                Button {
                    setMapMode(mode)
                } label: {
                    Image(systemName: mode.icon)
                        .font(.scaled(size: 16, weight: .medium))
                        .foregroundStyle(mapMode == mode ? Color(red: 232/255, green: 163/255, blue: 61/255) : .white)
                        .frame(width: 42, height: 40)
                }
                .accessibilityLabel(LanguageManager.shared.localized(mode.labelKey))
                .accessibilityAddTraits(mapMode == mode ? .isSelected : [])
            }
        }
        .background(panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func setMapMode(_ mode: MapDisplayMode) {
        let wasGlobe = mapMode == .globe
        mapMode = mode
        if mode == .globe {
            let me = locationService.currentLocation ?? pins.first?.coordinate
                ?? CLLocationCoordinate2D(latitude: 20, longitude: 0)
            isFollowing = false
            withAnimation(.easeInOut(duration: 1.2)) {
                position = .camera(MapCamera(
                    centerCoordinate: .init(latitude: max(-30, min(30, me.latitude)), longitude: me.longitude),
                    distance: GlobeMapView.globeDistance, heading: 0, pitch: 0))
            }
        } else if wasGlobe {
            recenterFullMap()
        }
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
                .background(Color.inkSolid.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(Color.inkSolid.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Route Logic

    private func calculateRoute() {
        guard let item = selectedSearchItem,
              item.placemark.location?.coordinate != nil,
              let myCoord = locationService.currentLocation else { return }

        // MapKit draws no public-transport routes in apps: hand transit to Apple Maps
        if routeTransportMode == .transit {
            openInAppleMaps()
            return
        }

        isCalculatingRoute = true
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: myCoord))
        request.destination = item
        request.transportType = routeTransportMode.mkType

        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            isCalculatingRoute = false
            guard let response, let route = response.routes.first else {
                // No route for this mode: clear the old one rather than show it
                activeRoute = nil
                routeSteps = []
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                activeRoute = route
                routeSteps = route.steps
                // Fit map to show entire route
                let rect = route.polyline.boundingMapRect
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
            TextField("", text: $searchText,
                      prompt: Text(LanguageManager.shared.localized("map.search.placeholder")).foregroundStyle(.white.opacity(0.55)))
                .font(.scaled(size: 14))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($searchFieldFocused)
                .submitLabel(.search)
                .onSubmit { performSearch() }
            if !searchText.isEmpty || !searchResults.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.scaled(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .accessibilityLabel(LanguageManager.shared.localized("map.search.clear"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func clearSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            searchText = ""
            searchResults = []
            activeCategory = nil
            showResultList = false
            selectedSearchItem = nil
            selectedResultIndex = nil
            addressText = nil
            searchFieldFocused = false
            clearRoute()
        }
    }

    // MARK: - Nearby Places

    private var poiChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MapPlaceCategory.emergency) { chip($0) }
                Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 20)
                ForEach(MapPlaceCategory.daily) { chip($0) }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ category: MapPlaceCategory) -> some View {
        let on = activeCategory == category
        return Button {
            if on { clearSearch() } else { searchNearby(category) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.scaled(size: 11, weight: .semibold))
                    .foregroundStyle(on ? .white : category.color)
                Text(LanguageManager.shared.localized(category.labelKey))
                    .font(.scaled(size: 12, weight: on ? .semibold : .regular))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(on ? category.color : panel, in: Capsule())
            .overlay(Capsule().stroke(category.isEmergency && !on ? category.color.opacity(0.7) : .clear, lineWidth: 1))
        }
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Search Results

    private var searchResultsView: some View {
        let lm = LanguageManager.shared
        return VStack(spacing: 0) {
            if searchResults.isEmpty {
                Text(lm.localized("map.search.noResults"))
                    .font(.scaled(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(12)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(searchResults.enumerated()), id: \.offset) { idx, item in
                            resultRow(item)
                            if idx < searchResults.count - 1 {
                                Divider().overlay(.white.opacity(0.12)).padding(.leading, 40)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func resultRow(_ item: MKMapItem) -> some View {
        HStack(spacing: 8) {
            Button {
                selectSearchResult(item)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: activeCategory?.icon ?? "mappin.circle.fill")
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(activeCategory?.color ?? safe)
                        .frame(width: 24)
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
                    Spacer(minLength: 4)
                    if let dist = distanceFromMe(item) {
                        Text(formatSearchDistance(dist))
                            .font(.scaled(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .contentShape(Rectangle())
            }
            if let phone = item.phoneNumber, let url = Self.telURL(phone) {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.scaled(size: 13))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.blue.opacity(0.8), in: Circle())
                }
                .accessibilityLabel("\(LanguageManager.shared.localized("map.place.call")) \(item.name ?? phone)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        .background(Color.inkSolid.opacity(0.5))
        .clipShape(Capsule())
    }

    // MARK: - Search Logic

    /// Where to look: the part of the map on screen when zoomed in to a town,
    /// otherwise around me (a whole-country view would find nothing useful)
    private var searchRegion: MKCoordinateRegion? {
        if let region = visibleRegion, mapMode != .globe,
           region.span.latitudeDelta < 1.0, region.span.longitudeDelta < 1.0 {
            return region
        }
        guard let me = locationService.currentLocation ?? pins.first?.coordinate else { return nil }
        return MKCoordinateRegion(center: me, span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        activeCategory = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        run(request)
    }

    private func searchNearby(_ category: MapPlaceCategory) {
        activeCategory = category
        searchText = ""
        searchFieldFocused = false
        let request = MKLocalSearch.Request()
        if let poi = category.poi {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [poi])
            request.resultTypes = .pointOfInterest
            // A category search needs some text on older systems; the filter does the work
            request.naturalLanguageQuery = category.query
        } else {
            request.naturalLanguageQuery = category.query
        }
        run(request)
    }

    private func run(_ request: MKLocalSearch.Request) {
        if let region = searchRegion { request.region = region }
        isSearching = true
        selectedSearchItem = nil
        selectedResultIndex = nil
        clearRoute()
        if mapMode == .globe { mapMode = .standard }
        MKLocalSearch(request: request).start { response, error in
            isSearching = false
            let items = (error == nil ? response?.mapItems : nil) ?? []
            // Nearest first, the way you'd want them in an emergency
            searchResults = Array(items.sorted {
                (distanceFromMe($0) ?? .greatestFiniteMagnitude) < (distanceFromMe($1) ?? .greatestFiniteMagnitude)
            }.prefix(25))
            withAnimation(.easeInOut(duration: 0.25)) { showResultList = true }
            fitResults()
        }
    }

    /// Show me and the closest results together
    private func fitResults() {
        let coords = searchResults.prefix(5).compactMap { $0.placemark.location?.coordinate }
            + [locationService.currentLocation].compactMap { $0 }
        guard !coords.isEmpty else { return }
        var rect = MKMapRect.null
        for c in coords {
            let pt = MKMapPoint(c)
            rect = rect.union(MKMapRect(x: pt.x, y: pt.y, width: 1, height: 1))
        }
        let padX = max(rect.width * 0.35, 2000), padY = max(rect.height * 0.6, 2000)
        withAnimation(.easeInOut(duration: 0.5)) {
            position = .rect(rect.insetBy(dx: -padX, dy: -padY))
            isFollowing = false
            fullMapDragged = true
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        selectedSearchItem = item
        clearRoute()
        searchFieldFocused = false
        withAnimation(.easeInOut(duration: 0.25)) { showResultList = false }
        if let idx = searchResults.firstIndex(of: item), selectedResultIndex != idx {
            selectedResultIndex = idx
        }
        if let coord = item.placemark.location?.coordinate {
            withAnimation(.easeInOut(duration: 0.5)) {
                position = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
                isFollowing = false
            }
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
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: LanguageManager.shared.current.rawValue))
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

// MARK: - Nearby place categories

/// One-tap "what's near me": emergency services first, then everyday places.
struct MapPlaceCategory: Identifiable, Equatable {
    let id: String
    let icon: String
    let labelKey: String
    let poi: MKPointOfInterestCategory?
    /// Used alone when there's no POI category (embassies), else alongside it
    let query: String
    let color: Color
    let isEmergency: Bool

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }

    private static let red = Color(red: 214/255, green: 69/255, blue: 65/255)

    static let emergency: [MapPlaceCategory] = [
        .init(id: "hospital", icon: "cross.case.fill", labelKey: "map.search.hospital", poi: .hospital, query: "hospital", color: red, isEmergency: true),
        .init(id: "police", icon: "shield.fill", labelKey: "map.search.police", poi: .police, query: "police", color: Color(red: 52/255, green: 101/255, blue: 201/255), isEmergency: true),
        .init(id: "fire", icon: "flame.fill", labelKey: "map.search.fire", poi: .fireStation, query: "fire station", color: Color(red: 232/255, green: 110/255, blue: 40/255), isEmergency: true),
        .init(id: "pharmacy", icon: "pills.fill", labelKey: "map.search.pharmacy", poi: .pharmacy, query: "pharmacy", color: Color(red: 46/255, green: 150/255, blue: 100/255), isEmergency: true),
        .init(id: "embassy", icon: "building.columns.fill", labelKey: "map.search.embassy", poi: nil, query: "embassy consulate", color: Color(red: 107/255, green: 92/255, blue: 165/255), isEmergency: true),
    ]

    static let daily: [MapPlaceCategory] = [
        .init(id: "grocery", icon: "cart.fill", labelKey: "map.search.grocery", poi: .foodMarket, query: "grocery", color: Color(red: 63/255, green: 143/255, blue: 110/255), isEmergency: false),
        .init(id: "food", icon: "fork.knife", labelKey: "map.search.food", poi: .restaurant, query: "restaurant", color: Color(red: 232/255, green: 140/255, blue: 61/255), isEmergency: false),
        .init(id: "cafe", icon: "cup.and.saucer.fill", labelKey: "map.search.cafe", poi: .cafe, query: "cafe", color: Color(red: 150/255, green: 105/255, blue: 70/255), isEmergency: false),
        .init(id: "gas", icon: "fuelpump.fill", labelKey: "map.search.gas", poi: .gasStation, query: "gas station", color: Color(red: 61/255, green: 120/255, blue: 192/255), isEmergency: false),
        .init(id: "ev", icon: "bolt.car.fill", labelKey: "map.search.ev", poi: .evCharger, query: "EV charger", color: Color(red: 40/255, green: 170/255, blue: 160/255), isEmergency: false),
        .init(id: "atm", icon: "banknote.fill", labelKey: "map.search.atm", poi: .atm, query: "ATM", color: Color(red: 90/255, green: 140/255, blue: 70/255), isEmergency: false),
        .init(id: "parking", icon: "parkingsign", labelKey: "map.search.parking", poi: .parking, query: "parking", color: Color(red: 61/255, green: 110/255, blue: 200/255), isEmergency: false),
        .init(id: "transit", icon: "tram.fill", labelKey: "map.search.transit", poi: .publicTransport, query: "station", color: Color(red: 120/255, green: 100/255, blue: 190/255), isEmergency: false),
        .init(id: "hotel", icon: "bed.double.fill", labelKey: "map.search.hotel", poi: .hotel, query: "hotel", color: Color(red: 170/255, green: 90/255, blue: 140/255), isEmergency: false),
    ]
}

/// Street map, satellite with labels, or the whole-Earth globe.
enum MapDisplayMode: CaseIterable {
    case standard, satellite, globe

    var icon: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "square.2.layers.3d"
        case .globe: return "globe.americas.fill"
        }
    }

    var labelKey: String {
        switch self {
        case .standard: return "map.mode.map"
        case .satellite: return "map.mode.satellite"
        case .globe: return "map.mode.globe"
        }
    }

    var style: MapStyle {
        switch self {
        case .standard: return .standard(elevation: .realistic, pointsOfInterest: .all)
        case .satellite: return .hybrid(elevation: .realistic, pointsOfInterest: .all)
        case .globe: return .imagery(elevation: .realistic)
        }
    }
}
