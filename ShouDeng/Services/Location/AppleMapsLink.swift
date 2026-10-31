import MapKit
import SwiftUI

// MARK: - Apple Maps Link
//
// Hands a coordinate to the Apple Maps app. Apple Maps can use maps the person
// downloaded for offline use (Maps → profile → Offline Maps), which MapKit inside
// this app can't — so "Open in Apple Maps" is how a location stays viewable
// without signal. No map data is cached or stored by this app.

enum AppleMapsLink {

    static func mapItem(for coordinate: CLLocationCoordinate2D, name: String?) -> MKMapItem {
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                             address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
        item.name = name
        return item
    }

    static func launchOptions(for coordinate: CLLocationCoordinate2D, walkingDirections: Bool) -> [String: Any] {
        var options: [String: Any] = [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)),
        ]
        if walkingDirections {
            options[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeWalking
        }
        return options
    }

    /// Opens Apple Maps with a pin (or walking directions) to the coordinate.
    @discardableResult
    static func open(_ coordinate: CLLocationCoordinate2D, name: String?, walkingDirections: Bool = false) -> Bool {
        mapItem(for: coordinate, name: name)
            .openInMaps(launchOptions: launchOptions(for: coordinate, walkingDirections: walkingDirections))
    }

    /// Opens Apple Maps at the person's current location (e.g. to download an offline area).
    @discardableResult
    static func openAtCurrentLocation() -> Bool {
        MKMapItem.forCurrentLocation().openInMaps(launchOptions: nil)
    }
}

// MARK: - Button

struct OpenInAppleMapsButton: View {
    let coordinate: CLLocationCoordinate2D
    let name: String?
    var walkingDirections = false

    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        Button {
            AppleMapsLink.open(coordinate, name: name, walkingDirections: walkingDirections)
        } label: {
            Label(lang.localized(walkingDirections ? "maps.open.directions" : "maps.open.apple"),
                  systemImage: walkingDirections ? "figure.walk" : "map")
                .font(.scaled(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(lang.localized("maps.open.hint"))
    }
}
