import Foundation

// MARK: - Claim Material Models
//
// Models for the insurance claim materials organizer.
// Lantern Care only provides reference data — no proofs, no certifications.

// MARK: - Insurance Types

enum InsuranceType: String, CaseIterable, Identifiable, Codable {
    case overseasMedical = "overseas_medical"
    case accidentalInjury = "accidental_injury"
    case theft = "theft"
    case flightDelay = "flight_delay"
    case lostLuggage = "lost_luggage"
    case trafficAccident = "traffic_accident"

    var id: String { rawValue }

    var displayName: String { LanguageManager.shared.localized("claim.type.\(rawValue)") }

    var icon: String {
        switch self {
        case .overseasMedical: return "cross.case.fill"
        case .accidentalInjury: return "figure.fall"
        case .theft: return "lock.slash.fill"
        case .flightDelay: return "airplane.departure"
        case .lostLuggage: return "suitcase.fill"
        case .trafficAccident: return "car.fill"
        }
    }

    /// What the insurer typically requires (third-party documents)
    var insurerRequires: [String] { lines("claim.requires.\(rawValue)") }

    /// What Lantern Care device records may contain
    var velaCanProvide: [String] { lines("claim.provides.\(rawValue)") }

    private func lines(_ key: String) -> [String] {
        LanguageManager.shared.localized(key).components(separatedBy: "\n")
    }
}

// MARK: - Request / Response

struct ClaimMaterialRequest: Codable {
    let incidentDate: Date
    let windowHours: Int
    let description: String?
    let insuranceType: String?
    let policyNumber: String?
    let includeSOS: Bool
    let includeCheckIns: Bool
    let includeTimeline: Bool
    let includeLocation: Bool
    let includeMedicalCard: Bool
}

struct ClaimMaterialExport: Codable {
    let exportId: String
    let personName: String
    let exportedAt: Date
    let incidentDate: Date
    let window: ExportTimeWindow
    let sosEvents: [SOSRecordItem]?
    let checkIns: [CheckInRecordItem]?
    let timeline: [TimelineRecordItem]?
    let medicalSnapshot: MedicalSnapshot?
    let contentHash: String
    let disclaimer: String
}

struct ExportTimeWindow: Codable {
    let start: Date
    let end: Date
}

struct SOSRecordItem: Codable, Identifiable {
    var id: String { triggeredAt }
    let triggeredAt: String
    let triggerMethod: String?
    let resolution: String?
    let latitude: Double?
    let longitude: Double?
}

struct CheckInRecordItem: Codable, Identifiable {
    var id: String { timestamp }
    let timestamp: String
    let latitude: Double?
    let longitude: Double?
    let note: String?
}

struct TimelineRecordItem: Codable, Identifiable {
    var id: String { timestamp + (description ?? "") }
    let timestamp: String
    let type: String?
    let description: String?
}

struct MedicalSnapshot: Codable {
    let bloodType: String?
    let allergies: [String]?
    let conditions: [String]?
    let insuranceProvider: String?
    let policyNumber: String?
}

// MARK: - Export History

struct ClaimExportSummary: Codable, Identifiable {
    let exportId: String
    let incidentDate: Date
    let exportedAt: Date
    let insuranceType: String?

    var id: String { exportId }
}

// MARK: - Disclaimer

enum ClaimDisclaimer {
    private static func l(_ key: String) -> String { LanguageManager.shared.localized("claim.disclaimer.\(key)") }

    static var full: String { l("full") }

    static var pdfHeader: String { l("pdfHeader") }

    static var checklistNote: String { l("checklistNote") }

    static var limitations: [String] { l("limitations").components(separatedBy: "\n") }
}
