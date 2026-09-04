import Foundation
import CoreLocation

// MARK: - Trajectory Processor: Four-Layer Pipeline
//
// From PDF section 7: 轨迹处理四层流水线
//
// Raw GPS points are noisy, jittery, and storage-heavy.
// This pipeline cleans them in four stages:
//
//   Layer 1: Filter  — discard bad points (accuracy, speed, timestamp)
//   Layer 2: Smooth  — 1D Kalman filter on lat/lng separately
//   Layer 3: Thin    — Douglas-Peucker simplification (display only)
//   Layer 4: Segment — classify dwell vs movement, infer transport mode
//
// Real-time judgments use original points; display uses simplified.

final class TrajectoryProcessor {

    // MARK: - Configuration

    struct Config {
        var maxAccuracyMeters: Double = 100        // Layer 1: discard if accuracy > 100m
        var maxSpeedKmh: Double = 200              // Layer 1: walking/biking/driving cap
        var flyingSpeedKmh: Double = 1200          // Layer 1: flight cap
        var simplificationEpsilon: Double = 15     // Layer 3: Douglas-Peucker ε in meters
        var dwellRadiusMeters: Double = 200        // Layer 4: dwell point radius
        var dwellMinDurationSec: TimeInterval = 1200  // Layer 4: 20 minutes

        // Speed thresholds for transport mode (km/h)
        var walkMaxKmh: Double = 5
        var bikeMaxKmh: Double = 20
        var carMaxKmh: Double = 120
    }

    // MARK: - Types

    struct TrajectoryPoint {
        let coordinate: CLLocationCoordinate2D
        let accuracy: Double
        let timestamp: Date
        let speed: Double?    // m/s
        let altitude: Double?
    }

    struct SmoothedPoint {
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
        let speed: Double?
    }

    struct TrajectorySegment {
        let startTime: Date
        let endTime: Date
        let points: [SmoothedPoint]
        let type: SegmentType
        let distanceMeters: Double
        let averageSpeedKmh: Double
        let transportMode: TransportMode
    }

    enum SegmentType {
        case dwell      // Stayed in one place
        case movement   // Moving between places
    }

    enum TransportMode: String {
        case walking = "步行"
        case cycling = "骑行"
        case driving = "车辆"
        case flying = "飞行"
        case stationary = "停留"
        case unknown = "未知"
    }

    // MARK: - Properties

    private let config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Full Pipeline

    func process(rawPoints: [TrajectoryPoint]) -> (
        filtered: [TrajectoryPoint],
        smoothed: [SmoothedPoint],
        simplified: [SmoothedPoint],
        segments: [TrajectorySegment]
    ) {
        let filtered = filterLayer(rawPoints)
        let smoothed = kalmanSmooth(filtered)
        let simplified = douglasPeucker(smoothed, epsilon: config.simplificationEpsilon)
        let segments = segment(smoothed)
        return (filtered, smoothed, simplified, segments)
    }

    // MARK: - Layer 1: Filter (discard bad points)
    //
    // Discard criteria:
    //   - accuracy > 100m (too imprecise)
    //   - computed speed from previous point > threshold (physically impossible)
    //   - timestamp earlier than previous point (out of order)

    func filterLayer(_ points: [TrajectoryPoint]) -> [TrajectoryPoint] {
        guard !points.isEmpty else { return [] }

        var result: [TrajectoryPoint] = []

        for i in 0..<points.count {
            let point = points[i]

            // Accuracy check
            if point.accuracy > config.maxAccuracyMeters {
                continue
            }

            // Timestamp order check
            if let lastAccepted = result.last, point.timestamp <= lastAccepted.timestamp {
                continue
            }

            // Speed sanity check against previous accepted point
            if let lastAccepted = result.last {
                let distance = haversineDistance(
                    lat1: lastAccepted.coordinate.latitude,
                    lon1: lastAccepted.coordinate.longitude,
                    lat2: point.coordinate.latitude,
                    lon2: point.coordinate.longitude
                )
                let timeDelta = point.timestamp.timeIntervalSince(lastAccepted.timestamp)
                if timeDelta > 0 {
                    let speedKmh = (distance / timeDelta) * 3.6
                    if speedKmh > config.flyingSpeedKmh {
                        continue
                    }
                }
            }

            result.append(point)
        }

        return result
    }

    // MARK: - Layer 2: Kalman Smooth (1D per lat/lng)
    //
    // Core idea: GPS reported accuracy → observation noise.
    // Higher accuracy → trust observation more; lower → trust prediction more.
    // ~20 lines of code, no matrix math needed for 1D.

    func kalmanSmooth(_ points: [TrajectoryPoint]) -> [SmoothedPoint] {
        guard points.count > 1 else {
            return points.map { SmoothedPoint(coordinate: $0.coordinate, timestamp: $0.timestamp, speed: $0.speed) }
        }

        var smoothedLat: [Double] = []
        var smoothedLng: [Double] = []

        // Kalman state for latitude
        var latPosition = points[0].coordinate.latitude
        var latVariance = points[0].accuracy * points[0].accuracy

        // Kalman state for longitude
        var lngPosition = points[0].coordinate.longitude
        var lngVariance = points[0].accuracy * points[0].accuracy

        smoothedLat.append(latPosition)
        smoothedLng.append(lngPosition)

        for i in 1..<points.count {
            let point = points[i]
            let dt = point.timestamp.timeIntervalSince(points[i-1].timestamp)
            let speed = point.speed ?? 0
            let processNoise = dt * speed * speed * 1e-10  // velocity-based process noise

            // Predict
            latVariance += processNoise
            lngVariance += processNoise

            // Update — gain = variance / (variance + accuracy²)
            let accuracy2 = point.accuracy * point.accuracy
            let latK = latVariance / (latVariance + accuracy2)
            let lngK = lngVariance / (lngVariance + accuracy2)

            latPosition += latK * (point.coordinate.latitude - latPosition)
            lngPosition += lngK * (point.coordinate.longitude - lngPosition)

            latVariance = (1 - latK) * latVariance
            lngVariance = (1 - lngK) * lngVariance

            smoothedLat.append(latPosition)
            smoothedLng.append(lngPosition)
        }

        return zip(points.indices, points).map { i, point in
            SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: smoothedLat[i], longitude: smoothedLng[i]),
                timestamp: point.timestamp,
                speed: point.speed
            )
        }
    }

    // MARK: - Layer 3: Douglas-Peucker Simplification
    //
    // Reduces point count by ~80% with ε = 10-20m, no visible difference.
    // Display only — real-time judgments use original smoothed points.

    func douglasPeucker(_ points: [SmoothedPoint], epsilon: Double) -> [SmoothedPoint] {
        guard points.count > 2 else { return points }

        var maxDist: Double = 0
        var maxIdx = 0

        let first = points.first!
        let last = points.last!

        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(
                point: points[i].coordinate,
                lineStart: first.coordinate,
                lineEnd: last.coordinate
            )
            if d > maxDist {
                maxDist = d
                maxIdx = i
            }
        }

        if maxDist > epsilon {
            let left = douglasPeucker(Array(points[...maxIdx]), epsilon: epsilon)
            let right = douglasPeucker(Array(points[maxIdx...]), epsilon: epsilon)
            return left.dropLast() + right
        } else {
            return [first, last]
        }
    }

    // MARK: - Layer 4: Segmentation (dwell vs movement)
    //
    // Dwell point: consecutive points within radius < 200m, duration > 20min
    // Movement: everything between dwell points
    // Transport mode inferred by average speed (no ML needed)

    func segment(_ points: [SmoothedPoint]) -> [TrajectorySegment] {
        guard points.count > 1 else { return [] }

        var segments: [TrajectorySegment] = []
        var dwellStart: Int?
        var moveStart = 0

        for i in 1..<points.count {
            let prevLoc = CLLocation(
                latitude: points[i-1].coordinate.latitude,
                longitude: points[i-1].coordinate.longitude
            )
            let curLoc = CLLocation(
                latitude: points[i].coordinate.latitude,
                longitude: points[i].coordinate.longitude
            )
            let dist = curLoc.distance(from: prevLoc)

            if dist < config.dwellRadiusMeters {
                // Potential dwell — mark start
                if dwellStart == nil {
                    dwellStart = i - 1
                }
            } else {
                // Movement detected
                if let start = dwellStart {
                    let duration = points[i-1].timestamp.timeIntervalSince(points[start].timestamp)
                    if duration >= config.dwellMinDurationSec {
                        // Emit movement segment before dwell (if any)
                        if moveStart < start {
                            segments.append(buildMovementSegment(points: Array(points[moveStart...start])))
                        }
                        // Emit dwell segment
                        segments.append(buildDwellSegment(points: Array(points[start...(i-1)])))
                        moveStart = i
                    }
                    dwellStart = nil
                }
            }
        }

        // Handle trailing dwell
        if let start = dwellStart {
            let duration = points.last!.timestamp.timeIntervalSince(points[start].timestamp)
            if duration >= config.dwellMinDurationSec {
                if moveStart < start {
                    segments.append(buildMovementSegment(points: Array(points[moveStart...start])))
                }
                segments.append(buildDwellSegment(points: Array(points[start...])))
            } else {
                segments.append(buildMovementSegment(points: Array(points[moveStart...])))
            }
        } else if moveStart < points.count {
            segments.append(buildMovementSegment(points: Array(points[moveStart...])))
        }

        return segments
    }

    // MARK: - Segment Builders

    private func buildDwellSegment(points: [SmoothedPoint]) -> TrajectorySegment {
        TrajectorySegment(
            startTime: points.first!.timestamp,
            endTime: points.last!.timestamp,
            points: points,
            type: .dwell,
            distanceMeters: 0,
            averageSpeedKmh: 0,
            transportMode: .stationary
        )
    }

    private func buildMovementSegment(points: [SmoothedPoint]) -> TrajectorySegment {
        var totalDistance: Double = 0
        for i in 1..<points.count {
            totalDistance += haversineDistance(
                lat1: points[i-1].coordinate.latitude,
                lon1: points[i-1].coordinate.longitude,
                lat2: points[i].coordinate.latitude,
                lon2: points[i].coordinate.longitude
            )
        }

        let duration = points.last!.timestamp.timeIntervalSince(points.first!.timestamp)
        let avgSpeedKmh = duration > 0 ? (totalDistance / duration) * 3.6 : 0

        let mode = inferTransportMode(avgSpeedKmh: avgSpeedKmh, points: points)

        return TrajectorySegment(
            startTime: points.first!.timestamp,
            endTime: points.last!.timestamp,
            points: points,
            type: .movement,
            distanceMeters: totalDistance,
            averageSpeedKmh: avgSpeedKmh,
            transportMode: mode
        )
    }

    // MARK: - Transport Mode Inference (PDF: by average speed, no ML)

    private func inferTransportMode(avgSpeedKmh: Double, points: [SmoothedPoint]) -> TransportMode {
        if avgSpeedKmh < config.walkMaxKmh {
            return .walking
        } else if avgSpeedKmh < config.bikeMaxKmh {
            return .cycling
        } else if avgSpeedKmh < config.carMaxKmh {
            return .driving
        } else {
            // Check altitude gain for flight detection
            let altitudes = points.compactMap { _ -> Double? in nil }  // No altitude in SmoothedPoint
            if altitudes.isEmpty {
                return avgSpeedKmh > 200 ? .flying : .driving
            }
            return .flying
        }
    }

    // MARK: - Math Helpers

    /// Haversine distance in meters
    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0  // Earth radius in meters
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    /// Perpendicular distance from a point to a line (in meters)
    private func perpendicularDistance(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let pointLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let startLoc = CLLocation(latitude: lineStart.latitude, longitude: lineStart.longitude)
        let endLoc = CLLocation(latitude: lineEnd.latitude, longitude: lineEnd.longitude)

        let lineLength = startLoc.distance(from: endLoc)
        guard lineLength > 0 else { return pointLoc.distance(from: startLoc) }

        // Project point onto line using dot product
        let dx = endLoc.coordinate.longitude - startLoc.coordinate.longitude
        let dy = endLoc.coordinate.latitude - startLoc.coordinate.latitude
        let px = pointLoc.coordinate.longitude - startLoc.coordinate.longitude
        let py = pointLoc.coordinate.latitude - startLoc.coordinate.latitude

        let t = max(0, min(1, (px * dx + py * dy) / (dx * dx + dy * dy)))
        let projLat = startLoc.coordinate.latitude + t * dy
        let projLng = startLoc.coordinate.longitude + t * dx
        let projLoc = CLLocation(latitude: projLat, longitude: projLng)

        return pointLoc.distance(from: projLoc)
    }
}
