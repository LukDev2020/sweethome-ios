import Foundation

// MARK: - Demo Store
//
// The in-memory "server" behind Explore Mode. DemoURLProtocol answers every API
// request from here: GETs from the Chen-family fixtures, POST/PUT applied to
// this state. Shapes mirror the real routes (see ShouDengTests/ContractFixtures
// and docs/explore-mode/tools/demo_stub_server.py).

final class DemoStore {

    struct SOSState {
        var sosEventId: String
        var personId: String
        var triggeredAt: Date
        var batteryLevel: Double
        var acknowledgedBy: String?
        var acknowledgedAt: Date?
    }

    private let lock = NSLock()
    private(set) var dataset: DemoDataset
    /// Whose phone the demo is showing.
    var currentUserId: String {
        get { lock.withLock { _currentUserId } }
        set { lock.withLock { _currentUserId = newValue } }
    }
    private var _currentUserId: String
    private var sos: [String: SOSState] = [:]           // personId → active SOS
    private var extraTimeline: [String: [TimelineEntry]] = [:]
    private(set) var checkIns: [(userId: String, at: Date)] = []
    /// Requests the demo couldn't answer (shown as errors in the UI, never sent anywhere).
    private(set) var unhandled: [String] = []

    /// Called (on any thread) when demo state changes in a way the other
    /// phone would hear about (check-in, SOS, acknowledge).
    var onEvent: ((DemoEvent) -> Void)?

    enum DemoEvent: Equatable {
        case checkedIn(personId: String, at: Date)
        case sosTriggered(personId: String)
        case sosAcknowledged(personId: String, by: String)
        case sosResolved(personId: String)
    }

    init(dataset: DemoDataset, currentUserId: String) {
        self.dataset = dataset
        self._currentUserId = currentUserId
    }

    // MARK: - Mutations (also used by the scenario engine)

    func setDadBattery(_ level: Double) {
        lock.withLock { dataset.dadPerson.batteryLevel = level }
    }

    func setDadStatus(_ status: SafetyStatus) {
        lock.withLock { dataset.dadPerson.status = status }
    }

    func activeSOS(for personId: String) -> SOSState? {
        lock.withLock { sos[personId] }
    }

    @discardableResult
    func triggerSOS(personId: String, at date: Date = Date()) -> SOSState {
        let state: SOSState = lock.withLock {
            if let existing = sos[personId] { return existing }
            let new = SOSState(sosEventId: "demo-sos-\(Int(date.timeIntervalSince1970))", personId: personId,
                               triggeredAt: date, batteryLevel: personId == DemoDataset.dadId ? 0.17 : 0.82)
            sos[personId] = new
            if personId == DemoDataset.momId { dataset.momPerson.status = .alert }
            return new
        }
        onEvent?(.sosTriggered(personId: personId))
        return state
    }

    func acknowledgeSOS(sosEventId: String, by userId: String) -> SOSState? {
        let result: SOSState? = lock.withLock {
            guard let key = sos.first(where: { $0.value.sosEventId == sosEventId })?.key else { return nil }
            if sos[key]?.acknowledgedBy == nil {
                sos[key]?.acknowledgedBy = userId
                sos[key]?.acknowledgedAt = Date()
            }
            return sos[key]
        }
        if let result { onEvent?(.sosAcknowledged(personId: result.personId, by: userId)) }
        return result
    }

    func resolveSOS(id: String) {
        let personId: String? = lock.withLock {
            let key = sos.first(where: { $0.value.sosEventId == id || $0.key == currentUserIdUnlocked })?.key
            if let key {
                sos[key] = nil
                if key == DemoDataset.momId { dataset.momPerson.status = .normal }
            }
            return key
        }
        if let personId { onEvent?(.sosResolved(personId: personId)) }
    }

    private var currentUserIdUnlocked: String { _currentUserId }

    func recordCheckIn(userId: String, at date: Date = Date(), note: String? = nil) {
        lock.withLock {
            checkIns.append((userId, date))
            if userId == DemoDataset.momId {
                dataset.momPerson.lastCheckIn = date
                dataset.momPerson.status = sos[userId] == nil ? .normal : .alert
            }
            let entry = TimelineEntry(id: "demo-checkin-\(checkIns.count)", timestamp: date, type: .checkIn,
                                      description: note ?? LanguageManager.shared.localized("explore.timeline.checkIn"), detail: nil)
            extraTimeline[userId, default: []].insert(entry, at: 0)
        }
        onEvent?(.checkedIn(personId: userId, at: date))
    }

    func noteUnhandled(_ request: String) {
        lock.withLock { unhandled.append(request) }
    }

    // MARK: - Responses

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static func iso(_ d: Date?) -> Any {
        guard let d else { return NSNull() }
        return ISO8601DateFormatter().string(from: d)
    }

    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("null".utf8)
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? Self.encoder.encode(value)) ?? Data("null".utf8)
    }

    /// (status, body) for a request, or nil if the demo does not implement it.
    func respond(method: String, path: String, query: [String: String], body: Data?) -> (Int, Data)? {
        let me = currentUserId
        switch (method, path) {
        case ("GET", "/v1/user/me"):
            guard let u = lock.withLock({ dataset.user(me) }) else { return nil }
            return (200, json([
                "id": u.id, "displayName": u.displayName, "role": u.role.rawValue, "avatarInitial": u.avatarInitial,
                "email": NSNull(), "timeZone": u.timeZone.identifier, "countryCode": u.countryCode,
                "cityName": u.cityName, "createdAt": Self.iso(u.createdAt),
            ]))

        case ("GET", "/v1/guardian/protected-persons"):
            guard me == DemoDataset.sarahId else { return (200, json([])) }
            let rows = lock.withLock { [dataset.momPerson, dataset.dadPerson].map { statusRow($0) } }
            return (200, json(rows))

        case ("GET", "/v1/protected/guardians"):
            let guardians = lock.withLock { me == DemoDataset.momId ? dataset.guardiansOfMom : [] }
            return (200, encode(guardians))

        case ("GET", "/v1/family/posts"):
            return (200, encode(lock.withLock { dataset.posts }))

        case ("GET", "/v1/timeline"):
            let who = query["personId"] ?? me
            let entries = lock.withLock { (extraTimeline[who] ?? []) + (dataset.timelines[who] ?? []) }
            return (200, json(["entries": (try? JSONSerialization.jsonObject(with: encode(entries))) ?? [], "hasMore": false]))

        case ("GET", "/v1/sos/active"):
            return (200, activeSOSBody(personId: me))

        case ("GET", "/v1/guardian/sos/active"):
            return (200, activeSOSBody(personId: query["personId"] ?? ""))

        case ("GET", "/v1/safe-zones"):
            let zones = lock.withLock { dataset.safeZones }
            return (200, json(zones.map { ["id": $0.id, "name": $0.name, "latitude": $0.latitude,
                                           "longitude": $0.longitude, "radius": $0.radius, "isAutoSuggested": $0.isAutoSuggested] }))

        case ("GET", "/v1/consulate/selected/me"):
            return (200, Data("null".utf8))

        case ("POST", "/v1/checkin"):
            let note = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["note"] as? String
            recordCheckIn(userId: me, note: note)
            return (200, json(["checkInId": "demo-ci-\(Int(Date().timeIntervalSince1970))",
                               "timestamp": Self.iso(Date()), "guardiansNotified": 3]))

        case ("POST", "/v1/sos/trigger"):
            let s = triggerSOS(personId: me)
            return (201, json(["sosEventId": s.sosEventId, "escalationState": "initiated"]))

        case ("POST", "/v1/sos/acknowledge"):
            let id = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["sosEventId"] as? String ?? ""
            guard let s = acknowledgeSOS(sosEventId: id, by: me) else { return (404, json(["error": "SOS event not found"])) }
            return (200, json(["success": true, "acknowledgedBy": s.acknowledgedBy ?? me, "alreadyAcknowledged": s.acknowledgedBy != me]))

        case ("POST", "/v1/sos/resolve"):
            let id = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["sosEventId"] as? String ?? ""
            resolveSOS(id: id)
            return (200, json(["success": true, "sosEventId": id]))

        case ("POST", _), ("PUT", _), ("DELETE", _):
            // Telemetry, preferences, profile edits… accepted and kept on the phone
            return (200, json(["success": true]))

        default:
            return nil
        }
    }

    private func activeSOSBody(personId: String) -> Data {
        guard let status = sosStatus(personId: personId) else {
            return json(["active": false, "sos": NSNull()])
        }
        let sosObject = (try? JSONSerialization.jsonObject(with: encode(status))) ?? NSNull()
        return json(["active": true, "sos": sosObject])
    }

    /// Simulated escalation that follows the real plan's timing (hop2 30 s,
    /// calls from 90 s, link at 120 s) — nobody is actually contacted.
    func sosStatus(personId: String, now: Date = Date()) -> SOSStatus? {
        lock.withLock {
            guard let s = sos[personId], let person = dataset.user(personId) else { return nil }
            let elapsed = max(0, Int(now.timeIntervalSince(s.triggeredAt)))
            let ack = s.acknowledgedBy
            let state: EscalationState = ack != nil ? .frozen
                : elapsed < 30 ? .hop1_notified : elapsed < 90 ? .hop2_allNotified
                : elapsed < 120 ? .hop3_voiceCalling : .hop4_shareSent
            return SOSStatus(
                sosEventId: s.sosEventId, protectedPersonId: personId, personName: person.displayName,
                triggeredAt: s.triggeredAt, triggerMethod: "longPress",
                latitude: 30.6586, longitude: 104.0647, batteryLevel: s.batteryLevel,
                escalationState: state, nextStep: ack != nil ? nil : "voice1", nextStepAt: nil,
                guardiansNotified: elapsed < 30 ? 1 : 3, callsPlaced: ack != nil || elapsed < 90 ? 0 : 3,
                shareLinkSent: ack == nil && elapsed >= 120, noGuardians: false, emergencyContactsNotified: 0,
                acknowledgedBy: ack, acknowledgedByName: ack.flatMap { dataset.user($0)?.displayName },
                acknowledgedAt: s.acknowledgedAt, elapsedSeconds: elapsed)
        }
    }

    private func statusRow(_ p: ProtectedPerson) -> [String: Any] {
        let loc = p.lastKnownLocation
        var row: [String: Any] = [
            "personId": p.id, "displayName": p.user.displayName, "status": p.status.rawValue,
            "latitude": loc?.latitude ?? NSNull(), "longitude": loc?.longitude ?? NSNull(),
            "locationTimestamp": Self.iso(loc?.timestamp), "locationAddress": loc?.address ?? NSNull(),
            "locationAccuracy": loc?.accuracy ?? NSNull(), "batteryLevel": p.batteryLevel ?? NSNull(),
            "batteryState": p.batteryState.rawValue, "lastCheckIn": Self.iso(p.lastCheckIn),
            "lastPhoneActivity": Self.iso(p.lastPhoneActivity), "protectionLayers": p.protectionLayers,
            "timeZoneId": p.user.timeZone.identifier, "countryCode": p.user.countryCode, "cityName": p.user.cityName,
        ]
        // Caller holds `lock`
        if let s = sos[p.id], let person = dataset.user(p.id) {
            let elapsed = max(0, Int(Date().timeIntervalSince(s.triggeredAt)))
            row["status"] = "alert"
            row["activeSOS"] = [
                "sosEventId": s.sosEventId, "protectedPersonId": p.id, "personName": person.displayName,
                "triggeredAt": Self.iso(s.triggeredAt), "triggerMethod": "longPress",
                "latitude": 30.6586, "longitude": 104.0647, "batteryLevel": s.batteryLevel,
                "escalationState": s.acknowledgedBy == nil ? "hop2_allNotified" : "frozen",
                "nextStep": NSNull(), "nextStepAt": NSNull(), "guardiansNotified": 3, "callsPlaced": 0,
                "shareLinkSent": false, "noGuardians": false, "emergencyContactsNotified": 0,
                "acknowledgedBy": s.acknowledgedBy ?? NSNull(),
                "acknowledgedByName": s.acknowledgedBy.flatMap { dataset.user($0)?.displayName } ?? NSNull(),
                "acknowledgedAt": Self.iso(s.acknowledgedAt), "elapsedSeconds": elapsed,
            ] as [String: Any]
        }
        return row
    }
}
