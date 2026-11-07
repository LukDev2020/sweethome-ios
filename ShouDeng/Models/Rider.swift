import Foundation
import CoreLocation

// MARK: - Rider mode (delivery / rideshare riders)
//
// A protected person who rides for work turns on Rider mode (Settings → Home screen).
// They work in shifts and look out for other riders in a small invite-only crew: an
// SOS alerts the crew nearest first, alongside their guardians. Server: /v1/crew.

struct Crew: Codable, Equatable {
    let id: String
    let name: String
    let inviteCode: String
    let isOwner: Bool
    let members: [CrewMember]
    let cautions: [CrewCaution]
    /// Who watches my shifts (crew mates and guardians); the next shift starts with them
    var myWatcherIds: [String]? = nil

    /// Joining link shown as a QR code (the app opens it and fills in the code)
    var inviteURL: URL { URL(string: "shoudeng://crew/join?code=\(inviteCode)")! }
}

struct CrewMember: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let initial: String
    let onShift: Bool
    let latitude: Double?
    let longitude: Double?
    let locationAt: Date?
    let distanceM: Int?
    /// They watch my shifts / I watch theirs
    var watchesMe: Bool? = nil
    var iWatch: Bool? = nil

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct CrewCaution: Codable, Identifiable, Equatable {
    let id: String
    let latitude: Double
    let longitude: Double
    let note: String
    let createdAt: Date?
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

struct CrewResponseEntry: Codable, Identifiable, Equatable {
    let memberId: String
    let name: String
    let response: String   // "going" | "cant_help"
    let at: Date?
    let distanceM: Int?
    var id: String { memberId }
    var isGoing: Bool { response == "going" }
}

/// A crew mate's open SOS, as the crew sees it.
struct CrewAlert: Codable, Identifiable, Equatable {
    let sosEventId: String
    let riderId: String
    let riderName: String
    let triggeredAt: Date?
    let latitude: Double?
    let longitude: Double?
    let distanceM: Int?
    let myResponse: String?
    let responses: [CrewResponseEntry]
    var id: String { sosEventId }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct CrewEnvelope: Decodable { let crew: Crew? }
struct CrewAlertsEnvelope: Decodable { let alerts: [CrewAlert] }

/// The rider's current shift (kept on the phone; the server knows on/off and the planned end).
struct RiderShift: Codable, Equatable {
    let startedAt: Date
    let plannedEnd: Date?
    /// Crew mates and family watching this shift
    var watcherIds: [String]? = nil
}

enum RiderFormat {
    /// "220 m" / "1.2 km"
    static func distance(_ meters: Int?) -> String? {
        guard let meters else { return nil }
        return meters >= 1000 ? String(format: "%.1f km", Double(meters) / 1000) : "\(max(10, (meters / 10) * 10)) m"
    }

    /// Police assistance (non-emergency) line, where we know it
    static func policeAssistanceNumber(country: String) -> String? {
        switch country.uppercased() {
        case "AU": return "131444"
        case "GB": return "101"
        case "NZ": return "105"
        default: return nil
        }
    }
}

// MARK: - Family watch back
//
// The person being cared for can look after their guardian too (the guardian agrees).
// Covered by the carer's plan — it takes no household seat. Server: /v1/watch-back.

struct WatchBackEntry: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    /// "none" | "pending" | "active"
    let state: String
}

struct WatchBackOverview: Codable, Equatable {
    /// My guardians and whether I watch them back
    let guardians: [WatchBackEntry]
    /// People I look after and whether they watch me back
    let people: [WatchBackEntry]
}

struct WatchBackStateResponse: Decodable { let state: String? }
