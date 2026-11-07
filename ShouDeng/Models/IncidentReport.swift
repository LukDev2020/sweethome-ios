import Foundation
import CoreLocation

// MARK: - Incident report for police (docs/police-incident-report.md)
//
// What POST /v1/incident-reports returns. `canonical` is the server's data, already
// hashed (dataSha256): it is saved as data.json byte for byte and decoded into
// IncidentReportData only to draw the PDF and maps. Times stay ISO strings.

enum IncidentReportPurpose: String, CaseIterable, Codable, Identifiable {
    case missingPerson = "missing_person"
    case assault
    case accident
    case harassment
    case other
    var id: String { rawValue }
    var titleKey: String { "report.purpose.\(rawValue)" }
}

enum IncidentReportSection: String, CaseIterable, Codable, Identifiable {
    case locations, activity, falls, sos, checkins, events, device
    var id: String { rawValue }
    var titleKey: String { "report.section.\(rawValue)" }
}

struct IncidentReportRequest: Encodable {
    let personId: String
    let windowStart: Date
    let windowEnd: Date
    let purpose: String
    let caseNumber: String?
    let sections: [String]
}

struct IncidentReportCreated: Decodable {
    let reportId: String
    let verifyCode: String
    let dataSha256: String
    let verifyUrl: String?
    let canonical: String
}

struct IncidentReportSealRequest: Encodable {
    let files: [String: String]
}

struct IncidentReportListResponse: Decodable {
    let reports: [IncidentReportSummary]
}

struct IncidentReportSummary: Decodable, Identifiable {
    let reportId: String
    let createdAt: String?
    let createdBy: String?
    let createdBySelf: Bool?
    let purpose: String?
    let windowStart: String?
    let windowEnd: String?
    let sealed: Bool?
    var id: String { reportId }
}

/// The canonical data (see services/incidentReport.ts gatherReportData).
struct IncidentReportData: Decodable {
    struct Person: Decodable { let id: String; let name: String?; let phone: String?; let timeZone: String? }
    struct Reporter: Decodable { let id: String; let name: String?; let role: String }
    struct Window: Decodable { let start: String; let end: String }
    struct Point: Decodable {
        let at: String
        let latitude: Double
        let longitude: Double
        let accuracy: Double?
        let speed: Double?
        let altitude: Double?
        let activity: String?
        let source: String
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }
    struct Segment: Decodable { let activity: String; let start: String; let end: String; let distanceMeters: Double; let points: Int }
    struct Gap: Decodable { let from: String; let to: String; let minutes: Int }
    struct Metrics: Decodable {
        let peakImpactG: Double?
        let freeFallMs: Double?
        let orientationChangeDeg: Double?
        let stillnessVariance: Double?
        let detector: String?
    }
    struct Fall: Decodable {
        let detectedAt: String?
        let latitude: Double?
        let longitude: Double?
        let accuracy: Double?
        let batteryLevel: Double?
        let metrics: Metrics?
        let outcome: String?
        let respondedAfterSec: Double?
        let sosEventId: String?
    }
    struct TrailPoint: Decodable { let latitude: Double; let longitude: Double; let at: String }
    struct SOS: Decodable {
        let id: String
        let triggeredAt: String?
        let triggerMethod: String?
        let latitude: Double?
        let longitude: Double?
        let batteryLevel: Double?
        let escalationState: String?
        let acknowledgedBy: String?
        let acknowledgedAt: String?
        let resolvedAt: String?
        let resolution: String?
        let trail: [TrailPoint]?
    }
    struct CheckIn: Decodable { let at: String?; let latitude: Double?; let longitude: Double?; let note: String? }
    struct Event: Decodable { let at: String?; let type: String; let description: String }
    struct Battery: Decodable { let at: String; let level: Double?; let state: String? }
    struct Counts: Decodable { let points: Int; let sos: Int; let falls: Int; let checkins: Int }
    struct Summary: Decodable {
        let lastKnown: Point?
        let lastCheckIn: CheckIn?
        let lastBattery: Battery?
        let counts: Counts
        let thinned: Bool?
    }

    let reportId: String
    let verifyCode: String
    let generatedAt: String
    let purpose: String
    let caseNumber: String?
    let sections: [String]
    let reporter: Reporter
    let person: Person
    let window: Window
    let sources: [String: String]
    let summary: Summary
    let locations: [Point]
    let activity: [Segment]
    let gaps: [Gap]
    let falls: [Fall]
    let sos: [SOS]
    let checkins: [CheckIn]
    let events: [Event]
    let battery: [Battery]
}

enum ReportTime {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFraction = ISO8601DateFormatter()

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoNoFraction.date(from: s)
    }

    static func string(_ d: Date) -> String { iso.string(from: d) }
}
