import SwiftUI
import CoreLocation

struct DistanceChip: View {
    let from: CLLocationCoordinate2D?
    let to: CLLocationCoordinate2D?

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    var body: some View {
        if let distanceText = formattedDistance {
            HStack(spacing: 3) {
                Image(systemName: "location.fill")
                    .font(.system(size: 8))
                Text(distanceText)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(ink.opacity(0.3))
        }
    }

    private var formattedDistance: String? {
        guard let from, let to else { return nil }
        let fromLoc = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLoc = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let meters = fromLoc.distance(from: toLoc)
        let km = meters / 1000

        if km < 1 {
            return String(format: "%.0f m away", meters)
        } else if km < 100 {
            return String(format: "%.1f km away", km)
        } else {
            return String(format: "%.0f km away", km)
        }
    }
}
