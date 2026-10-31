import XCTest
import Security
@testable import ShouDeng

/// Explore Mode merge gates:
///  1. a full scripted demo run makes zero requests outside DemoURLProtocol
///  2. real LocalStore / Keychain / OfflineQueue / App Group are byte-identical after a demo
///  3. demo fixtures decode with the app's own models (round trip)
///  (4. i18n completeness is LocalizationCompletenessTests)
@MainActor
final class ExploreModeTests: XCTestCase {

    private var escaped: [String] = []
    private let lock = NSLock()

    override func setUp() async throws {
        try await super.setUp()
        ExploreModeController.shared.exit()
        DemoURLProtocol.resetLog()
        escaped = []
        URLProtocol.registerClass(EscapeRecorder.self)
        EscapeRecorder.onRequest = { [weak self] url in
            self?.lock.withLock { self?.escaped.append("URLSession.shared → \(url)") }
        }
        APIClient.requestObserver = { [weak self] request in
            guard request.url?.host != DemoURLProtocol.host else { return }
            self?.lock.withLock { self?.escaped.append("APIClient → \(request.url?.absoluteString ?? "?")") }
        }
    }

    override func tearDown() async throws {
        ExploreModeController.shared.exit()
        URLProtocol.unregisterClass(EscapeRecorder.self)
        EscapeRecorder.onRequest = nil
        APIClient.requestObserver = nil
        try await super.tearDown()
    }

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition(), "condition not met within \(timeout)s", file: file, line: line)
    }

    // MARK: - 1. Network isolation over the whole scripted story

    func testScriptedDemoRunNeverLeavesTheDevice() async throws {
        let explore = ExploreModeController.shared
        explore.start(role: .mom)
        let demo = try XCTUnwrap(explore.coordinator)
        XCTAssertTrue(demo.isDemo)

        // Mom's phone loads the family
        await waitUntil { demo.myGuardians.count == 3 && demo.currentUser?.id == DemoDataset.momId }

        // Step 1: Home Safe → recorded by the demo store, "sent to Sarah, Kevin and Lucy"
        demo.performCheckIn()
        await waitUntil { explore.learned.contains(.homeSafe) }
        XCTAssertNotNil(explore.notification)

        // Step 3: practice SOS (3 s hold ends in triggerSOS)
        demo.triggerSOS(method: .longPress)
        await waitUntil { explore.store?.activeSOS(for: DemoDataset.momId) != nil }
        XCTAssertTrue(demo.isSOSScreenPresented)
        await waitUntil { demo.ownSOSStatus != nil }

        // Hand-off to Sarah: she sees Mom in Needs Attention with the SOS
        explore.continueToGuardian()
        await waitUntil { demo.userRole == .guardian && demo.guardianSOS[DemoDataset.momId] != nil }
        XCTAssertEqual(demo.protectedPersons.first { $0.id == DemoDataset.momId }?.status, .alert)
        explore.tapNotification()
        await waitUntil { demo.pendingAlertPersonId == DemoDataset.momId }

        // "I've got it" → acknowledged, then "Mom is safe"
        let sosId = try XCTUnwrap(demo.guardianSOS[DemoDataset.momId]?.sosEventId)
        try await demo.acknowledgeSOS(sosEventId: sosId)
        await waitUntil { explore.learned.contains(.respond) }
        await waitUntil { demo.guardianSOS[DemoDataset.momId]?.acknowledgedBy == DemoDataset.sarahId }
        try await demo.resolveSOSAsGuardian(sosEventId: sosId, personId: DemoDataset.momId)
        XCTAssertNil(explore.store?.activeSOS(for: DemoDataset.momId))

        // Scenario engine events + side switching
        explore.batteryDrops()
        explore.missedCheckIn()
        explore.switchRole(to: .mom)
        await waitUntil { demo.userRole == .protected_ }

        // Device features are refused, never started
        DeadManSwitchService.shared.start(seconds: 600)
        XCTAssertFalse(DeadManSwitchService.shared.isActive)

        explore.exit()
        XCTAssertFalse(ExploreMode.isActive)

        XCTAssertEqual(DemoURLProtocol.violations, [], "requests aimed at a real host")
        XCTAssertEqual(escaped, [], "requests that bypassed DemoURLProtocol")
        XCTAssertTrue(DemoURLProtocol.handled.contains("POST /v1/sos/trigger"))
        XCTAssertTrue(DemoURLProtocol.handled.contains("POST /v1/sos/acknowledge"))
        XCTAssertTrue(DemoURLProtocol.handled.contains("GET /v1/guardian/protected-persons"))
    }

    func testDemoSessionCannotReachARealHost() async {
        let config = DemoURLProtocol.sessionConfiguration()
        let session = URLSession(configuration: config)
        do {
            _ = try await session.data(from: URL(string: "https://api.example.com/v1/user/me")!)
            XCTFail("a non-demo host must fail")
        } catch {
            XCTAssertEqual(DemoURLProtocol.violations, ["https://api.example.com/v1/user/me"])
        }
    }

    // MARK: - 2. Real data untouched

    private struct Snapshot: Equatable {
        var files: [String: Data]
        var keychain: [String: Data]
        var appGroup: [String: String]
    }

    private func snapshot() -> Snapshot {
        let fm = FileManager.default
        var files: [String: Data] = [:]
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let store = docs.appendingPathComponent("store")
        for name in (try? fm.contentsOfDirectory(atPath: store.path)) ?? [] where !name.contains(".sb-") {
            files["store/\(name)"] = try? Data(contentsOf: store.appendingPathComponent(name))
        }
        files["offline_queue.jsonl"] = try? Data(contentsOf: OfflineQueue.defaultFileURL)
        if let mc = MedicalCardCache.fileURL { files["medical_card_cache.enc"] = try? Data(contentsOf: mc) }

        var keychain: [String: Data] = [:]
        for service in ["com.shoudeng.auth", "com.shoudeng.prefs"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnAttributes as String: true,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ]
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] {
                for item in items {
                    let account = item[kSecAttrAccount as String] as? String ?? "?"
                    keychain["\(service)/\(account)"] = item[kSecValueData as String] as? Data ?? Data()
                }
            }
        }

        var group: [String: String] = [:]
        // Only what is stored in the App Group's own domain (not the merged global domain)
        let groupDefaults = UserDefaults(suiteName: WidgetDataStore.appGroupId)
        groupDefaults?.synchronize()
        for (k, v) in groupDefaults?.persistentDomain(forName: WidgetDataStore.appGroupId) ?? [:] {
            group[k] = "\(v)"
        }
        return Snapshot(files: files, keychain: keychain, appGroup: group)
    }

    func testRealStorageIsByteIdenticalAfterADemo() async throws {
        // Real data that a careless demo could overwrite
        LocalStore.shared.saveTimeline([TimelineEntry(id: "real-1", timestamp: Date(timeIntervalSince1970: 1_800_000_000),
                                                      type: .checkIn, description: "real entry", detail: nil)])
        KeychainHelper.shared.save("sa_win", value: "45")
        // LocalStore writes are async (atomic: temp file, then rename) — wait for the
        // real entry to land instead of a fixed sleep, which raced the write.
        await waitUntil {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("store/timeline.json")
            return (try? String(contentsOf: url, encoding: .utf8))?.contains("real-1") == true
        }
        let before = snapshot()

        let explore = ExploreModeController.shared
        explore.start(role: .mom)
        let demo = try XCTUnwrap(explore.coordinator)
        await waitUntil { demo.currentUser?.id == DemoDataset.momId }

        // Everything the demo user might do that writes somewhere
        demo.performCheckIn()
        demo.triggerSOS(method: .longPress)
        demo.addTimelineEntry(type: .checkIn, description: "demo entry")
        KeychainHelper.shared.save("sa_win", value: "5")
        KeychainHelper.shared.save("demo-only", for: .duressCode)
        MedicalCardCache.save(MedicalCardData(bloodType: "O-"))
        WidgetDataStore.write(.empty)
        WidgetDataStore.writeLanguage("fr")
        explore.switchRole(to: .sarah)
        await waitUntil { demo.userRole == .guardian }
        demo.syncWidgetState()
        try? await Task.sleep(nanoseconds: 600_000_000)
        explore.exit()
        try? await Task.sleep(nanoseconds: 300_000_000)

        let after = snapshot()
        XCTAssertEqual(after.files, before.files, "LocalStore / OfflineQueue / medical cache changed")
        XCTAssertEqual(after.keychain, before.keychain, "keychain changed")
        XCTAssertEqual(after.appGroup, before.appGroup, "App Group defaults changed")
        XCTAssertEqual(KeychainHelper.shared.read("sa_win"), "45")
    }

    // MARK: - 3. Fixture round trip

    func testFixturesDecodeWithTheAppsModels() throws {
        let dataset = DemoDataset.build(now: Date(), language: .english)
        let store = DemoStore(dataset: dataset, currentUserId: DemoDataset.sarahId)
        let decoder = APIClient(config: .init(baseURL: DemoURLProtocol.baseURL), offlineQueue: OfflineQueue(fileURL: nil)).decoder
        func get(_ path: String, _ query: [String: String] = [:]) throws -> Data {
            let r = try XCTUnwrap(store.respond(method: "GET", path: path, query: query, body: nil), path)
            XCTAssertEqual(r.0, 200, path)
            return r.1
        }

        let profile = try decoder.decode(UserProfileResponse.self, from: get("/v1/user/me"))
        XCTAssertEqual(profile.displayName, "Sarah Chen")
        XCTAssertEqual(profile.timeZone, "America/Toronto")

        let persons = try decoder.decode([ProtectedPersonStatusResponse].self, from: get("/v1/guardian/protected-persons"))
        XCTAssertEqual(persons.map(\.personId), [DemoDataset.momId, DemoDataset.dadId])
        XCTAssertEqual(persons[0].cityName, "Chengdu")
        XCTAssertEqual(persons[1].batteryLevel, 0.17)
        XCTAssertNotNil(persons[0].lastCheckIn)
        XCTAssertNil(persons[0].activeSOS)

        store.triggerSOS(personId: DemoDataset.momId)
        let withSOS = try decoder.decode([ProtectedPersonStatusResponse].self, from: get("/v1/guardian/protected-persons"))
        XCTAssertEqual(withSOS[0].status, .alert)
        XCTAssertNotNil(withSOS[0].activeSOS)
        let active = try decoder.decode(ActiveSOSResponse.self, from: get("/v1/guardian/sos/active", ["personId": DemoDataset.momId]))
        XCTAssertTrue(active.active)
        XCTAssertEqual(active.sos?.personName, "Xiulan Chen")

        let posts = try decoder.decode([FamilyPost].self, from: get("/v1/family/posts"))
        XCTAssertEqual(posts.count, 3)
        let timeline = try decoder.decode(TimelineResponse.self, from: get("/v1/timeline"))
        XCTAssertEqual(timeline.entries.count, 4)

        store.currentUserId = DemoDataset.momId
        let guardians = try decoder.decode([Guardian].self, from: get("/v1/protected/guardians"))
        XCTAssertEqual(guardians.map(\.id), [DemoDataset.sarahId, DemoDataset.kevinId, DemoDataset.lucyId])
        XCTAssertEqual(guardians[2].user.timeZone.identifier, "Europe/Paris")

        XCTAssertNil(store.respond(method: "GET", path: "/v1/not-a-route", query: [:], body: nil))
    }

    func testDatasetIsLocalizedAndRelativeToNow() {
        let now = Date()
        let zh = DemoDataset.build(now: now, language: .chinese)
        XCTAssertEqual(zh.mom.displayName, "陈秀兰")
        XCTAssertEqual(zh.mom.cityName, "成都")
        let lastCheckIn = try? XCTUnwrap(zh.momPerson.lastCheckIn)
        XCTAssertEqual(lastCheckIn.map { now.timeIntervalSince($0) } ?? 0, 38 * 60, accuracy: 1)
    }
}

/// Records anything that goes through URLSession.shared / default protocol stack.
final class EscapeRecorder: URLProtocol {
    nonisolated(unsafe) static var onRequest: ((String) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool {
        onRequest?(request.url?.absoluteString ?? "?")
        return false
    }
}
