import XCTest
@testable import ShouDeng

/// Mainland-China networks: primary (cloudfunctions.net) ↔ Hong Kong relay failover
/// (BaseURLFailover, APIClient, docs/ops/CHINA-RELAY.md).
final class RelayFailoverTests: XCTestCase {

    private let primary = "https://primary.test/api"
    private let relay = "https://relay.test"
    private var queue: OfflineQueue!
    private var client: APIClient!
    private var defaults: UserDefaults!
    private var suiteName = ""

    /// Hosts that fail in transit, and how.
    private var blocked: [String: URLError.Code] = [:]

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "relay-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        queue = OfflineQueue(fileURL: nil)
        blocked = [:]
        client = makeClient()
        StubURLProtocol.handler = { [weak self] req in
            if let code = self?.blocked[req.url?.host ?? ""] { throw URLError(code) }
            switch req.url?.path ?? "" {
            case let p where p.hasSuffix("/health"): return (200, Data(#"{"status":"ok"}"#.utf8))
            case let p where p.hasSuffix("/v1/sos/trigger"):
                return (201, Data(#"{"sosEventId":"srv-1","escalationState":"initiated"}"#.utf8))
            default: return (200, Data(#"{"ok":true}"#.utf8))
            }
        }
    }

    override func tearDown() {
        StubURLProtocol.reset()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeClient(relayURL: String? = "https://relay.test", hedge: TimeInterval = 2.5) -> APIClient {
        let c = APIClient(
            config: .init(baseURL: primary, maxRetries: 1, sosTimeoutInterval: 4, relayBaseURL: relayURL, sosHedgeDelay: hedge),
            offlineQueue: queue,
            sessionConfiguration: StubURLProtocol.session(),
            defaults: defaults
        )
        c.currentOwnerId = { "mom" }
        return c
    }

    private struct OK: Decodable { let ok: Bool }
    private struct Body: Encodable { var n = 1 }

    private func trigger() -> SOSTriggerRequest {
        SOSTriggerRequest(protectedPersonId: "mom", triggerMethod: .longPress, latitude: nil, longitude: nil,
                          batteryLevel: 0.5, clientSOSId: "local-sos-1", clientTriggeredAt: Date())
    }

    private func hosts(_ pathSuffix: String) -> [String] {
        StubURLProtocol.recorded.filter { $0.path.hasSuffix(pathSuffix) }.map(\.host)
    }

    /// Background route checks finish on their own time.
    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    // MARK: - Configuration

    func testNoRelayConfiguredMeansNoFailover() async {
        client = makeClient(relayURL: "")
        XCTAssertNil(client.route.relay)
        blocked = ["primary.test": .cannotConnectToHost]
        do {
            let _: OK = try await client.get("/v1/user/me")
            XCTFail("primary is blocked and there is no relay")
        } catch {}
        XCTAssertEqual(Set(hosts("/v1/user/me")), ["primary.test"])
        XCTAssertFalse(client.route.isUsingRelay)
    }

    func testBaseURLsAreTrimmedAndARelayEqualToThePrimaryIsIgnored() {
        let r = BaseURLFailover(primary: "https://a.test/api/", relay: " https://b.test/ ", defaults: defaults)
        XCTAssertEqual(r.primary, "https://a.test/api")
        XCTAssertEqual(r.relay, "https://b.test")
        XCTAssertNil(BaseURLFailover(primary: "https://a.test/api", relay: "https://a.test/api/", defaults: defaults).relay)
        XCTAssertEqual(r.alternate(to: "https://a.test/api"), "https://b.test")
        XCTAssertEqual(r.alternate(to: "https://b.test"), "https://a.test/api")
    }

    func testRebasingKeepsPathAndQuery() throws {
        let r = BaseURLFailover(primary: primary, relay: relay, defaults: defaults)
        let req = URLRequest(url: URL(string: "https://primary.test/api/v1/timeline?limit=5")!)
        XCTAssertEqual(r.rebased(req, to: relay)?.url?.absoluteString, "https://relay.test/v1/timeline?limit=5")
        let back = try XCTUnwrap(r.rebased(URLRequest(url: URL(string: "https://relay.test/v1/x")!), to: primary))
        XCTAssertEqual(back.url?.absoluteString, "https://primary.test/api/v1/x")
    }

    func testTransportFailureClassification() {
        XCTAssertEqual(BaseURLFailover.classify(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(BaseURLFailover.classify(URLError(.cannotFindHost)), .neverSent)
        XCTAssertEqual(BaseURLFailover.classify(URLError(.cannotConnectToHost)), .neverSent)
        XCTAssertEqual(BaseURLFailover.classify(URLError(.secureConnectionFailed)), .neverSent)
        XCTAssertEqual(BaseURLFailover.classify(URLError(.timedOut)), .ambiguous)
        XCTAssertEqual(BaseURLFailover.classify(URLError(.networkConnectionLost)), .ambiguous)
        XCTAssertEqual(BaseURLFailover.classify(URLError(.cancelled)), .other)
        XCTAssertEqual(BaseURLFailover.classify(APIError.serverError(500)), .other)
    }

    // MARK: - Ordinary requests

    func testBlockedPrimaryFailsOverToTheRelayAndRemembersIt() async throws {
        blocked = ["primary.test": .cannotConnectToHost]
        let first: OK = try await client.get("/v1/user/me")
        XCTAssertTrue(first.ok)
        XCTAssertEqual(hosts("/v1/user/me"), ["primary.test", "relay.test"])
        XCTAssertTrue(client.route.isUsingRelay)
        let until = try XCTUnwrap(client.route.relayPreferredUntil)
        XCTAssertEqual(until.timeIntervalSinceNow, BaseURLFailover.relayStickyInterval, accuracy: 60)

        // The next request goes straight to the relay
        let _: OK = try await client.get("/v1/timeline")
        XCTAssertEqual(hosts("/v1/timeline"), ["relay.test"])
    }

    func testTheChoiceSurvivesARestart() async throws {
        blocked = ["primary.test": .cannotConnectToHost]
        let _: OK = try await client.get("/v1/user/me")
        let restarted = makeClient()
        XCTAssertTrue(restarted.route.isUsingRelay)
        XCTAssertEqual(restarted.route.current, relay)
    }

    func testHTTPErrorsNeverFailOver() async {
        StubURLProtocol.handler = { _ in (500, Data()) }
        do {
            let _: OK = try await client.get("/v1/user/me")
            XCTFail("500 must surface")
        } catch {}
        XCTAssertEqual(Set(hosts("/v1/user/me")), ["primary.test"])
        XCTAssertFalse(client.route.isUsingRelay)
    }

    func testOfflineDoesNotSwitchToTheRelay() async {
        blocked = ["primary.test": .notConnectedToInternet, "relay.test": .notConnectedToInternet]
        do {
            let _: OK = try await client.get("/v1/user/me")
            XCTFail("offline")
        } catch {}
        XCTAssertEqual(Set(hosts("/v1/user/me")), ["primary.test"], "no point trying the relay with no network")
        XCTAssertFalse(client.route.isUsingRelay)
    }

    func testBothRoutesDownChangesNothing() async {
        blocked = ["primary.test": .cannotConnectToHost, "relay.test": .cannotConnectToHost]
        do {
            let _: OK = try await client.get("/v1/user/me")
            XCTFail("both down")
        } catch {}
        XCTAssertFalse(client.route.isUsingRelay)
    }

    func testRelayGatewayErrorIsNotLearned() async {
        blocked = ["primary.test": .cannotConnectToHost]
        StubURLProtocol.handler = { [weak self] req in
            if let code = self?.blocked[req.url?.host ?? ""] { throw URLError(code) }
            return (502, Data()) // relay up, backend not reachable from it
        }
        do {
            let _: OK = try await client.get("/v1/user/me")
            XCTFail("502")
        } catch {}
        XCTAssertFalse(client.route.isUsingRelay)
    }

    func testPOSTThatNeverLeftIsResentOnTheRelay() async throws {
        blocked = ["primary.test": .cannotFindHost]
        let r: OK = try await client.post("/v1/telemetry/checkin", body: Body())
        XCTAssertTrue(r.ok)
        XCTAssertEqual(hosts("/v1/telemetry/checkin"), ["primary.test", "relay.test"])
        XCTAssertTrue(client.route.isUsingRelay)
    }

    func testPOSTThatMayHaveArrivedIsNotResentButTheRouteIsChecked() async {
        blocked = ["primary.test": .timedOut]
        do {
            let _: OK = try await client.post("/v1/auth/refresh", body: Body())
            XCTFail("timed out")
        } catch {}
        XCTAssertEqual(hosts("/v1/auth/refresh"), ["primary.test"], "a refresh may have been applied: never resent")
        // GET /health on both routes in the background: primary silent, relay answers → relay
        await waitUntil { self.client.route.isUsingRelay }
        XCTAssertTrue(client.route.isUsingRelay)
        XCTAssertEqual(Set(hosts("/health")), ["primary.test", "relay.test"])
        XCTAssertEqual(StubURLProtocol.recorded.first { $0.path.hasSuffix("/health") }?.authorization, nil)
    }

    func testIdempotentRequestThatTimedOutIsRetriedOnTheRelay() async throws {
        blocked = ["primary.test": .timedOut]
        let _: OK = try await client.get("/v1/user/me")
        XCTAssertEqual(hosts("/v1/user/me"), ["primary.test", "relay.test"])
        XCTAssertTrue(client.route.isUsingRelay)
    }

    func testWhileOnTheRelayThePrimaryIsRecheckedAndUsedAgain() async throws {
        blocked = ["primary.test": .cannotConnectToHost]
        let _: OK = try await client.get("/v1/user/me")
        XCTAssertTrue(client.route.isUsingRelay)

        // The block lifts; the next relay request triggers the (hourly) background check
        blocked = [:]
        let _: OK = try await client.get("/v1/timeline")
        await waitUntil { !self.client.route.isUsingRelay }
        XCTAssertFalse(client.route.isUsingRelay)
        XCTAssertEqual(client.route.current, primary)
    }

    func testFailingRelayFallsBackToThePrimary() async throws {
        blocked = ["primary.test": .cannotConnectToHost]
        let _: OK = try await client.get("/v1/user/me")
        blocked = ["relay.test": .cannotConnectToHost]
        let _: OK = try await client.get("/v1/timeline")
        XCTAssertEqual(hosts("/v1/timeline"), ["relay.test", "primary.test"])
        XCTAssertFalse(client.route.isUsingRelay)
    }

    // MARK: - Remembering and re-checking (clock injected)

    func testRelayPreferenceExpiresAfter24Hours() {
        var now = Date()
        let r = BaseURLFailover(primary: primary, relay: relay, defaults: defaults, now: { now })
        r.failedInTransit(on: primary, thenAnswered: relay)
        XCTAssertEqual(r.current, relay)
        now += BaseURLFailover.relayStickyInterval - 60
        XCTAssertEqual(r.current, relay)
        now += 120
        XCTAssertEqual(r.current, primary)
    }

    func testFailedPrimaryRecheckReArmsThe24Hours() {
        var now = Date()
        let r = BaseURLFailover(primary: primary, relay: relay, defaults: defaults, now: { now })
        r.failedInTransit(on: primary, thenAnswered: relay)
        now += 20 * 3600
        r.recordCheck(primaryAnswered: false, relayAnswered: true)
        now += 20 * 3600
        XCTAssertTrue(r.isUsingRelay, "still blocked 20 h later: stay on the relay")
        r.recordCheck(primaryAnswered: true, relayAnswered: true)
        XCTAssertFalse(r.isUsingRelay)
    }

    func testRouteChecksAreThrottled() {
        var now = Date()
        let r = BaseURLFailover(primary: primary, relay: relay, defaults: defaults, now: { now })
        XCTAssertFalse(r.claimCheck(afterFailure: false), "on the primary there is nothing to re-check")
        XCTAssertTrue(r.claimCheck(afterFailure: true))
        XCTAssertFalse(r.claimCheck(afterFailure: true), "at most once a minute after failures")
        now += 61
        XCTAssertTrue(r.claimCheck(afterFailure: true))

        r.failedInTransit(on: primary, thenAnswered: relay)
        now += 61
        XCTAssertFalse(r.claimCheck(afterFailure: false), "the primary is re-checked at most hourly")
        now += 3600
        XCTAssertTrue(r.claimCheck(afterFailure: false))
        XCTAssertFalse(BaseURLFailover(primary: primary, relay: nil, defaults: defaults).claimCheck(afterFailure: true))
    }

    // MARK: - SOS

    func testSOSDoesNotWaitForABlackHoledPrimary() async {
        client = makeClient(hedge: 0.3)
        // DNS poisoned to an address that never answers: no error, just silence
        StubURLProtocol.delay = { $0.url?.host == "primary.test" ? 3 : 0 }
        let start = Date()
        let response: SOSTriggerResponse? = await client.postSOS("/v1/sos/trigger", body: trigger())
        XCTAssertEqual(response?.sosEventId, "srv-1")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "SOS went out on the relay after the hedge delay")
        XCTAssertTrue(queue.peekAll().isEmpty)
        XCTAssertEqual(hosts("/v1/sos/trigger"), ["primary.test", "relay.test"])
    }

    func testSOSFailsOverAtOnceWhenThePrimaryIsRefused() async {
        client = makeClient(hedge: 5)
        blocked = ["primary.test": .networkConnectionLost] // TLS reset by the firewall
        let start = Date()
        let response: SOSTriggerResponse? = await client.postSOS("/v1/sos/trigger", body: trigger())
        XCTAssertEqual(response?.sosEventId, "srv-1")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "no hedge wait after a transport failure")
        XCTAssertTrue(client.route.isUsingRelay, "SOS teaches the route too")
        XCTAssertTrue(queue.peekAll().isEmpty)
    }

    func testSOSOnAHealthyPrimaryNeverTouchesTheRelay() async {
        client = makeClient(hedge: 0.5)
        let response: SOSTriggerResponse? = await client.postSOS("/v1/sos/trigger", body: trigger())
        XCTAssertEqual(response?.sosEventId, "srv-1")
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(hosts("/v1/sos/trigger"), ["primary.test"])
    }

    func testSOSGoesToTheRelayFirstOnceKnown() async throws {
        blocked = ["primary.test": .cannotConnectToHost]
        let _: OK = try await client.get("/v1/user/me")
        StubURLProtocol.reset()
        StubURLProtocol.handler = { _ in (201, Data(#"{"sosEventId":"srv-2","escalationState":"initiated"}"#.utf8)) }
        let response: SOSTriggerResponse? = await client.postSOS("/v1/sos/trigger", body: trigger())
        XCTAssertEqual(response?.sosEventId, "srv-2")
        XCTAssertEqual(hosts("/v1/sos/trigger").first, "relay.test")
    }

    func testSOSStaysQueuedWhenBothRoutesFail() async {
        client = makeClient(hedge: 0.2)
        blocked = ["primary.test": .cannotConnectToHost, "relay.test": .cannotConnectToHost]
        let response: SOSTriggerResponse? = await client.postSOS("/v1/sos/trigger", body: trigger())
        XCTAssertNil(response)
        XCTAssertEqual(queue.peekAll().map(\.path), ["/v1/sos/trigger"])
        XCTAssertEqual(Set(hosts("/v1/sos/trigger")), ["primary.test", "relay.test"])
        XCTAssertFalse(client.route.isUsingRelay)
    }

    func testSOSRejectedByTheServerIsNotSentAgainOnTheRelay() async {
        client = makeClient(hedge: 0.2)
        StubURLProtocol.handler = { _ in (403, Data()) }
        let response: SOSTriggerResponse? = await client.postSOS("/v1/sos/trigger", body: trigger())
        XCTAssertNil(response)
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(hosts("/v1/sos/trigger"), ["primary.test"], "the server answered: the route works")
        XCTAssertTrue(queue.peekAll().isEmpty, "403 is permanent: dropped as before")
    }

    // MARK: - Offline queue

    func testQueuedItemsFlushThroughTheRelay() async {
        blocked = ["primary.test": .cannotConnectToHost, "relay.test": .notConnectedToInternet]
        client.postQueued("/v1/telemetry/location", body: Body())
        await waitUntil { StubURLProtocol.recorded.count >= 1 }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(queue.peekAll().count, 1)

        blocked = ["primary.test": .cannotConnectToHost]
        await client.flushOfflineQueue()
        XCTAssertTrue(queue.peekAll().isEmpty)
        XCTAssertEqual(hosts("/v1/telemetry/location").last, "relay.test")
        XCTAssertTrue(client.route.isUsingRelay)
    }

    func testQueuedItemThatTimedOutIsResentOnTheRelay() async {
        blocked = ["primary.test": .timedOut]
        let delivered = expectation(description: "delivered")
        client.postQueued("/v1/checkin", body: Body()) { ok in
            XCTAssertTrue(ok)
            delivered.fulfill()
        }
        await fulfillment(of: [delivered], timeout: 3)
        XCTAssertEqual(hosts("/v1/checkin"), ["primary.test", "relay.test"], "queued items are delivered at least once anyway")
        XCTAssertTrue(queue.peekAll().isEmpty)
    }
}
