import Foundation
import MapKit
import CoreLocation
import Combine

// MARK: - RouteRiskService
//
// Evaluates navigation routes for safety risk by sampling each route's
// polyline every 200 m, running MKLocalSearch at each sample point, and
// aggregating isolation / time-of-day / length factors into a 0–1 risk score.
//
// Usage:
//   await RouteRiskService.shared.evaluateRoutes([route1, route2])
//   let sorted = RouteRiskService.shared.routeRiskScores  // lowest risk first

// MARK: - Supporting Types

/// Discrete risk bands mapped from the 0–1 continuous score.
enum RiskLevel: String, Codable {
    case safe    = "safe"
    case caution = "caution"
    case warning = "warning"
    case danger  = "danger"

    init(score: Double) {
        switch score {
        case ..<0.25:  self = .safe
        case ..<0.50:  self = .caution
        case ..<0.75:  self = .warning
        default:       self = .danger
        }
    }

    var localizedLabel: String {
        switch self {
        case .safe:    return NSLocalizedString("route_risk_safe",    comment: "Risk level: safe")
        case .caution: return NSLocalizedString("route_risk_caution", comment: "Risk level: caution")
        case .warning: return NSLocalizedString("route_risk_warning", comment: "Risk level: warning")
        case .danger:  return NSLocalizedString("route_risk_danger",  comment: "Risk level: danger")
        }
    }
}

/// Individual contributors to route risk, each carrying a raw 0–1 risk value.
enum RiskFactor {
    /// Night (22:00–05:00) = 0.30, dusk/dawn (05:00–07:00, 19:00–22:00) = 0.15, day = 0.0
    case timeOfDay(risk: Double)
    /// Longer routes increase cumulative exposure.
    case routeLength(risk: Double)
    /// Segments with fewer than 2 POIs within 300 m.
    case isolatedArea(risk: Double)
    /// No commercial / residential POIs within 200 m (lighting proxy).
    case poorLighting(risk: Double)
    /// High-traffic roads are safer for pedestrians at night.
    case highTraffic(risk: Double)

    var risk: Double {
        switch self {
        case .timeOfDay(let r),
             .routeLength(let r),
             .isolatedArea(let r),
             .poorLighting(let r),
             .highTraffic(let r):
            return r
        }
    }

    var label: String {
        switch self {
        case .timeOfDay:   return NSLocalizedString("risk_factor_time",      comment: "")
        case .routeLength: return NSLocalizedString("risk_factor_length",    comment: "")
        case .isolatedArea:return NSLocalizedString("risk_factor_isolated",  comment: "")
        case .poorLighting:return NSLocalizedString("risk_factor_lighting",  comment: "")
        case .highTraffic: return NSLocalizedString("risk_factor_traffic",   comment: "")
        }
    }
}

/// A single point along the route polyline annotated with its computed risk level,
/// used to render colored route segments in the map overlay.
struct RiskOverlayPoint {
    let coordinate: CLLocationCoordinate2D
    let riskLevel: RiskLevel
}

/// Complete risk assessment for one MKRoute.
struct RouteRiskScore {
    let route: MKRoute
    let overallRisk: Double          // 0.0 (safest) … 1.0 (most dangerous)
    let riskLevel: RiskLevel
    let factors: [RiskFactor]
    let safetyTips: [String]
    let overlayPoints: [RiskOverlayPoint]
}

// MARK: - POI Cache

private struct POICacheEntry {
    let count: Int
    let hasHighTrafficRoad: Bool
    let timestamp: Date
}

// MARK: - RouteRiskService

@MainActor
final class RouteRiskService: ObservableObject {

    static let shared = RouteRiskService()
    private init() {}

    // MARK: - Published State

    /// Evaluated scores, sorted safest-first. Updated after each evaluateRoutes call.
    @Published var routeRiskScores: [RouteRiskScore] = []

    /// True while an evaluation is in progress.
    @Published var isEvaluating: Bool = false

    /// Flattened overlay points from all evaluated routes (for multi-route display).
    @Published var riskOverlayPoints: [RiskOverlayPoint] = []

    // MARK: - Configuration Constants

    private let sampleInterval: Double   = 200.0   // metres between polyline samples
    private let poiSearchRadius: Double  = 300.0   // metres for POI density check
    private let lightingRadius:  Double  = 200.0   // metres for lighting proxy check
    private let isolationThreshold       = 2       // POIs below this → isolated
    private let cacheLifetime: TimeInterval = 3600  // 1 hour
    private let maxConcurrentSearches    = 5

    // MARK: - Internal State

    /// Keyed by "lat,lon" string rounded to 3 decimal places (~111 m grid).
    private var poiCache: [String: POICacheEntry] = [:]

    // MARK: - Public API

    /// Evaluates one or more routes and populates `routeRiskScores` (sorted safest-first).
    func evaluateRoutes(_ routes: [MKRoute]) async {
        guard !routes.isEmpty else { return }
        isEvaluating = true
        defer { isEvaluating = false }

        var scores: [RouteRiskScore] = []
        for route in routes {
            let score = await evaluateSingleRoute(route)
            scores.append(score)
        }

        routeRiskScores   = scores.sorted { $0.overallRisk < $1.overallRisk }
        riskOverlayPoints = routeRiskScores.flatMap { $0.overlayPoints }
    }

    /// Convenience wrapper: returns routes sorted by ascending risk.
    func compareRoutes(_ routes: [MKRoute]) async -> [RouteRiskScore] {
        await evaluateRoutes(routes)
        return routeRiskScores
    }

    // MARK: - Single-Route Evaluation

    private func evaluateSingleRoute(_ route: MKRoute) async -> RouteRiskScore {
        let isWalking = route.transportType == .walking

        // 1. Sample the polyline
        let samplePoints = samplePolyline(route.polyline, interval: sampleInterval)

        // 2. Query POIs at each sample point (rate-limited, cached)
        var segmentResults: [(poiCount: Int, hasTrafficRoad: Bool)] = []
        await withTaskGroup(of: (index: Int, poiCount: Int, hasTrafficRoad: Bool).self) { group in
            let semaphore = AsyncSemaphore(limit: maxConcurrentSearches)
            for (idx, coord) in samplePoints.enumerated() {
                group.addTask {
                    await semaphore.wait()
                    let (count, traffic) = await self.fetchPOIData(near: coord)
                    await semaphore.signal()
                    return (idx, count, traffic)
                }
            }
            var indexed = [(index: Int, poiCount: Int, hasTrafficRoad: Bool)]()
            for await result in group { indexed.append(result) }
            segmentResults = indexed
                .sorted { $0.index < $1.index }
                .map { ($0.poiCount, $0.hasTrafficRoad) }
        }

        // 3. Compute per-segment risk and overlay points
        var overlayPoints: [RiskOverlayPoint] = []
        var isolatedSegmentCount = 0
        var poorLightingSegmentCount = 0
        var highTrafficBonus = 0

        for (idx, result) in segmentResults.enumerated() {
            let isIsolated = result.poiCount < isolationThreshold
            let hasPoorLighting = result.poiCount == 0
            if isIsolated { isolatedSegmentCount += 1 }
            if hasPoorLighting { poorLightingSegmentCount += 1 }
            if result.hasTrafficRoad { highTrafficBonus += 1 }

            // Per-segment risk for overlay colouring
            var segRisk = 0.0
            if isIsolated { segRisk += isWalking ? 0.35 : 0.20 }
            if hasPoorLighting { segRisk += 0.25 }
            if result.hasTrafficRoad { segRisk = max(0.0, segRisk - 0.15) }
            segRisk = min(1.0, segRisk)

            if idx < samplePoints.count {
                overlayPoints.append(
                    RiskOverlayPoint(
                        coordinate: samplePoints[idx],
                        riskLevel: RiskLevel(score: segRisk)
                    )
                )
            }
        }

        let totalSegments = max(1, segmentResults.count)

        // 4. Build factor list
        var factors: [RiskFactor] = []

        // Time-of-day factor
        let todRisk = timeOfDayRisk()
        factors.append(.timeOfDay(risk: todRisk))

        // Route length factor (0 at 0 km, caps at 0.4 for 10+ km)
        let lengthKm = route.distance / 1000.0
        let lengthRisk = min(0.4, lengthKm / 25.0)
        factors.append(.routeLength(risk: lengthRisk))

        // Isolation factor (fraction of isolated segments, walking gets 1.5× weight)
        let isolationFraction = Double(isolatedSegmentCount) / Double(totalSegments)
        let isolationRisk = min(1.0, isolationFraction * (isWalking ? 1.5 : 1.0))
        factors.append(.isolatedArea(risk: isolationRisk))

        // Poor lighting factor
        let lightingFraction = Double(poorLightingSegmentCount) / Double(totalSegments)
        let lightingRisk = min(1.0, lightingFraction)
        factors.append(.poorLighting(risk: lightingRisk))

        // High-traffic bonus (negative risk — improves safety, expressed as reduction)
        let trafficBonus = min(0.20, Double(highTrafficBonus) / Double(totalSegments) * 0.20)
        factors.append(.highTraffic(risk: trafficBonus))   // caller should subtract this

        // 5. Aggregate overall score
        //    Weighted sum; highTraffic is protective so subtracted.
        let weights: [Double] = [0.25, 0.15, 0.35, 0.20, 0.05]
        var weighted = 0.0
        for (factor, weight) in zip(factors, weights) {
            switch factor {
            case .highTraffic(let r): weighted -= r * weight
            default:                  weighted += factor.risk * weight
            }
        }
        // Apply time-of-day multiplier (night amplifies all other risks)
        let todMultiplier = 1.0 + todRisk            // 1.0 (day) … 1.3 (deep night)
        weighted *= todMultiplier
        let overallRisk = min(1.0, max(0.0, weighted))

        // 6. Generate safety tips
        let tips = generateSafetyTips(
            factors: factors,
            overlayPoints: overlayPoints,
            isWalking: isWalking,
            overallRisk: overallRisk
        )

        return RouteRiskScore(
            route: route,
            overallRisk: overallRisk,
            riskLevel: RiskLevel(score: overallRisk),
            factors: factors,
            safetyTips: tips,
            overlayPoints: overlayPoints
        )
    }

    // MARK: - Polyline Sampling

    /// Samples `polyline` at approximately `interval` metre spacing,
    /// returning an array of CLLocationCoordinate2D.
    private func samplePolyline(_ polyline: MKPolyline, interval: Double) -> [CLLocationCoordinate2D] {
        let pointCount = polyline.pointCount
        guard pointCount > 0 else { return [] }

        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                             count: pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))

        var samples: [CLLocationCoordinate2D] = [coords[0]]
        var distanceAccumulator = 0.0
        var previous = CLLocation(latitude: coords[0].latitude, longitude: coords[0].longitude)

        for i in 1..<pointCount {
            let current = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            distanceAccumulator += current.distance(from: previous)
            if distanceAccumulator >= interval {
                samples.append(coords[i])
                distanceAccumulator = 0.0
            }
            previous = current
        }

        // Always include the last point
        if let last = coords.last, samples.last.map({
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }) != nil {
            samples.append(last)
        }
        return samples
    }

    // MARK: - POI Fetching

    /// Returns (poiCount, hasHighTrafficRoad) for the area around `coordinate`.
    /// Results are cached for `cacheLifetime` seconds on a ~111 m grid.
    private func fetchPOIData(near coordinate: CLLocationCoordinate2D) async -> (Int, Bool) {
        let key = cacheKey(for: coordinate)

        // Check cache
        if let cached = poiCache[key], Date().timeIntervalSince(cached.timestamp) < cacheLifetime {
            return (cached.count, cached.hasHighTrafficRoad)
        }

        // POI categories that indicate a safe, populated environment
        let safetyCategories: [MKPointOfInterestCategory] = [
            .hospital, .police, .store, .restaurant,
            .pharmacy, .fireStation, .publicTransport
        ]

        var totalPOICount = 0
        var hasTrafficRoad = false

        // Search for safety POIs
        let poiRequest = MKLocalSearch.Request()
        poiRequest.naturalLanguageQuery = "store hospital police restaurant"
        poiRequest.pointOfInterestFilter = MKPointOfInterestFilter(including: safetyCategories)
        poiRequest.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: poiSearchRadius * 2,
            longitudinalMeters: poiSearchRadius * 2
        )

        do {
            let search = MKLocalSearch(request: poiRequest)
            let response = try await search.start()
            // Filter to items actually within the radius
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let nearby = response.mapItems.filter { item in
                guard let loc = item.placemark.location else { return false }
                return loc.distance(from: origin) <= poiSearchRadius
            }
            totalPOICount = nearby.count

            // Heuristic: if there are 5+ POIs within radius, assume well-trafficked road
            hasTrafficRoad = nearby.count >= 5
        } catch {
            // Search failed — treat as unknown (0 POIs, no traffic road)
        }

        let entry = POICacheEntry(count: totalPOICount, hasHighTrafficRoad: hasTrafficRoad, timestamp: Date())
        poiCache[key] = entry
        return (totalPOICount, hasTrafficRoad)
    }

    // MARK: - Time-of-Day Risk

    /// Returns a risk score based on the current hour:
    /// - 22:00–05:00 (night):       0.30
    /// - 05:00–07:00, 19:00–22:00:  0.15
    /// - 07:00–19:00 (day):         0.00
    private func timeOfDayRisk(date: Date = Date()) -> Double {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 22...23, 0...4:  return 0.30
        case 5...6, 19...21:  return 0.15
        default:              return 0.00
        }
    }

    // MARK: - Safety Tips Generation

    private func generateSafetyTips(
        factors: [RiskFactor],
        overlayPoints: [RiskOverlayPoint],
        isWalking: Bool,
        overallRisk: Double
    ) -> [String] {
        var tips: [String] = []

        for factor in factors {
            switch factor {
            case .timeOfDay(let r) where r >= 0.30:
                tips.append(NSLocalizedString(
                    "tip_night_travel",
                    comment: "Tip: traveling at night — consider sharing live location with a guardian"
                ))
                tips.append(NSLocalizedString(
                    "tip_well_lit_roads",
                    comment: "Tip: consider well-lit main roads"
                ))

            case .timeOfDay(let r) where r >= 0.15:
                tips.append(NSLocalizedString(
                    "tip_dusk_dawn",
                    comment: "Tip: dusk/dawn — stay on main roads and share your route"
                ))

            case .isolatedArea(let r) where r > 0.5:
                if isWalking {
                    tips.append(NSLocalizedString(
                        "tip_isolated_walking",
                        comment: "Tip: isolated route — consider a busier pedestrian path"
                    ))
                } else {
                    tips.append(NSLocalizedString(
                        "tip_isolated_driving",
                        comment: "Tip: isolated road — keep phone charged and fuel tank full"
                    ))
                }

            case .poorLighting(let r) where r > 0.3:
                tips.append(NSLocalizedString(
                    "tip_poor_lighting",
                    comment: "Tip: low commercial density on this route — carry a flashlight"
                ))

            case .routeLength(let r) where r > 0.25:
                tips.append(NSLocalizedString(
                    "tip_long_route",
                    comment: "Tip: long route — schedule a check-in reminder"
                ))

            case .highTraffic(let r) where r > 0.10:
                tips.append(NSLocalizedString(
                    "tip_high_traffic_safe",
                    comment: "Tip: busy roads detected on this route — they provide additional safety"
                ))

            default:
                break
            }
        }

        // Find the safest waypoint (lowest risk overlay point index) that has a POI nearby
        if let safePoint = overlayPoints.enumerated().min(by: { a, b in
            a.element.riskLevel.rawValue < b.element.riskLevel.rawValue
        }) {
            let index = safePoint.offset + 1   // 1-based for user display
            let tip = String(
                format: NSLocalizedString(
                    "tip_safe_waypoint",
                    comment: "Tip: police station / hospital nearby at waypoint %d"
                ),
                index
            )
            tips.append(tip)
        }

        if overallRisk < 0.25 {
            tips.append(NSLocalizedString(
                "tip_route_safe",
                comment: "Tip: this route looks safe — enjoy your journey"
            ))
        }

        return Array(Set(tips))   // deduplicate while preserving content
    }

    // MARK: - Cache Helpers

    /// Rounds lat/lon to 3 decimal places (~111 m grid) for cache bucketing.
    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude  * 1000).rounded() / 1000
        let lon = (coordinate.longitude * 1000).rounded() / 1000
        return "\(lat),\(lon)"
    }

    // MARK: - Cache Management

    /// Evicts all POI cache entries older than `cacheLifetime`.
    func evictExpiredCache() {
        let now = Date()
        poiCache = poiCache.filter { now.timeIntervalSince($0.value.timestamp) < cacheLifetime }
    }
}

// MARK: - AsyncSemaphore
//
// Lightweight Swift concurrency semaphore for bounding concurrent MKLocalSearch calls.

private actor AsyncSemaphore {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func wait() async {
        if active < limit {
            active += 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func signal() {
        if waiters.isEmpty {
            active -= 1
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}
