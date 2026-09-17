import XCTest
@testable import ShouDeng

final class ClaimMaterialTests: XCTestCase {

    // MARK: - InsuranceType

    func testAllInsuranceTypesExist() {
        let types = InsuranceType.allCases
        XCTAssertEqual(types.count, 6)
    }

    func testInsuranceTypeRawValues() {
        XCTAssertEqual(InsuranceType.overseasMedical.rawValue, "overseas_medical")
        XCTAssertEqual(InsuranceType.accidentalInjury.rawValue, "accidental_injury")
        XCTAssertEqual(InsuranceType.theft.rawValue, "theft")
        XCTAssertEqual(InsuranceType.flightDelay.rawValue, "flight_delay")
        XCTAssertEqual(InsuranceType.lostLuggage.rawValue, "lost_luggage")
        XCTAssertEqual(InsuranceType.trafficAccident.rawValue, "traffic_accident")
    }

    func testInsuranceTypeDisplayNames() {
        XCTAssertEqual(InsuranceType.overseasMedical.displayName, "境外医疗")
        XCTAssertEqual(InsuranceType.theft.displayName, "盗抢")
        XCTAssertEqual(InsuranceType.flightDelay.displayName, "航班延误")
    }

    func testInsuranceTypeIcons() {
        for type in InsuranceType.allCases {
            XCTAssertFalse(type.icon.isEmpty, "\(type) should have an icon")
        }
    }

    func testInsuranceTypeInsurerRequiresNotEmpty() {
        for type in InsuranceType.allCases {
            XCTAssertFalse(type.insurerRequires.isEmpty, "\(type) should have insurer requirements")
        }
    }

    func testInsuranceTypeVelaCanProvideNotEmpty() {
        for type in InsuranceType.allCases {
            XCTAssertFalse(type.velaCanProvide.isEmpty, "\(type) should have Vela records")
        }
    }

    func testInsuranceTypeIdentifiable() {
        let type = InsuranceType.overseasMedical
        XCTAssertEqual(type.id, "overseas_medical")
    }

    func testInsuranceTypeCodableRoundTrip() {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for type in InsuranceType.allCases {
            let data = try! encoder.encode(type)
            let decoded = try! decoder.decode(InsuranceType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }

    // MARK: - ClaimMaterialRequest

    func testClaimMaterialRequestEncoding() {
        let request = ClaimMaterialRequest(
            incidentDate: Date(timeIntervalSinceReferenceDate: 1000),
            windowHours: 24,
            description: "Test incident",
            insuranceType: "overseas_medical",
            policyNumber: "PA-2026-001",
            includeSOS: true,
            includeCheckIns: true,
            includeTimeline: false,
            includeLocation: true,
            includeMedicalCard: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(request)
        let dict = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["windowHours"] as? Int, 24)
        XCTAssertEqual(dict["description"] as? String, "Test incident")
        XCTAssertEqual(dict["insuranceType"] as? String, "overseas_medical")
        XCTAssertEqual(dict["policyNumber"] as? String, "PA-2026-001")
        XCTAssertEqual(dict["includeSOS"] as? Bool, true)
        XCTAssertEqual(dict["includeCheckIns"] as? Bool, true)
        XCTAssertEqual(dict["includeTimeline"] as? Bool, false)
        XCTAssertEqual(dict["includeLocation"] as? Bool, true)
        XCTAssertEqual(dict["includeMedicalCard"] as? Bool, false)
    }

    func testClaimMaterialRequestWithNilOptionals() {
        let request = ClaimMaterialRequest(
            incidentDate: Date(),
            windowHours: 12,
            description: nil,
            insuranceType: nil,
            policyNumber: nil,
            includeSOS: false,
            includeCheckIns: false,
            includeTimeline: false,
            includeLocation: false,
            includeMedicalCard: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertNoThrow(try encoder.encode(request))
    }

    // MARK: - ClaimMaterialExport

    func testClaimMaterialExportDecoding() {
        let json = """
        {
            "exportId": "EXP-ABC123-1695000000000",
            "personName": "张三",
            "exportedAt": "2026-09-17T12:00:00Z",
            "incidentDate": "2026-09-17T10:00:00Z",
            "window": {
                "start": "2026-09-16T10:00:00Z",
                "end": "2026-09-18T10:00:00Z"
            },
            "sosEvents": [
                {
                    "triggeredAt": "2026-09-17T10:05:00Z",
                    "triggerMethod": "longPress",
                    "resolution": null,
                    "latitude": 40.7128,
                    "longitude": -74.0060
                }
            ],
            "checkIns": [
                {
                    "timestamp": "2026-09-17T08:00:00Z",
                    "latitude": 40.7128,
                    "longitude": -74.0060,
                    "note": "在学校"
                }
            ],
            "timeline": [
                {
                    "timestamp": "2026-09-17T09:00:00Z",
                    "type": "checkIn",
                    "description": "报平安"
                }
            ],
            "medicalSnapshot": {
                "bloodType": "A+",
                "allergies": ["青霉素"],
                "conditions": null,
                "insuranceProvider": "平安保险",
                "policyNumber": "PA-001"
            },
            "contentHash": "abc123def456",
            "disclaimer": "仅供参考"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let export = try! decoder.decode(ClaimMaterialExport.self, from: json)

        XCTAssertEqual(export.exportId, "EXP-ABC123-1695000000000")
        XCTAssertEqual(export.personName, "张三")
        XCTAssertEqual(export.contentHash, "abc123def456")

        // SOS events
        XCTAssertEqual(export.sosEvents?.count, 1)
        XCTAssertEqual(export.sosEvents?.first?.triggerMethod, "longPress")
        XCTAssertEqual(export.sosEvents?.first?.latitude ?? 0, 40.7128, accuracy: 0.0001)

        // Check-ins
        XCTAssertEqual(export.checkIns?.count, 1)
        XCTAssertEqual(export.checkIns?.first?.note, "在学校")

        // Timeline
        XCTAssertEqual(export.timeline?.count, 1)
        XCTAssertEqual(export.timeline?.first?.description, "报平安")

        // Medical snapshot
        XCTAssertEqual(export.medicalSnapshot?.bloodType, "A+")
        XCTAssertEqual(export.medicalSnapshot?.allergies, ["青霉素"])
        XCTAssertNil(export.medicalSnapshot?.conditions)
        XCTAssertEqual(export.medicalSnapshot?.insuranceProvider, "平安保险")
    }

    func testClaimMaterialExportDecodingWithNulls() {
        let json = """
        {
            "exportId": "EXP-MIN-001",
            "personName": "用户",
            "exportedAt": "2026-09-17T12:00:00Z",
            "incidentDate": "2026-09-17T10:00:00Z",
            "window": {
                "start": "2026-09-16T10:00:00Z",
                "end": "2026-09-18T10:00:00Z"
            },
            "sosEvents": null,
            "checkIns": null,
            "timeline": null,
            "medicalSnapshot": null,
            "contentHash": "000",
            "disclaimer": "仅供参考"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let export = try! decoder.decode(ClaimMaterialExport.self, from: json)
        XCTAssertNil(export.sosEvents)
        XCTAssertNil(export.checkIns)
        XCTAssertNil(export.timeline)
        XCTAssertNil(export.medicalSnapshot)
    }

    // MARK: - Record Item Identifiable

    func testSOSRecordItemId() {
        let item = SOSRecordItem(
            triggeredAt: "2026-09-17T10:00:00Z",
            triggerMethod: "longPress",
            resolution: nil,
            latitude: nil,
            longitude: nil
        )
        XCTAssertEqual(item.id, "2026-09-17T10:00:00Z")
    }

    func testCheckInRecordItemId() {
        let item = CheckInRecordItem(
            timestamp: "2026-09-17T08:00:00Z",
            latitude: 40.0,
            longitude: 116.0,
            note: "test"
        )
        XCTAssertEqual(item.id, "2026-09-17T08:00:00Z")
    }

    func testTimelineRecordItemId() {
        let item = TimelineRecordItem(
            timestamp: "2026-09-17T09:00:00Z",
            type: "checkIn",
            description: "报平安"
        )
        XCTAssertEqual(item.id, "2026-09-17T09:00:00Z报平安")
    }

    func testTimelineRecordItemIdWithNilDescription() {
        let item = TimelineRecordItem(
            timestamp: "2026-09-17T09:00:00Z",
            type: nil,
            description: nil
        )
        XCTAssertEqual(item.id, "2026-09-17T09:00:00Z")
    }

    // MARK: - ClaimExportSummary

    func testClaimExportSummaryDecoding() {
        let json = """
        {
            "exportId": "EXP-ABC-123",
            "incidentDate": "2026-09-17T10:00:00Z",
            "exportedAt": "2026-09-17T12:00:00Z",
            "insuranceType": "theft"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let summary = try! decoder.decode(ClaimExportSummary.self, from: json)
        XCTAssertEqual(summary.exportId, "EXP-ABC-123")
        XCTAssertEqual(summary.id, "EXP-ABC-123")
        XCTAssertEqual(summary.insuranceType, "theft")
    }

    func testClaimExportSummaryWithNilInsuranceType() {
        let json = """
        {
            "exportId": "EXP-XYZ-456",
            "incidentDate": "2026-09-17T10:00:00Z",
            "exportedAt": "2026-09-17T12:00:00Z",
            "insuranceType": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let summary = try! decoder.decode(ClaimExportSummary.self, from: json)
        XCTAssertNil(summary.insuranceType)
    }

    // MARK: - ClaimDisclaimer

    func testDisclaimerContainsKeyPhrases() {
        // Full disclaimer must include key liability-limiting language
        XCTAssertTrue(ClaimDisclaimer.full.contains("仅供"))
        XCTAssertTrue(ClaimDisclaimer.full.contains("不对"))
        XCTAssertTrue(ClaimDisclaimer.full.contains("承担责任"))

        // PDF header must clarify reference-only
        XCTAssertTrue(ClaimDisclaimer.pdfHeader.contains("仅供参考"))
        XCTAssertTrue(ClaimDisclaimer.pdfHeader.contains("不构成"))

        // Checklist note must defer to policy
        XCTAssertTrue(ClaimDisclaimer.checklistNote.contains("保险合同"))
    }

    func testDisclaimerLimitationsNotEmpty() {
        XCTAssertFalse(ClaimDisclaimer.limitations.isEmpty)
        XCTAssertGreaterThanOrEqual(ClaimDisclaimer.limitations.count, 3)
    }

    func testDisclaimerLimitationsIncludeLocationCaveat() {
        let hasLocationCaveat = ClaimDisclaimer.limitations.contains { $0.contains("定位") || $0.contains("偏差") }
        XCTAssertTrue(hasLocationCaveat, "Limitations should mention location accuracy")
    }

    func testDisclaimerLimitationsIncludeTimeCaveat() {
        let hasTimeCaveat = ClaimDisclaimer.limitations.contains { $0.contains("时钟") || $0.contains("时间") }
        XCTAssertTrue(hasTimeCaveat, "Limitations should mention time accuracy")
    }

    func testDisclaimerLimitationsIncludeNoReplacementCaveat() {
        let hasNoReplacement = ClaimDisclaimer.limitations.contains { $0.contains("不能替代") }
        XCTAssertTrue(hasNoReplacement, "Limitations should state records can't replace official documents")
    }

    // MARK: - MedicalSnapshot

    func testMedicalSnapshotAllNil() {
        let snapshot = MedicalSnapshot(
            bloodType: nil,
            allergies: nil,
            conditions: nil,
            insuranceProvider: nil,
            policyNumber: nil
        )
        XCTAssertNil(snapshot.bloodType)
        XCTAssertNil(snapshot.allergies)
    }

    func testMedicalSnapshotCodableRoundTrip() {
        let snapshot = MedicalSnapshot(
            bloodType: "O-",
            allergies: ["花生", "海鲜"],
            conditions: ["高血压"],
            insuranceProvider: "中国人寿",
            policyNumber: "CL-2026-001"
        )

        let data = try! JSONEncoder().encode(snapshot)
        let decoded = try! JSONDecoder().decode(MedicalSnapshot.self, from: data)

        XCTAssertEqual(decoded.bloodType, "O-")
        XCTAssertEqual(decoded.allergies, ["花生", "海鲜"])
        XCTAssertEqual(decoded.conditions, ["高血压"])
        XCTAssertEqual(decoded.insuranceProvider, "中国人寿")
        XCTAssertEqual(decoded.policyNumber, "CL-2026-001")
    }

    // MARK: - ExportTimeWindow

    func testExportTimeWindowCodableRoundTrip() {
        let window = ExportTimeWindow(
            start: Date(timeIntervalSinceReferenceDate: 0),
            end: Date(timeIntervalSinceReferenceDate: 86400)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try! encoder.encode(window)
        let decoded = try! decoder.decode(ExportTimeWindow.self, from: data)

        XCTAssertEqual(decoded.start.timeIntervalSinceReferenceDate, 0, accuracy: 1)
        XCTAssertEqual(decoded.end.timeIntervalSinceReferenceDate, 86400, accuracy: 1)
    }

    // MARK: - Full Export Codable Round Trip

    func testFullExportCodableRoundTrip() {
        let export = ClaimMaterialExport(
            exportId: "EXP-TEST-001",
            personName: "测试用户",
            exportedAt: Date(timeIntervalSinceReferenceDate: 1000),
            incidentDate: Date(timeIntervalSinceReferenceDate: 500),
            window: ExportTimeWindow(
                start: Date(timeIntervalSinceReferenceDate: 0),
                end: Date(timeIntervalSinceReferenceDate: 1000)
            ),
            sosEvents: [
                SOSRecordItem(triggeredAt: "2026-01-01T00:00:00Z", triggerMethod: "longPress", resolution: nil, latitude: 40.0, longitude: 116.0)
            ],
            checkIns: [
                CheckInRecordItem(timestamp: "2026-01-01T08:00:00Z", latitude: 40.0, longitude: 116.0, note: "测试")
            ],
            timeline: [
                TimelineRecordItem(timestamp: "2026-01-01T09:00:00Z", type: "checkIn", description: "签到")
            ],
            medicalSnapshot: MedicalSnapshot(bloodType: "B+", allergies: nil, conditions: nil, insuranceProvider: nil, policyNumber: nil),
            contentHash: "abcdef1234567890",
            disclaimer: ClaimDisclaimer.full
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try! encoder.encode(export)
        let decoded = try! decoder.decode(ClaimMaterialExport.self, from: data)

        XCTAssertEqual(decoded.exportId, "EXP-TEST-001")
        XCTAssertEqual(decoded.personName, "测试用户")
        XCTAssertEqual(decoded.contentHash, "abcdef1234567890")
        XCTAssertEqual(decoded.sosEvents?.count, 1)
        XCTAssertEqual(decoded.checkIns?.count, 1)
        XCTAssertEqual(decoded.timeline?.count, 1)
        XCTAssertEqual(decoded.medicalSnapshot?.bloodType, "B+")
        XCTAssertEqual(decoded.disclaimer, ClaimDisclaimer.full)
    }
}
