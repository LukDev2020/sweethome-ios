import XCTest
import UserNotifications
import CoreLocation
@testable import ShouDeng

/// W2-i: offline SOS delivery, queue ownership, retries, refresh re-entrancy.
final class SOSDeliveryTests: XCTestCase {

    private var queue: OfflineQueue!
    private var client: APIClient!
    private var owner: String? = "mom"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        queue = OfflineQueue(fileURL: nil) // in-memory
        client = APIClient(
            config: .init(baseURL: "https://api.test", sosTimeoutInterval: 4),
            offlineQueue: queue,
            sessionConfiguration: StubURLProtocol.session()
        )
        client.currentOwnerId = { [unowned self] in self.owner }
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func json(_ s: String) -> Data { s.data(using: .utf8)! }

    private func trigger(_ clientId: String) -> SOSTriggerRequest {
        SOSTriggerRequest(protectedPersonId: "mom", triggerMethod: .longPress, latitude: nil, longitude: nil,
                          batteryLevel: 0.5, clientSOSId: clientId, clientTriggeredAt: Date())
    }

    // MARK: - Dispositions

    func testDispositionKeepsSOSOn429And5xxAndDropsOnPermanentErrors() {
        XCTAssertEqual(APIClient.disposition(for: 201), .delivered)
        XCTAssertEqual(APIClient.disposition(for: 429), .stopFlush)
        XCTAssertEqual(APIClient.disposition(for: 503), .keep)
        XCTAssertEqual(APIClient.disposition(for: 401), .keep)
        XCTAssertEqual(APIClient.disposition(for: 400), .drop)
        XCTAssertEqual(APIClient.disposition(for: 403), .drop)
    }

    // MARK: - postSOS

    func testSOSIsPersistedFirstAndUsesShortTimeout() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let response: SOSTriggerResponse? = await client.postSOS("/v1/sos/trigger", body: trigger("local-1"))
        XCTAssertNil(response)
        XCTAssertEqual(queue.peekAll().map(\.path), ["/v1/sos/trigger"], "SOS must stay queued for retry")
        XCTAssertEqual(queue.peekAll().first?.ownerId, "mom")
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "POST is never retried on a transport error")
        XCTAssertEqual(StubURLProtocol.requests.first?.timeout, 4)
    }

    func testDeliveredSOSIsRemovedAndDecoded() async {
        StubURLProtocol.handler = { _ in (201, self.json(#"{"sosEventId":"srv-1","escalationState":"initiated"}"#)) }
        let response: SOSTriggerResponse? = await client.postSOS("/v1/sos/trigger", body: trigger("local-2"))
        XCTAssertEqual(response?.sosEventId, "srv-1")
        XCTAssertTrue(queue.peekAll().isEmpty)
    }

    func testUnknownEscalationStateDoesNotBreakTriggerResponse() async {
        StubURLProtocol.handler = { _ in (200, self.json(#"{"sosEventId":"srv-1","escalationState":"hop4_shareSent"}"#)) }
        let response: SOSTriggerResponse? = await client.postSOS("/v1/sos/trigger", body: trigger("local-3"))
        XCTAssertEqual(response?.escalationState, .hop4_shareSent)
        let odd = try? JSONDecoder().decode(EscalationState.self, from: json(#""somethingNew""#))
        XCTAssertEqual(odd, .unknown)
    }

    // MARK: - Flush

    func testFlushReplaysOnlyTheSignedInUsersItemsSOSFirst() async {
        queue.enqueue(.init(method: "POST", path: "/v1/heartbeat", body: json("{}"), ownerId: "mom"))
        queue.enqueue(.init(method: "POST", path: "/v1/sos/trigger", body: json(#"{"a":1}"#), ownerId: "mom"))
        queue.enqueue(.init(method: "POST", path: "/v1/sos/trigger", body: json(#"{"b":2}"#), ownerId: "dad"))
        StubURLProtocol.handler = { _ in (200, self.json("{}")) }
        var delivered: [OfflineQueue.Item] = []
        let exp = expectation(description: "delivered")
        client.onQueuedItemsDelivered = { delivered = $0; exp.fulfill() }

        await client.flushOfflineQueue()
        await fulfillment(of: [exp], timeout: 2)

        XCTAssertEqual(StubURLProtocol.requests.map(\.path), ["/v1/sos/trigger", "/v1/heartbeat"])
        XCTAssertEqual(delivered.map(\.path), ["/v1/sos/trigger", "/v1/heartbeat"])
        XCTAssertEqual(queue.peekAll().map(\.ownerId), ["dad"], "another account's SOS waits for that account")
    }

    func testRateLimitedFlushKeepsEverything() async {
        queue.enqueue(.init(method: "POST", path: "/v1/sos/trigger", body: json("{}"), ownerId: "mom"))
        queue.enqueue(.init(method: "POST", path: "/v1/heartbeat", body: json("{}"), ownerId: "mom"))
        StubURLProtocol.handler = { _ in (429, self.json("{}")) }
        await client.flushOfflineQueue()
        XCTAssertEqual(queue.pendingCount, 2)
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "stop at the first 429")
    }

    func testFlushRefreshesTokenOnceOn401ThenRetries() async {
        queue.enqueue(.init(method: "POST", path: "/v1/sos/trigger", body: json("{}"), ownerId: "mom"))
        var refreshed = 0
        client.onUnauthorized = { [unowned self] in
            refreshed += 1
            self.client.setAccessToken("new-token")
            return true
        }
        StubURLProtocol.handler = { req in
            req.value(forHTTPHeaderField: "Authorization") == "Bearer new-token" ? (200, Data("{}".utf8)) : (401, Data())
        }
        await client.flushOfflineQueue()
        XCTAssertEqual(refreshed, 1)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testNoFlushWithoutASignedInUser() async {
        owner = nil
        queue.enqueue(.init(method: "POST", path: "/v1/sos/trigger", body: json("{}"), ownerId: "mom"))
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        await client.flushOfflineQueue()
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    // MARK: - execute()

    func testPOSTIsNotRetriedOnDecodeError() async {
        StubURLProtocol.handler = { _ in (200, Data("not json".utf8)) }
        do {
            let _: SOSTriggerResponse = try await client.post("/v1/sos/trigger", body: trigger("x"))
            XCTFail("expected decoding error")
        } catch let error as APIError {
            guard case .decoding = error else { return XCTFail("got \(error)") }
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testRefreshCallNeverAwaitsItself() async {
        var unauthorizedCalls = 0
        client.onUnauthorized = { unauthorizedCalls += 1; return false }
        StubURLProtocol.handler = { _ in (401, Data()) }
        do {
            let _: AuthResponse = try await client.postWithoutRefresh("/v1/auth/refresh", body: RefreshRequest(refreshToken: "r"))
            XCTFail("expected 401")
        } catch {
            XCTAssertEqual(unauthorizedCalls, 0, "a 401 from /refresh must not trigger another refresh")
        }
    }

    func testOnlyDefinitiveRefreshFailuresLogOut() {
        XCTAssertTrue(AuthManager.refreshFailureIsDefinitive(APIError.unauthorized))
        XCTAssertTrue(AuthManager.refreshFailureIsDefinitive(APIError.forbidden))
        XCTAssertFalse(AuthManager.refreshFailureIsDefinitive(APIError.networkError(URLError(.timedOut))))
        XCTAssertFalse(AuthManager.refreshFailureIsDefinitive(APIError.serverError(503)))
        XCTAssertFalse(AuthManager.refreshFailureIsDefinitive(APIError.rateLimited))
        XCTAssertFalse(AuthManager.refreshFailureIsDefinitive(URLError(.notConnectedToInternet)))
    }

    // MARK: - Offline queue

    func testDuplicateEnqueueReturnsTheExistingIdSoItCanBeRemoved() {
        let first = queue.enqueue(.init(method: "POST", path: "/v1/sos/trigger", body: json("{}"), ownerId: "mom"))
        let second = queue.enqueue(.init(method: "POST", path: "/v1/sos/trigger", body: json("{}"), ownerId: "mom"))
        XCTAssertEqual(first, second)
        queue.removeItems(withIds: [second])
        XCTAssertEqual(queue.pendingCount, 0, "no stale copy left to replay after resolve")
    }

    func testRemoveWherePredicate() {
        queue.enqueue(.init(method: "POST", path: "/v1/sos/trigger", body: json(#"{"clientSOSId":"local-9"}"#), ownerId: "mom"))
        queue.enqueue(.init(method: "POST", path: "/v1/heartbeat", body: json("{}"), ownerId: "mom"))
        let removed = queue.removeItems { $0.path == "/v1/sos/trigger" }
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(queue.peekAll().map(\.path), ["/v1/heartbeat"])
    }

    func testQueueFileIsReadableWhileLocked() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("q-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let diskQueue = OfflineQueue(fileURL: url)
        diskQueue.enqueue(.init(method: "POST", path: "/v1/sos/trigger", body: nil, ownerId: "mom"))
        diskQueue.enqueue(.init(method: "POST", path: "/v1/heartbeat", body: nil, ownerId: "mom"))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        // Simulator file systems may not report protection; when they do it must not be .complete
        if let protection = attrs[.protectionKey] as? FileProtectionType {
            XCTAssertNotEqual(protection, .complete)
        }
        XCTAssertEqual(OfflineQueue(fileURL: url).pendingCount, 2, "survives a new instance (app relaunch)")
    }

    func testLegacyItemsWithoutOwnerStillDecode() throws {
        let legacy = #"{"id":"1","method":"POST","path":"/v1/sos/trigger","createdAt":"2026-10-30T12:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(OfflineQueue.Item.self, from: json(legacy))
        XCTAssertNil(item.ownerId)
        XCTAssertTrue(item.isSOS)
    }
}

/// W2-j: notification actions reach the right service.
final class NotificationRoutingTests: XCTestCase {

    private func handlers(_ log: @escaping (String) -> Void) -> PushService.ResponseHandlers {
        .init(
            sosTakenOver: { log("ack:\($0)") },
            checkIn: { log("checkin") },
            openSOSAlert: { log("open:\($0):\($1 ?? "-")") },
            deadManDismiss: { log("dms-dismiss") },
            deadManExtend: { log("dms-extend") },
            silentAlarmConfirm: { log("silent-safe") }
        )
    }

    private func route(_ action: String, category: String = "", userInfo: [AnyHashable: Any] = [:]) -> [String] {
        var log: [String] = []
        PushService.route(actionIdentifier: action, categoryIdentifier: category, userInfo: userInfo, handlers: handlers { log.append($0) })
        return log
    }

    func testGuardianTakeOverCallsAcknowledge() {
        XCTAssertEqual(route(PushService.actionTakenOver, userInfo: ["sos_id": "s1"]), ["ack:s1"])
    }

    func testTappingAnSOSPushOpensThatPersonsAlert() {
        XCTAssertEqual(route(UNNotificationDefaultActionIdentifier, category: "SOS_ALERT",
                             userInfo: ["action": "sos_alert", "sos_id": "s1", "person_id": "mom"]), ["open:mom:s1"])
    }

    func testDeadManAndSilentAlarmActionsAreHandled() {
        XCTAssertEqual(route("DMS_DISMISS"), ["dms-dismiss"])
        XCTAssertEqual(route("DMS_EXTEND_5"), ["dms-extend"])
        XCTAssertEqual(route(SilentAlarmService.confirmActionId), ["silent-safe"])
    }

    func testAllCategoriesCarryTheirActions() {
        let cats = DeadManSwitchService.notificationCategories()
            .union(SilentAlarmService.notificationCategories())
            .union(FakeCallService.notificationCategories())
        XCTAssertTrue(cats.contains { $0.identifier == "DMS_WARNING" && $0.actions.map(\.identifier) == ["DMS_DISMISS", "DMS_EXTEND_5"] })
        XCTAssertTrue(cats.contains { $0.identifier == "SILENT_ALARM_CHECKIN" })
        XCTAssertTrue(cats.contains { $0.identifier == "FAKE_CALL_INCOMING" })
    }
}

/// W2-j / W2-n / W2-b odds and ends.
final class SafetyPathTests: XCTestCase {

    func testDuressIsTheOnlySilentTrigger() {
        XCTAssertTrue(SOSTriggerMethod.duressPassword.isSilent)
        XCTAssertFalse(SOSTriggerMethod.longPress.isSilent)
        XCTAssertFalse(SOSTriggerMethod.deadManSwitch.isSilent)
    }

    /// The hold is 3 s (owner's choice, the 5 s cancel countdown follows); every text
    /// that names the hold must say the same.
    func testSOSHoldIsThreeSecondsAndTheCopySaysSo() throws {
        XCTAssertEqual(FloatingSOSButton.holdDuration, 3.0)
        let bundle = Bundle(for: AppCoordinator.self)
        for lang in ["en", "zh-Hans", "zh-Hant", "fr", "ja"] {
            let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: lang))
            let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
            for key in ["sos.button.holdHint", "home.sos.hold", "sos.button.a11yHint", "simple.sosHold",
                        "protected.settings.sos.longPress", "protected.home.sosHint"] {
                let text = try XCTUnwrap(table[key], "\(lang) \(key)")
                XCTAssertTrue(text.contains("3") || text.contains("三"), "\(lang) \(key): \(text)")
                XCTAssertFalse(text.contains("5") || text.contains("五"), "\(lang) \(key): \(text)")
            }
        }
    }

    func testLockScreenLocationButtonIsQueued() {
        _ = WidgetDataStore.takePendingActions()
        WidgetDataStore.enqueuePendingAction(.shareLocation)
        XCTAssertEqual(WidgetDataStore.takePendingActions(), [.shareLocation])
    }

    func testWidgetPendingActionsAreTakenOnceAndExpire() {
        _ = WidgetDataStore.takePendingActions()
        let now = Date()
        WidgetDataStore.enqueuePendingAction(.checkIn, at: now.addingTimeInterval(-30))
        WidgetDataStore.enqueuePendingAction(.arrived, at: now.addingTimeInterval(-3600))
        XCTAssertEqual(WidgetDataStore.takePendingActions(now: now), [.checkIn])
        XCTAssertEqual(WidgetDataStore.takePendingActions(now: now), [])
    }

    func testOvernightDutySlotSplitsAcrossDays() {
        // Calendar weekdays: 2 = Monday, 3 = Tuesday
        let slot = DutySlot(startHour: 22, endHour: 6, dayOfWeek: [2], isConfirmed: true)
        XCTAssertEqual(DutyScheduler.coveredHours(of: slot, today: 2, yesterday: 1), [22, 23])
        XCTAssertEqual(DutyScheduler.coveredHours(of: slot, today: 3, yesterday: 2), [0, 1, 2, 3, 4, 5])
        let lateSlot = DutySlot(startHour: 23, endHour: 24, dayOfWeek: [], isConfirmed: true)
        XCTAssertEqual(DutyScheduler.coveredHours(of: lateSlot, today: 5, yesterday: 4), [23])
    }

    func testCoverageUsesTheProtectedPersonsWeekday() {
        // 2026-10-30 23:30 UTC = Friday in Toronto but Saturday 07:30 in Chengdu
        let date = ISO8601DateFormatter().date(from: "2026-10-30T23:30:00Z")!
        let mom = User(id: "mom", displayName: "Mom", role: .protected_, avatarInitial: "M",
                       timeZone: TimeZone(identifier: "Asia/Shanghai")!, countryCode: "CN", cityName: "Chengdu", createdAt: date)
        let kevin = User(id: "kevin", displayName: "Kevin", role: .guardian, avatarInitial: "K",
                         timeZone: TimeZone(identifier: "Asia/Shanghai")!, countryCode: "CN", cityName: "Shanghai", createdAt: date)
        // Saturday-only (Calendar 7) 06-09 slot
        let g = Guardian(id: "kevin", user: kevin, permissions: .defaultPermissions, isOnDuty: false,
                         dutySchedule: DutySchedule(guardianId: "kevin", slots: [DutySlot(startHour: 6, endHour: 9, dayOfWeek: [7], isConfirmed: true)]),
                         averageResponseTime: 60, linkedSince: date)
        let person = ProtectedPerson(id: "mom", user: mom, guardians: [g], protectionLayers: 1, lastCheckIn: nil,
                                     lastKnownLocation: nil, batteryLevel: nil, batteryState: .unknown,
                                     lastPhoneActivity: nil, status: .normal)
        let coverage = DutyScheduler().buildDayCoverage(protectedPerson: person, guardians: [g], date: date)
        XCTAssertFalse(coverage.slots[7].isGap, "07:00 Saturday in Chengdu is covered")
    }

    func testUserDecodesTimeZoneAsStringOrObject() throws {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let a = try d.decode(User.self, from: Data(#"{"id":"k","displayName":"K","role":"guardian","avatarInitial":"K","timeZone":"Asia/Shanghai","countryCode":"CN","cityName":"S","createdAt":"2026-01-01T00:00:00Z"}"#.utf8))
        XCTAssertEqual(a.timeZone.identifier, "Asia/Shanghai")
        let b = try d.decode(User.self, from: Data(#"{"id":"k","displayName":"K","role":"guardian","timeZone":{"identifier":"Europe/Paris"}}"#.utf8))
        XCTAssertEqual(b.timeZone.identifier, "Europe/Paris")
        XCTAssertEqual(b.avatarInitial, "K")
    }

    func testLocationLeavesSOSModeAfterExit() {
        let manager = AdaptiveLocationManager()
        manager.enterSOSMode()
        XCTAssertEqual(manager.currentMode, .sos)
        manager.exitSOSMode()
        XCTAssertNotEqual(manager.currentMode, .sos, "exitSOSMode must not leave GPS at best accuracy forever")
    }

    func testKeychainDistinguishesMissingFromUnavailable() {
        KeychainHelper.shared.delete(.deviceSecret)
        XCTAssertEqual(KeychainHelper.shared.readResult(.deviceSecret), .notFound)
    }

    func testDuressCodeSurvivesLogoutWipe() {
        let had = KeychainHelper.shared.read(.duressCode)
        defer {
            if let had { KeychainHelper.shared.save(had, for: .duressCode) } else { KeychainHelper.shared.delete(.duressCode) }
        }
        let saved = (KeychainHelper.shared.read(.accessToken), KeychainHelper.shared.read(.refreshToken), KeychainHelper.shared.read(.userId))
        defer {
            if let v = saved.0 { KeychainHelper.shared.save(v, for: .accessToken) }
            if let v = saved.1 { KeychainHelper.shared.save(v, for: .refreshToken) }
            if let v = saved.2 { KeychainHelper.shared.save(v, for: .userId) }
        }
        KeychainHelper.shared.save("4321", for: .duressCode)
        KeychainHelper.shared.deleteAll()
        XCTAssertEqual(KeychainHelper.shared.read(.duressCode), "4321")
    }

    func testMedicalCardCacheRoundTripAndClear() {
        let previous = MedicalCardCache.fileURL
        MedicalCardCache.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("mc-\(UUID().uuidString).enc")
        defer { MedicalCardCache.clear(); MedicalCardCache.fileURL = previous }
        XCTAssertNil(MedicalCardCache.load())
        let card = MedicalCardData(bloodType: "A+", allergies: ["Penicillin"])
        MedicalCardCache.save(card)
        XCTAssertEqual(MedicalCardCache.load()?.bloodType, "A+")
        MedicalCardCache.clear()
        XCTAssertNil(MedicalCardCache.load())
    }

    // MARK: - Text fallback (server unreachable)

    func testTextFallbackOffersAfterFailureOrSilenceAndHidesOnceServerAnswers() {
        let t0 = Date()
        func offer(ended: Bool = false, reached: Bool = false, failed: Bool = false, after s: TimeInterval) -> Bool {
            SOSTextFallback.shouldOffer(ended: ended, reachedServer: reached, deliveryFailed: failed,
                                        triggeredAt: t0, now: t0.addingTimeInterval(s))
        }
        XCTAssertFalse(offer(after: 3), "still waiting for the first answer")
        XCTAssertTrue(offer(failed: true, after: 3), "delivery failed: offer at once")
        XCTAssertFalse(offer(after: 14.9))
        XCTAssertTrue(offer(after: SOSTextFallback.waitForServer), "no answer after 15 s")
        XCTAssertFalse(offer(reached: true, failed: true, after: 60), "server answered: hide it")
        XCTAssertFalse(offer(ended: true, failed: true, after: 60), "SOS ended: hide it")
        XCTAssertFalse(SOSTextFallback.shouldOffer(ended: false, reachedServer: false, deliveryFailed: false,
                                                   triggeredAt: nil, now: t0))
    }

    func testTextFallbackRecipientsSkipEmptyAndDuplicateNumbers() {
        XCTAssertEqual(SOSTextFallback.recipients(["+1 514-555-0101", nil, "  ", "+15145550101", " +86 138 0000 0000 "]),
                       ["+1 514-555-0101", "+86 138 0000 0000"])
        XCTAssertEqual(SOSTextFallback.recipients([]), [])
    }

    private let englishSMS: [String: String] = [
        "sos.sms.head": "SOS from %@. I need help.",
        "sos.sms.headNoName": "SOS. I need help.",
        "sos.sms.location": "Location: %1$@ (%2$@)",
        "sos.sms.noLocation": "Location unknown (%@)",
    ]

    func testTextFallbackMessageBodyHasNameMapLinkAndTimeWithZone() {
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let time = Date(timeIntervalSince1970: 1_794_117_900) // 2026-11-08 06:05 UTC = 14:05 in Shanghai
        let body = SOSTextFallback.messageBody(name: " Mei Chen ",
                                               coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                                               at: time, locale: Locale(identifier: "fr"), timeZone: shanghai,
                                               localize: { self.englishSMS[$0] ?? $0 })
        XCTAssertTrue(body.hasPrefix("SOS from Mei Chen. I need help. Location: https://maps.apple.com/?ll=31.23040,121.47370 ("), body)
        XCTAssertTrue(body.contains("14:05"), body)
        XCTAssertTrue(body.contains("UTC+8") || body.contains("GMT+8"), body)
        XCTAssertTrue(body.hasSuffix(")"), body)
        XCTAssertFalse(body.contains("%"), body)
        XCTAssertLessThan(body.count, 160, "fits one text in English")
    }

    func testTextFallbackMessageBodyWithoutNameOrLocation() {
        let body = SOSTextFallback.messageBody(name: "", coordinate: nil, at: Date(), locale: Locale(identifier: "en_US"),
                                               timeZone: .current, localize: { self.englishSMS[$0] ?? $0 })
        XCTAssertTrue(body.hasPrefix("SOS. I need help. Location unknown ("), body)
        let zero = SOSTextFallback.messageBody(name: "Mei", coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                               at: Date(), locale: Locale(identifier: "en_US"), timeZone: .current,
                                               localize: { self.englishSMS[$0] ?? $0 })
        XCTAssertTrue(zero.contains("Location unknown"), "0,0 is no fix")
    }

    func testTextFallbackStringsExistInEveryLanguage() {
        for lang in ["en", "zh-Hans", "zh-Hant", "fr", "ja"] {
            let bundle = Bundle(path: Bundle(for: AppCoordinator.self).path(forResource: lang, ofType: "lproj")!)!
            let body = SOSTextFallback.messageBody(name: "Mei", coordinate: CLLocationCoordinate2D(latitude: 31.2, longitude: 121.4),
                                                   at: Date(), locale: Locale(identifier: lang), timeZone: .current,
                                                   localize: { bundle.localizedString(forKey: $0, value: nil, table: nil) })
            XCTAssertTrue(body.contains("Mei") && body.contains("https://maps.apple.com/?ll=31.20000,121.40000"), "\(lang): \(body)")
            XCTAssertFalse(body.contains("sos.sms"), "\(lang): \(body)")
        }
    }
}
