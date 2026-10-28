import Foundation
import CoreLocation

struct TripRecord: Codable, Identifiable {
    let id: String
    let userId: String
    var status: TripStatus
    let startTime: Date
    var endTime: Date?
    var totalDistanceMeters: Double
    var pointCount: Int
    var segments: [TripSegment]

    enum TripStatus: String, Codable {
        case recording
        case completed
        case cancelled
    }

    struct TripSegment: Codable {
        let startTime: Date
        let endTime: Date
        let transportMode: String  // walking, driving, cycling, stationary
        let distanceMeters: Double
        let pointCount: Int
    }
}

struct TripPoint: Codable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let altitude: Double?
    let speed: Double?
    let timestamp: Date
    let activityType: String?
}

// Response types for API
struct TripListResponse: Codable {
    let trips: [TripSummary]
}

struct TripSummary: Codable, Identifiable {
    let id: String
    let userId: String
    let status: String
    let startTime: String
    let endTime: String?
    let totalDistanceMeters: Double
    let pointCount: Int
    let durationSeconds: Double
    let primaryTransportMode: String?
}

struct TripDetailResponse: Codable {
    let trip: TripSummary
    let points: [TripPoint]
    let segments: [TripRecord.TripSegment]
}

struct TripStartResponse: Codable {
    let tripId: String
    let startTime: String
}

struct TripEndResponse: Codable {
    let tripId: String
    let totalDistanceMeters: Double
    let pointCount: Int
    let durationSeconds: Double
}
