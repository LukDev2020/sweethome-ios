import Foundation
import CoreLocation

// MARK: - Nearby alerts (GET /v1/nearby/alerts)
//
// Disasters, traffic and crime around the person, from public sources
// (shoudeng-backend/functions/src/services/nearbyAlerts.ts). For each category the
// server says whether something was found, nothing was found, or there is no public
// information for this place — the card shows each of the three differently.

struct NearbyAlertsResponse: Codable, Equatable {
    let radiusKm: Int
    let coverage: [String: NearbyCoverage]
    let alerts: [NearbyAlert]

    func status(_ category: NearbyCategory) -> NearbyCoverage.Status {
        coverage[category.rawValue].flatMap { NearbyCoverage.Status(rawValue: $0.status) } ?? .noData
    }

    /// Most serious first, then nearest (whatever order the source used)
    func alerts(in category: NearbyCategory) -> [NearbyAlert] {
        alerts.filter { $0.category == category.rawValue }.sorted(by: NearbyAlert.moreImportant)
    }
}

struct NearbyCoverage: Codable, Equatable {
    enum Status: String { case found, clear, noData }
    let status: String
    let sources: [String]
}

enum NearbyCategory: String, CaseIterable, Identifiable {
    case disaster, traffic, crime
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .disaster: return "exclamationmark.triangle.fill"
        case .traffic: return "car.fill"
        case .crime: return "shield.lefthalf.filled"
        }
    }
}

struct NearbyAlert: Codable, Identifiable, Equatable {
    struct Count: Codable, Equatable { let label: String; let count: Int }

    let id: String
    let category: String
    let kind: String
    let severity: Int
    let distanceKm: Double
    /// Kept as text: sources write dates in several ISO shapes
    let occurredAt: String?
    let place: String?
    let magnitude: Double?
    let source: String
    let url: String?
    let total: Int?
    let top: [Count]?
    let dataUntil: String?
    let radiusKm: Double?

    static func moreImportant(_ a: NearbyAlert, _ b: NearbyAlert) -> Bool {
        a.severity != b.severity ? a.severity > b.severity : a.distanceKm < b.distanceKm
    }

    var occurredDate: Date? { NearbyAlert.parseDate(occurredAt) }
    var dataUntilDate: Date? { NearbyAlert.parseDate(dataUntil) }

    var icon: String {
        switch kind {
        case "earthquake": return "waveform.path.ecg"
        case "cyclone": return "hurricane"
        case "flood": return "water.waves"
        case "volcano": return "mountain.2.fill"
        case "wildfire": return "flame.fill"
        case "drought": return "sun.max.trianglebadge.exclamationmark"
        case "tsunami": return "water.waves.and.arrow.trianglehead.up"
        case "weather": return "cloud.bolt.rain.fill"
        case "accident": return "car.side.rear.and.collision.and.car.side.front"
        case "closure": return "xmark.octagon.fill"
        case "roadworks": return "cone.fill"
        case "jam": return "car.2.fill"
        case "crimeSummary": return "shield.lefthalf.filled"
        default: return "exclamationmark.triangle.fill"
        }
    }

    /// ISO with or without fractions / zone, or a plain day ("2026-09-01")
    static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: text) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: text) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return nil
    }
}

/// One shared copy for both homes; refreshed at most every 10 minutes per place and radius.
@MainActor
final class NearbyAlertsStore: ObservableObject {
    static let shared = NearbyAlertsStore()
    static let radii = [10, 30, 50, 100]
    static let radiusKey = "nearby.radiusKm"

    @Published private(set) var result: NearbyAlertsResponse?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published var radiusKm: Int = {
        let saved = UserDefaults.standard.integer(forKey: NearbyAlertsStore.radiusKey)
        return NearbyAlertsStore.radii.contains(saved) ? saved : 30
    }() {
        didSet { UserDefaults.standard.set(radiusKm, forKey: Self.radiusKey) }
    }

    private var lastKey: String?
    private var lastAt: Date?

    func load(near coordinate: CLLocationCoordinate2D?, api: APIClient, force: Bool = false) async {
        guard let coordinate else { return }
        let lat = (coordinate.latitude * 100).rounded() / 100
        let lng = (coordinate.longitude * 100).rounded() / 100
        let key = "\(lat),\(lng),\(radiusKm)"
        if !force, key == lastKey, let lastAt, Date().timeIntervalSince(lastAt) < 600, result != nil { return }
        loading = true
        defer { loading = false }
        do {
            let response: NearbyAlertsResponse = try await api.get("/v1/nearby/alerts?lat=\(lat)&lng=\(lng)&radiusKm=\(radiusKm)")
            result = response
            failed = false
            lastKey = key
            lastAt = Date()
        } catch {
            failed = result == nil
        }
    }

    /// Signed out / another account: nothing of the old place stays on screen
    func reset() {
        result = nil
        lastKey = nil
        lastAt = nil
        failed = false
    }
}
