import Foundation

// MARK: - Claim Material Models
//
// Models for the insurance claim materials organizer.
// Vela only provides reference data — no proofs, no certifications.

// MARK: - Insurance Types

enum InsuranceType: String, CaseIterable, Identifiable, Codable {
    case overseasMedical = "overseas_medical"
    case accidentalInjury = "accidental_injury"
    case theft = "theft"
    case flightDelay = "flight_delay"
    case lostLuggage = "lost_luggage"
    case trafficAccident = "traffic_accident"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overseasMedical: return "境外医疗"
        case .accidentalInjury: return "意外伤残"
        case .theft: return "盗抢"
        case .flightDelay: return "航班延误"
        case .lostLuggage: return "行李丢失"
        case .trafficAccident: return "交通事故"
        }
    }

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
    var insurerRequires: [String] {
        switch self {
        case .overseasMedical:
            return ["医疗机构病历", "诊断证明", "费用原始凭证"]
        case .accidentalInjury:
            return ["意外事故证明", "认可机构伤残鉴定书"]
        case .theft:
            return ["警方报案证明"]
        case .flightDelay:
            return ["航空公司盖章的延误书面证明"]
        case .lostLuggage:
            return ["航空公司行李异常报告 (PIR)", "物品清单与票据"]
        case .trafficAccident:
            return ["使领馆或当地政府机构的事故证明"]
        }
    }

    /// What Vela device records may contain
    var velaCanProvide: [String] {
        switch self {
        case .overseasMedical:
            return ["事发时间地点记录", "跌倒或 SOS 记录", "就医前后轨迹"]
        case .accidentalInjury:
            return ["事故时刻与位置的独立记录"]
        case .theft:
            return ["事发时间线", "现场照片及拍摄时间"]
        case .flightDelay:
            return ["共享行程中的航班号与实际起落时间"]
        case .lostLuggage:
            return ["行程记录", "附件拍照时间"]
        case .trafficAccident:
            return ["使领馆联系记录", "事发位置"]
        }
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
    static let full = "本导出内容来源于用户设备记录与守灯服务器日志，仅供用户自行参考使用。守灯不对记录的准确性、完整性或适用性作任何明示或暗示的保证，不对使用本内容产生的任何后果承担责任。"

    static let pdfHeader = "本文件由守灯 App 自动导出，内容为用户设备记录，仅供参考，不构成任何证明或法律文件。"

    static let checklistNote = "此清单仅供参考，具体要求以您的保险合同为准。"

    static let limitations: [String] = [
        "定位精度受设备硬件与环境影响，坐标可能存在偏差",
        "记录时间基于设备时钟，未经第三方时间戳机构认证",
        "本内容不能替代医疗机构、警方、航空公司等出具的正式文件",
        "用户可在导出前选择包含或排除特定记录",
    ]
}
