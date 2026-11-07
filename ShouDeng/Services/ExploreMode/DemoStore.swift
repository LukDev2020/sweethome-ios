import Foundation
import CoreLocation

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
    /// Photos "uploaded" to the family circle, by id (kept in memory only).
    private var media: [String: Data] = [:]

    // Rider demo (Kai's phone): shift, crew, caution spots, crew answers
    private var kaiOnShift = false
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

        case ("GET", "/v1/guardian/protected-persons"):
            guard me == DemoDataset.sarahId else { return (200, json([])) }
            let rows = lock.withLock { [dataset.momPerson, dataset.dadPerson].map { statusRow($0) } }
            return (200, json(rows))

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
            let spot = Self.spot(of: personId)
            var status = SOSStatus(
                sosEventId: s.sosEventId, protectedPersonId: personId, personName: person.displayName,
                triggeredAt: s.triggeredAt, triggerMethod: "longPress",
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
