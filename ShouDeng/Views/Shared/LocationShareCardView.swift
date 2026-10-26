import SwiftUI
import MapKit

struct LocationShareCardView: View {
    let latitude: Double
    let longitude: Double
    let address: String
    let timestamp: Date

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(safe)
                    .frame(width: 6, height: 6)
                Text("Live Location")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }

            // Address
            Text(address)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            // Coordinates
            Text(String(format: "%.4f\u{00B0} N, %.4f\u{00B0} W", latitude, abs(longitude)))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))

            // Map snapshot
            MapSnapshotView(latitude: latitude, longitude: longitude)
                .frame(height: 80)
                .cornerRadius(8)
                .overlay(
                    Circle()
                        .fill(alert)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: alert.opacity(0.3), radius: 4)
                )
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color(red: 26/255, green: 42/255, blue: 58/255), Color(red: 15/255, green: 31/255, blue: 48/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
    }
}

private struct MapSnapshotView: View {
    let latitude: Double
    let longitude: Double
    @State private var snapshot: UIImage?

    var body: some View {
        Group {
            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color(red: 200/255, green: 216/255, blue: 200/255).opacity(0.3))
                    .overlay(ProgressView().tint(.white.opacity(0.5)))
            }
        }
        .task { await generateSnapshot() }
    }

    private func generateSnapshot() async {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        options.size = CGSize(width: 300, height: 120)
        options.mapType = .standard

        do {
            let snapshotter = MKMapSnapshotter(options: options)
            let result = try await snapshotter.start()
            await MainActor.run { snapshot = result.image }
        } catch {
            // Silently fail — placeholder shown
        }
    }
}
