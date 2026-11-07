import Foundation
import CoreLocation
import CryptoKit

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
        var triggerMethod = "longPress"
    }

    /// Falls the demo detected ("Try fall detection"), for the police report
    struct DemoFall {
        var clientEventId: String
        var detectedAt: Date
        var outcome: String
        var respondedAfterSec: Double?
        var metrics: [String: Any]
    }
    private var falls: [String: [DemoFall]] = [:]

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
    /// Photos "uploaded" to the family circle, by id (kept in memory only).
    private var media: [String: Data] = [:]
    /// SOS that ended during this demo (for the claim materials)
    private var pastSOS: [String: [(state: SOSState, resolvedAt: Date)]] = [:]
    /// Emergency medical cards by person (Mom starts with one filled in)
    private var medicalCards: [String: Data] = [:]

    // Rider demo (Kai's phone): shift, crew, caution spots, crew answers
    private var kaiOnShift = false
    /// Family watch back: guardian id → state for Mom ("pending" / "active")
    private var momWatchesBack: [String: String] = [:]
    /// Who watches whose shifts: Wei and Mei (his sister) watch Kai; Kai watches Ahmed.
    /// Kai doesn't watch Wei yet — "Watch back" on Wei's row.
    private var watchers: [String: [String]] = [
        DemoDataset.kaiId: [DemoDataset.weiId, DemoDataset.meiId],
        DemoDataset.ahmedId: [DemoDataset.kaiId],
    ]
    private var kaiInCrew = true
    private var crewName = "CBD night crew"
    private var cautions: [(id: String, latitude: Double, longitude: Double, note: String, at: Date)] = []
    /// sosEventId → crew member id → "going" / "cant_help"
    private var crewAnswers: [String: [String: (response: String, at: Date)]] = [:]

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
        let t = DemoText(language: LanguageManager.shared.current)
        let momCard = MedicalCardData(bloodType: "A+", allergies: [t.penicillin],
                                      medicationItems: [MedicationItem(id: "demo-med-1", name: t.amlodipine,
                                                                       storageLocation: t.medicineShelf, dosage: t.everyMorning)],
                                      conditions: [t.highBloodPressure], insuranceProvider: t.insurer,
                                      insurancePolicyNumber: "PH-2026-0417", emergencyNote: t.medicalNote)
        medicalCards[DemoDataset.momId] = (try? JSONEncoder().encode(momCard)) ?? Data()
    }

    /// The persona's phone battery (the demo never reads the device's).
    func batteryLevel(of personId: String) -> Double? {
        lock.withLock {
            switch personId {
            case DemoDataset.momId: return dataset.momPerson.batteryLevel
            case DemoDataset.dadId: return dataset.dadPerson.batteryLevel
            case DemoDataset.sarahId: return 0.64
            case DemoDataset.kaiId: return 0.71
            default: return nil
            }
        }
    }

    /// Caller holds `lock`. What the server writes to the person's own timeline.
    private func noteOnTimeline(_ personId: String, _ type: TimelineEntryType, _ text: String, at date: Date = Date()) {
        let entry = TimelineEntry(id: "demo-\(type.rawValue)-\(Int(date.timeIntervalSince1970 * 1000))", timestamp: date,
                                  type: type, description: text, detail: nil)
        extraTimeline[personId, default: []].insert(entry, at: 0)
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
    func triggerSOS(personId: String, at date: Date = Date(), method: String = "longPress") -> SOSState {
        let state: SOSState = lock.withLock {
            if let existing = sos[personId] { return existing }
            let new = SOSState(sosEventId: "demo-sos-\(Int(date.timeIntervalSince1970))", personId: personId,
                               triggeredAt: date, batteryLevel: personId == DemoDataset.dadId ? 0.17 : 0.82,
                               triggerMethod: method)
            sos[personId] = new
            if personId == DemoDataset.momId { dataset.momPerson.status = .alert }
            let lm = LanguageManager.shared
            noteOnTimeline(personId, .sosTriggered, String(format: lm.localized("timeline.sosTriggered"),
                                                           lm.localized("sos.method.\(method)")), at: date)
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
                if let name = dataset.user(userId)?.displayName {
                    noteOnTimeline(key, .guardianAlert,
                                   String(format: LanguageManager.shared.localized("sos.status.acknowledged"), name))
                }
            }
            return sos[key]
        }
        if let result { onEvent?(.sosAcknowledged(personId: result.personId, by: userId)) }
        return result
    }

    func resolveSOS(id: String) {
        let personId: String? = lock.withLock {
            let key = sos.first(where: { $0.value.sosEventId == id || $0.key == currentUserIdUnlocked })?.key
            if let key, let ended = sos[key] {
                sos[key] = nil
                pastSOS[key, default: []].append((ended, Date()))
                if key == DemoDataset.momId { dataset.momPerson.status = .normal }
                noteOnTimeline(key, .sosResolved, LanguageManager.shared.localized("timeline.sosEnded"))
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

    /// A photo uploaded during this demo (its URL points at the demo host).
    func mediaData(for url: URL) -> Data? {
        guard url.host == DemoURLProtocol.host, url.path.hasPrefix("/media/") else { return nil }
        let id = url.deletingPathExtension().lastPathComponent
        return lock.withLock { media[id] }
    }

    // MARK: - Family circle (same rules as routes/family.ts)

    private func bodyObject(_ body: Data?) -> [String: Any] {
        (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }

    private func createPost(by me: String, body: Data?) -> (Int, Data) {
        let b = bodyObject(body)
        let text = (b["text"] as? String) ?? ""
        let urls = FamilyFeedSync.remoteMediaURLs((b["mediaURLs"] as? [String]) ?? [])
        guard !text.isEmpty || !urls.isEmpty else { return (400, json(["error": "Post must have text or media"])) }
        return lock.withLock {
            let id = (b["clientPostId"] as? String) ?? "demo-post-\(dataset.posts.count + 1)"
            if dataset.posts.contains(where: { $0.id == id }) { return (200, json(["postId": id])) }
            guard let u = dataset.user(me) else { return (404, json(["error": "User not found"])) }
            let post = FamilyPost(
                id: id, authorId: me, authorName: u.displayName, authorInitial: u.avatarInitial, authorAvatarPath: nil,
                text: text, mediaURLs: urls, createdAt: Date(), comments: [], commentCount: 0,
                latitude: b["latitude"] as? Double, longitude: b["longitude"] as? Double,
                locationName: b["locationName"] as? String)
            dataset.posts.insert(post, at: 0)
            return (201, json(["postId": id]))
        }
    }

    private func addComment(by me: String, postId: String, body: Data?) -> (Int, Data) {
        let text = ((bodyObject(body)["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return (400, json(["error": "Comment text is required"])) }
        return lock.withLock {
            guard let i = dataset.posts.firstIndex(where: { $0.id == postId }) else { return (404, json(["error": "Post not found"])) }
            guard let u = dataset.user(me) else { return (404, json(["error": "User not found"])) }
            let id = "demo-comment-\(Int(Date().timeIntervalSince1970 * 1000))"
            dataset.posts[i].comments.append(FamilyComment(
                id: id, authorId: me, authorName: u.displayName, authorInitial: u.avatarInitial,
                authorAvatarPath: nil, text: text, createdAt: Date()))
            dataset.posts[i].commentCount += 1
            return (201, json(["commentId": id]))
        }
    }

    private func uploadMedia(body: Data?) -> (Int, Data) {
        guard let base64 = bodyObject(body)["data"] as? String, let data = Data(base64Encoded: base64), !data.isEmpty else {
            return (400, json(["error": "Missing data"]))
        }
        let id = UUID().uuidString
        lock.withLock { media[id] = data }
        return (200, json(["url": "https://\(DemoURLProtocol.host)/media/\(id).jpg"]))
    }

    /// Posts as the feed returns them: the newest 10 comments, and the full count.
    private func feed() -> [FamilyPost] {
        lock.withLock {
            dataset.posts.sorted { $0.createdAt > $1.createdAt }.map { post in
                var p = post
                p.comments = Array(post.comments.sorted { $0.createdAt < $1.createdAt }.suffix(10))
                return p
            }
        }
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

        case ("GET", "/v1/watch-back"), ("POST", "/v1/watch-back/request"), ("POST", "/v1/watch-back/offer"),
             ("POST", "/v1/watch-back/respond"), ("POST", "/v1/watch-back/stop"):
            return watchBackRoute(method: method, path: path, me: me, body: body)

        case ("GET", "/v1/guardian/protected-persons") where me == DemoDataset.momId:
            // Mom watches Sarah back
            let rows: [[String: Any]] = lock.withLock {
                momWatchesBack[DemoDataset.sarahId] == "active" ? [statusRow(sarahAsWatched())] : []
            }
            return (200, json(rows))

        case ("GET", "/v1/guardian/protected-persons"):
            guard me == DemoDataset.sarahId else { return (200, json([])) }
            let rows = lock.withLock { [dataset.momPerson, dataset.dadPerson].map { statusRow($0) } }
            return (200, json(rows))

        case ("GET", "/v1/guardian/circle"):
            // Same rule as the server: only someone who looks after the person
            let personId = query["personId"] ?? ""
            let circle: [Guardian]? = lock.withLock {
                let guardians = personId == DemoDataset.momId ? dataset.guardiansOfMom
                    : personId == DemoDataset.dadId ? dataset.guardiansOfDad : []
                return guardians.contains { $0.id == me } ? guardians : nil
            }
            guard let circle else { return (403, json(["error": "No active guardian link for this person"])) }
            return (200, encode(circle))

        case ("GET", "/v1/medical-card"), ("GET", "/v1/medical-card/\(DemoDataset.momId)"):
            let personId = path == "/v1/medical-card" ? me : DemoDataset.momId
            return (200, lock.withLock { medicalCards[personId] } ?? json([:] as [String: Any]))

        case ("PUT", "/v1/medical-card"), ("PUT", "/v1/medical-card/\(DemoDataset.momId)"):
            let personId = path == "/v1/medical-card" ? me : DemoDataset.momId
            lock.withLock { medicalCards[personId] = body }
            return (200, json(["success": true]))

        case ("POST", "/v1/insurance/claim-materials"):
            return claimMaterials(for: me, body: bodyObject(body))

        case ("GET", "/v1/protected/guardians"):
            let guardians = lock.withLock {
                me == DemoDataset.momId ? dataset.guardiansOfMom : me == DemoDataset.kaiId ? dataset.guardiansOfKai : []
            }
            return (200, encode(guardians))

        case ("GET", "/v1/crew"), ("POST", "/v1/crew"), ("POST", "/v1/crew/join"), ("POST", "/v1/crew/leave"), ("POST", "/v1/crew/watch-back"),
             ("POST", "/v1/crew/shift"), ("POST", "/v1/crew/caution"), ("GET", "/v1/crew/alerts"), ("POST", "/v1/crew/respond"):
            return crewRoute(method: method, path: path, me: me, body: body)

        case ("GET", "/v1/family/posts"):
            return (200, encode(feed()))

        case ("POST", "/v1/family/posts"):
            return createPost(by: me, body: body)

        case ("POST", "/v1/family/upload"):
            return uploadMedia(body: body)

        case ("POST", let p) where p.hasPrefix("/v1/family/posts/") && p.hasSuffix("/comments"):
            let postId = p.dropFirst("/v1/family/posts/".count).dropLast("/comments".count)
            return addComment(by: me, postId: String(postId), body: body)

        case ("PUT", let p) where p.hasPrefix("/v1/family/posts/"):
            let postId = String(p.dropFirst("/v1/family/posts/".count))
            let text = (bodyObject(body)["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return lock.withLock {
                guard let i = dataset.posts.firstIndex(where: { $0.id == postId && $0.authorId == me }), !text.isEmpty else {
                    return (404, json(["error": "Post not found"]))
                }
                dataset.posts[i].text = text
                return (200, json(["success": true]))
            }

        case ("DELETE", let p) where p.hasPrefix("/v1/family/posts/"):
            let postId = String(p.dropFirst("/v1/family/posts/".count))
            lock.withLock { dataset.posts.removeAll { $0.id == postId && $0.authorId == me } }
            return (200, json(["success": true]))

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
            let s = triggerSOS(personId: me, method: (bodyObject(body)["triggerMethod"] as? String) ?? "longPress")
            return (201, json(["sosEventId": s.sosEventId, "escalationState": "initiated"]))

        case ("POST", "/v1/sos/acknowledge"):
            let id = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["sosEventId"] as? String ?? ""
            guard let s = acknowledgeSOS(sosEventId: id, by: me) else { return (404, json(["error": "SOS event not found"])) }
            return (200, json(["success": true, "acknowledgedBy": s.acknowledgedBy ?? me, "alreadyAcknowledged": s.acknowledgedBy != me]))

        case ("POST", "/v1/sos/resolve"):
            let id = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["sosEventId"] as? String ?? ""
            resolveSOS(id: id)
            return (200, json(["success": true, "sosEventId": id]))

        case ("POST", "/v1/safety-events/fall"):
            return (200, json(recordFall(personId: me, body: bodyObject(body))))

        case ("POST", "/v1/incident-reports"):
            return demoIncidentReport(by: me, body: bodyObject(body))

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
            let spot = Self.spot(of: personId)
            var status = SOSStatus(
                sosEventId: s.sosEventId, protectedPersonId: personId, personName: person.displayName,
                triggeredAt: s.triggeredAt, triggerMethod: s.triggerMethod,
                latitude: spot.latitude, longitude: spot.longitude, batteryLevel: s.batteryLevel,
                escalationState: state, nextStep: ack != nil ? nil : "voice1", nextStepAt: nil,
                guardiansNotified: elapsed < 30 ? 1 : 3, callsPlaced: ack != nil || elapsed < 90 ? 0 : 3,
                shareLinkSent: ack == nil && elapsed >= 120, noGuardians: false, emergencyContactsNotified: 0,
                acknowledgedBy: ack, acknowledgedByName: ack.flatMap { dataset.user($0)?.displayName },
                acknowledgedAt: s.acknowledgedAt, elapsedSeconds: elapsed)
            if personId == DemoDataset.kaiId {
                // Kai's crew answers like real riders would: Wei after 6 s, Ahmed after 15 s
                status.crewNotified = 3
                var answers: [CrewResponseEntry] = []
                if elapsed >= 6 {
                    answers.append(CrewResponseEntry(memberId: DemoDataset.weiId, name: dataset.wei.displayName, response: "going",
                                                     at: s.triggeredAt.addingTimeInterval(6), distanceM: 220))
                }
                if elapsed >= 15 {
                    answers.append(CrewResponseEntry(memberId: DemoDataset.ahmedId, name: dataset.ahmed.displayName, response: "going",
                                                     at: s.triggeredAt.addingTimeInterval(15), distanceM: 480))
                }
                status.crewResponses = answers
            }
            return status
        }
    }

    /// Where each demo person's phone is
    static func spot(of personId: String) -> CLLocationCoordinate2D {
        switch personId {
        case DemoDataset.kaiId: return DemoDataset.kaiSpot
        case DemoDataset.weiId: return DemoDataset.weiSpot
        case DemoDataset.ahmedId: return DemoDataset.ahmedSpot
        case DemoDataset.linaId: return DemoDataset.linaSpot
        default: return CLLocationCoordinate2D(latitude: 30.6586, longitude: 104.0647)
        }
    }

    private static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Int {
        Int(CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)))
    }

    // MARK: - Family watch back (same shapes as routes/watchBack.ts)

    private func watchBackRoute(method: String, path: String, me: String, body: Data?) -> (Int, Data) {
        let b = bodyObject(body)
        switch path {
        case "/v1/watch-back/request" where me == DemoDataset.momId:
            let gid = (b["guardianId"] as? String) ?? ""
            lock.withLock { momWatchesBack[gid] = "pending" }
            // Sarah says yes a few seconds later (in the demo she always agrees)
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.lock.withLock { if self?.momWatchesBack[gid] == "pending" { self?.momWatchesBack[gid] = "active" } }
            }
            return (200, json(["state": "pending"]))
        case "/v1/watch-back/offer" where me == DemoDataset.sarahId:
            if (b["personId"] as? String) == DemoDataset.momId { lock.withLock { momWatchesBack[me] = "active" } }
            return (200, json(["state": "active"]))
        case "/v1/watch-back/respond" where me == DemoDataset.sarahId:
            let accept = (b["accept"] as? Bool) ?? false
            lock.withLock { momWatchesBack[me] = accept ? "active" : nil }
            return (200, json(["state": accept ? "active" : "none"]))
        case "/v1/watch-back/stop":
            let other = (b["otherId"] as? String) ?? ""
            lock.withLock { momWatchesBack[me == DemoDataset.momId ? other : me] = nil }
            return (200, json(["success": true]))
        default:
            return (200, json(lock.withLock { watchBackOverview(me: me) }))
        }
    }

    private func watchBackOverview(me: String) -> [String: Any] {
        func entry(_ u: User, _ state: String?) -> [String: Any] { ["id": u.id, "name": u.displayName, "state": state ?? "none"] }
        switch me {
        case DemoDataset.momId:
            return ["guardians": dataset.guardiansOfMom.map { entry($0.user, momWatchesBack[$0.user.id]) }, "people": []]
        case DemoDataset.sarahId:
            return ["guardians": [], "people": [entry(dataset.mom, momWatchesBack[me]), entry(dataset.dad, nil)]]
        default:
            return ["guardians": [], "people": []]
        }
    }

    /// Sarah, as Mom sees her when she watches back (Toronto)
    private func sarahAsWatched() -> ProtectedPerson {
        let now = Date()
        let loc = Location(latitude: 43.6532, longitude: -79.3832, accuracy: 15, altitude: nil, speed: nil,
                           timestamp: now.addingTimeInterval(-4 * 60), address: DemoText(language: LanguageManager.shared.current).toronto,
                           isInSafeZone: false, safeZoneName: nil, activityType: .walking)
        return ProtectedPerson(id: dataset.sarah.id, user: dataset.sarah, guardians: [], protectionLayers: 1,
                               lastCheckIn: now.addingTimeInterval(-2 * 3600), lastKnownLocation: loc,
                               batteryLevel: 0.64, batteryState: .unplugged, lastPhoneActivity: now.addingTimeInterval(-3 * 60),
                               status: .normal)
    }

    // MARK: - Rider crew (same shapes as routes/crew.ts)

    private func crewRoute(method: String, path: String, me: String, body: Data?) -> (Int, Data) {
        let b = bodyObject(body)
        switch (method, path) {
        case ("POST", "/v1/crew/shift"):
            lock.withLock {
                kaiOnShift = (b["onShift"] as? Bool) ?? false
                if kaiOnShift, let ids = b["watcherIds"] as? [String] { watchers[me] = ids }
            }
            return (200, json(["success": true]))
        case ("POST", "/v1/crew/watch-back"):
            let member = (b["memberId"] as? String) ?? ""
            let ok: Bool = lock.withLock {
                guard watchers[me, default: []].contains(member) else { return false }
                if !watchers[member, default: []].contains(me) { watchers[member, default: []].append(me) }
                return true
            }
            return ok ? (200, json(["success": true])) : (403, json(["error": "they don't watch you"]))
        case ("POST", "/v1/crew"):
            lock.withLock { kaiInCrew = true; crewName = (b["name"] as? String) ?? crewName }
            return (201, json(["crew": crewJSON(me: me)]))
        case ("POST", "/v1/crew/join"):
            guard ((b["code"] as? String) ?? "").count == 6 else { return (400, json(["error": "invalid code"])) }
            lock.withLock { kaiInCrew = true }
            return (200, json(["crew": crewJSON(me: me)]))
        case ("POST", "/v1/crew/leave"):
            lock.withLock { kaiInCrew = false }
            return (200, json(["success": true]))
        case ("POST", "/v1/crew/caution"):
            let lat = (b["latitude"] as? Double) ?? DemoDataset.kaiSpot.latitude
            let lng = (b["longitude"] as? Double) ?? DemoDataset.kaiSpot.longitude
            let id = "demo-caution-\(Int(Date().timeIntervalSince1970))"
            lock.withLock { cautions.append((id, lat, lng, (b["note"] as? String) ?? "", Date())) }
            return (201, json(["id": id]))
        case ("GET", "/v1/crew/alerts"):
            return (200, json(["alerts": crewAlertsJSON(me: me)]))
        case ("POST", "/v1/crew/respond"):
            let id = (b["sosEventId"] as? String) ?? ""
            let response = (b["response"] as? String) ?? ""
            guard ["going", "cant_help"].contains(response) else { return (400, json(["error": "bad response"])) }
            let found: Bool = lock.withLock {
                guard sos.values.contains(where: { $0.sosEventId == id }) else { return false }
                crewAnswers[id, default: [:]][me] = (response, Date())
                return true
            }
            guard found else { return (404, json(["error": "SOS not found or already ended"])) }
            // The practice SOS ends a little later: "Ahmed is safe"
            DispatchQueue.global().asyncAfter(deadline: .now() + 25) { [weak self] in self?.resolveSOS(id: id) }
            return (200, json(["success": true]))
        default:
            return (200, json(["crew": crewJSON(me: me)]))
        }
    }

    /// The practice crew alert (Crew tab, demo only): Ahmed calls SOS near Kai.
    func practiceCrewSOS() -> String {
        triggerSOS(personId: DemoDataset.ahmedId).sosEventId
    }

    private func crewJSON(me: String) -> Any {
        lock.withLock {
            guard me == DemoDataset.kaiId, kaiInCrew else { return NSNull() }
            let here = DemoDataset.kaiSpot
            func member(_ u: User, onShift: Bool) -> [String: Any] {
                let spot = Self.spot(of: u.id)
                let visible = onShift || u.id == me
                return ["id": u.id, "name": u.displayName, "initial": u.avatarInitial, "onShift": onShift,
                        "latitude": visible ? spot.latitude : NSNull(), "longitude": visible ? spot.longitude : NSNull(),
                        "locationAt": Self.iso(visible ? Date().addingTimeInterval(-40) : nil),
                        "distanceM": visible && u.id != me ? Self.meters(here, spot) : NSNull(),
                        "watchesMe": u.id != me && (watchers[me] ?? []).contains(u.id),
                        "iWatch": u.id != me && (watchers[u.id] ?? []).contains(me)]
            }
            return [
                "id": "demo-crew", "name": crewName, "inviteCode": "K7M2QX", "isOwner": true,
                "myWatcherIds": watchers[me] ?? [],
                "members": [member(dataset.kai, onShift: kaiOnShift), member(dataset.wei, onShift: true),
                            member(dataset.ahmed, onShift: true), member(dataset.lina, onShift: false)],
                "cautions": cautions.map { ["id": $0.id, "latitude": $0.latitude, "longitude": $0.longitude,
                                            "note": $0.note, "createdAt": Self.iso($0.at)] as [String: Any] },
            ] as [String: Any]
        }
    }

    private func crewAlertsJSON(me: String) -> [[String: Any]] {
        lock.withLock {
            guard me == DemoDataset.kaiId, kaiInCrew, let s = sos[DemoDataset.ahmedId] else { return [] }
            let spot = DemoDataset.ahmedSpot
            let answers = crewAnswers[s.sosEventId] ?? [:]
            var responses: [[String: Any]] = answers.compactMap { id, a in
                guard let u = dataset.user(id) else { return nil }
                return ["memberId": id, "name": u.displayName, "response": a.response, "at": Self.iso(a.at),
                        "distanceM": Self.meters(Self.spot(of: id), spot)]
            }
            if Date().timeIntervalSince(s.triggeredAt) >= 8 {
                responses.append(["memberId": DemoDataset.weiId, "name": dataset.wei.displayName, "response": "going",
                                  "at": Self.iso(s.triggeredAt.addingTimeInterval(8)), "distanceM": Self.meters(DemoDataset.weiSpot, spot)])
            }
            return [[
                "sosEventId": s.sosEventId, "riderId": DemoDataset.ahmedId, "riderName": dataset.ahmed.displayName,
                "triggeredAt": Self.iso(s.triggeredAt), "latitude": spot.latitude, "longitude": spot.longitude,
                "distanceM": Self.meters(DemoDataset.kaiSpot, spot), "myResponse": answers[me]?.response ?? NSNull(),
                "responses": responses,
            ]]
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
            "phone": p.user.phone ?? NSNull(),
        ]
        // Caller holds `lock`
        if let s = sos[p.id], let person = dataset.user(p.id) {
            let elapsed = max(0, Int(Date().timeIntervalSince(s.triggeredAt)))
            row["status"] = "alert"
            row["activeSOS"] = [
                "sosEventId": s.sosEventId, "protectedPersonId": p.id, "personName": person.displayName,
                "triggeredAt": Self.iso(s.triggeredAt), "triggerMethod": s.triggerMethod,
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

    // MARK: - Claim materials (same shape as routes/insurance.ts)

    private func claimMaterials(for me: String, body: [String: Any]) -> (Int, Data) {
        func date(_ any: Any?) -> Date? {
            guard let text = any as? String else { return nil }
            let f = ISO8601DateFormatter()
            if let d = f.date(from: text) { return d }
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: text)
        }
        guard let incident = date(body["incidentDate"]) else { return (400, json(["error": "incidentDate is required"])) }
        let half = Double((body["windowHours"] as? Int) ?? 24) * 3600
        let start = incident.addingTimeInterval(-half), end = incident.addingTimeInterval(half)
        func on(_ key: String) -> Bool { (body[key] as? Bool) ?? true }
        let withLocation = on("includeLocation")
        let spot = Self.spot(of: me)
        return lock.withLock {
            guard let person = dataset.user(me) else { return (404, json(["error": "User not found"])) }
            func inWindow(_ d: Date) -> Bool { d >= start && d <= end }
            var sosRows: [[String: Any]] = (pastSOS[me] ?? []).filter { inWindow($0.state.triggeredAt) }.map {
                ["triggeredAt": Self.iso($0.state.triggeredAt), "triggerMethod": $0.state.triggerMethod,
                 "resolution": $0.state.acknowledgedBy == nil ? "protectedCancelled" : "guardianResolved"]
            }
            if let s = sos[me], inWindow(s.triggeredAt) {
                sosRows.append(["triggeredAt": Self.iso(s.triggeredAt), "triggerMethod": s.triggerMethod, "resolution": NSNull()])
            }
            for i in sosRows.indices {
                sosRows[i]["latitude"] = withLocation ? spot.latitude : NSNull()
                sosRows[i]["longitude"] = withLocation ? spot.longitude : NSNull()
            }
            let checkInRows: [[String: Any]] = checkIns.filter { $0.userId == me && inWindow($0.at) }.map {
                ["timestamp": Self.iso($0.at), "latitude": withLocation ? spot.latitude : NSNull(),
                 "longitude": withLocation ? spot.longitude : NSNull(), "note": NSNull()]
            }
            let timelineRows: [[String: Any]] = ((extraTimeline[me] ?? []) + (dataset.timelines[me] ?? []))
                .filter { inWindow($0.timestamp) }.sorted { $0.timestamp < $1.timestamp }
                .map { ["timestamp": Self.iso($0.timestamp), "type": $0.type.rawValue, "description": $0.description] }
            var medical: Any = NSNull()
            if on("includeMedicalCard"), let data = medicalCards[me], let card = try? JSONDecoder().decode(MedicalCardData.self, from: data) {
                medical = ["bloodType": card.bloodType ?? NSNull(), "allergies": card.allergies.isEmpty ? NSNull() : card.allergies,
                           "conditions": card.conditions.isEmpty ? NSNull() : card.conditions,
                           "insuranceProvider": card.insuranceProvider ?? NSNull(),
                           "policyNumber": (card.insurancePolicyNumber ?? body["policyNumber"] as? String).map { $0 as Any } ?? NSNull()] as [String: Any]
            }
            var export: [String: Any] = [
                "exportId": "EXP-DEMO-\(Int(Date().timeIntervalSince1970))", "personName": person.displayName,
                "exportedAt": Self.iso(Date()), "incidentDate": Self.iso(incident),
                "window": ["start": Self.iso(start), "end": Self.iso(end)],
                "sosEvents": on("includeSOS") ? sosRows : NSNull(),
                "checkIns": on("includeCheckIns") ? checkInRows : NSNull(),
                "timeline": on("includeTimeline") ? timelineRows : NSNull(),
                "medicalSnapshot": medical,
                "disclaimer": ClaimDisclaimer.full,
            ]
            let hashed = (try? JSONSerialization.data(withJSONObject: export, options: [.sortedKeys])) ?? Data()
            export["contentHash"] = SHA256.hash(data: hashed).map { String(format: "%02x", $0) }.joined()
            return (200, json(export))
        }
    }

    // MARK: - Falls and the police report (same shapes as safetyEvents.ts / incidentReport.ts)

    private func recordFall(personId: String, body: [String: Any]) -> [String: Any] {
        let id = body["clientEventId"] as? String ?? UUID().uuidString
        let outcome = body["outcome"] as? String ?? "pending"
        lock.withLock {
            var list = falls[personId] ?? []
            if let i = list.firstIndex(where: { $0.clientEventId == id }) {
                if list[i].outcome == "pending" { list[i].outcome = outcome }
                list[i].respondedAfterSec = body["respondedAfterSec"] as? Double ?? list[i].respondedAfterSec
            } else {
                list.append(DemoFall(clientEventId: id, detectedAt: Date(), outcome: outcome,
                                     respondedAfterSec: body["respondedAfterSec"] as? Double,
                                     metrics: body["metrics"] as? [String: Any] ?? [:]))
            }
            falls[personId] = list
        }
        return ["outcome": outcome, "sosEventId": NSNull()]
    }

    /// A believable afternoon for the person (home → walk → park → on the way back),
    /// plus whatever the visitor did: SOS, falls, check-ins. Hashed like the server does.
    private func demoIncidentReport(by me: String, body: [String: Any]) -> (Int, Data) {
        let personId = body["personId"] as? String ?? me
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()
        let start = (body["windowStart"] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } ?? now.addingTimeInterval(-86400)
        let end = min(now, (body["windowEnd"] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } ?? now)
        guard let person = lock.withLock({ dataset.user(personId) }), let reporter = lock.withLock({ dataset.user(me) }) else {
            return (403, json(["error": "Only the person or their guardian can make this report"]))
        }
        let base = Self.spot(of: personId)
        func at(_ minutesAgo: Double) -> Date { now.addingTimeInterval(-minutesAgo * 60) }
        // (minutes ago, north m, east m, speed m/s, activity)
        let path: [(Double, Double, Double, Double, String?)] = [
            (175, 0, 0, 0, "stationary"), (160, 2, 1, 0, "stationary"), (145, 1, -2, 0, "stationary"),
            (130, 60, 40, 1.3, "walking"), (125, 180, 120, 1.4, "walking"), (120, 320, 210, 1.3, "walking"),
            (115, 450, 330, 1.2, "walking"), (110, 560, 470, 1.4, "walking"), (105, 640, 610, 1.3, "walking"),
            (95, 650, 620, 0.1, "stationary"), (80, 655, 615, 0, "stationary"), (65, 648, 624, 0, "stationary"),
            (50, 600, 560, 1.2, "walking"), (45, 520, 470, 1.3, "walking"), (40, 470, 400, 1.1, "walking"),
            (12, 470, 400, 0, nil),
        ]
        var points: [[String: Any]] = []
        for (ago, n, e, v, act) in path {
            let t = at(ago)
            guard t >= start, t <= end else { continue }
            let lat = base.latitude + n / 111_000, lon = base.longitude + e / (111_000 * cos(base.latitude * .pi / 180))
            points.append(["at": iso.string(from: t), "latitude": lat, "longitude": lon, "accuracy": act == nil ? 35 : 9,
                           "speed": v, "altitude": NSNull(), "activity": act ?? NSNull(), "source": "history"])
        }
        let (sosState, demoFalls) = lock.withLock { (sos[personId], falls[personId] ?? []) }
        var sosList: [[String: Any]] = []
        if let s = sosState, s.triggeredAt >= start {
            let p: [String: Any] = ["at": iso.string(from: s.triggeredAt), "latitude": base.latitude + 470 / 111_000,
                                    "longitude": base.longitude + 400 / (111_000 * cos(base.latitude * .pi / 180)),
                                    "accuracy": 12, "speed": NSNull(), "altitude": NSNull(), "activity": NSNull(), "source": "sos"]
            points.append(p)
            sosList.append(["id": s.sosEventId, "triggeredAt": iso.string(from: s.triggeredAt), "triggerMethod": s.triggerMethod,
                            "latitude": p["latitude"]!, "longitude": p["longitude"]!, "batteryLevel": s.batteryLevel,
                            "escalationState": s.acknowledgedBy == nil ? "hop2_allNotified" : "frozen",
                            "acknowledgedBy": s.acknowledgedBy.flatMap { dataset.user($0)?.displayName } ?? NSNull(),
                            "acknowledgedAt": s.acknowledgedAt.map { iso.string(from: $0) } ?? NSNull(),
                            "resolvedAt": NSNull(), "resolution": NSNull(), "trail": [] as [Any]])
        }
        let fallLat: Double = base.latitude + 470 / 111_000
        let fallLon: Double = base.longitude + 400 / (111_000 * cos(base.latitude * .pi / 180))
        let fallList: [[String: Any]] = demoFalls.filter { $0.detectedAt >= start }.map { f in
            var row: [String: Any] = ["detectedAt": iso.string(from: f.detectedAt), "latitude": fallLat, "longitude": fallLon]
            row["accuracy"] = 12
            row["batteryLevel"] = 0.82
            row["metrics"] = f.metrics
            row["outcome"] = f.outcome
            row["respondedAfterSec"] = f.respondedAfterSec.map { $0 as Any } ?? NSNull()
            row["sosEventId"] = NSNull()
            return row
        }
        points.sort { ($0["at"] as! String) < ($1["at"] as! String) }
        let checkinAt = at(95)
        let checkins: [[String: Any]] = checkinAt >= start ? [["at": iso.string(from: checkinAt), "latitude": points.first?["latitude"] ?? base.latitude,
                                                              "longitude": points.first?["longitude"] ?? base.longitude, "note": NSNull()]] : []
        var activity: [[String: Any]] = []
        for p in points {
            let act = (p["activity"] as? String) ?? "unknown"
            if var last = activity.last, last["activity"] as? String == act || act == "unknown" {
                last["end"] = p["at"]; last["points"] = (last["points"] as! Int) + 1
                activity[activity.count - 1] = last
            } else {
                activity.append(["activity": act, "start": p["at"]!, "end": p["at"]!, "distanceMeters": act == "walking" ? 1150 : 0, "points": 1])
            }
        }
        var gaps: [[String: Any]] = []
        var prev = start
        for p in points.compactMap({ ($0["at"] as? String).flatMap { iso.date(from: $0) } }) + [end] {
            if p.timeIntervalSince(prev) > 1800 {
                gaps.append(["from": iso.string(from: prev), "to": iso.string(from: p), "minutes": Int(p.timeIntervalSince(prev) / 60)])
            }
            prev = p
        }
        let reportId = "R-DEMO\(String(format: "%04X", Int.random(in: 0..<65536)))"
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        let code = String((0..<8).map { _ in alphabet.randomElement()! })
        let report: [String: Any] = [
            "reportId": reportId, "verifyCode": code, "generatedAt": iso.string(from: now),
            "generator": "Lantern Care incident report v1 (Explore Mode — sample data)",
            "purpose": body["purpose"] as? String ?? "other", "caseNumber": body["caseNumber"] as? String ?? NSNull(),
            "sections": body["sections"] as? [String] ?? [],
            "reporter": ["id": me, "name": reporter.displayName, "role": me == personId ? "self" : "guardian"],
            "person": ["id": personId, "name": person.displayName, "phone": person.phone.map { $0 as Any } ?? NSNull(), "timeZone": person.timeZone.identifier],
            "window": ["start": iso.string(from: start), "end": iso.string(from: end)],
            "sources": ["locationHistory": "ok", "sos": "ok", "falls": "ok", "trips": "ok", "checkins": "ok"],
            "summary": ["lastKnown": points.last.map { $0 as Any } ?? NSNull(), "lastCheckIn": checkins.last.map { $0 as Any } ?? NSNull(),
                        "lastBattery": ["at": iso.string(from: at(10)), "level": 0.82, "state": "unplugged"],
                        "counts": ["points": points.count, "sos": sosList.count, "falls": fallList.count, "checkins": checkins.count],
                        "thinned": false],
            "locations": points, "activity": activity, "gaps": gaps, "falls": fallList, "sos": sosList,
            "checkins": checkins, "events": [] as [Any],
            "battery": [["at": iso.string(from: at(10)), "level": 0.82, "state": "unplugged"]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .withoutEscapingSlashes]),
              let canonical = String(data: data, encoding: .utf8) else { return (500, json(["error": "demo report"])) }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (201, json(["reportId": reportId, "verifyCode": code, "dataSha256": hash, "canonical": canonical]))
    }
}
