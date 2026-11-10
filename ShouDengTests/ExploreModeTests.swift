import XCTest
import Security
import CoreLocation
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
        ExploreModeController.shared.clearInviteHandoff()
        ExploreModeController.shared.locator = DeviceDemoLocator()
        URLProtocol.unregisterClass(EscapeRecorder.self)
        EscapeRecorder.onRequest = nil
        APIClient.requestObserver = nil
        DemoURLProtocol.bodyObserver = nil
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
        // load() runs on the store's serial queue, so once it sees the entry the write
        // has finished (on disk, or in the overlay if a previous test left one active).
        await waitUntil { LocalStore.shared.loadTimeline().contains { $0.id == "real-1" } }
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
        // The real touches: the person's own location (map + weather) and a typed-in member
        explore.locator = FakeLocator(.success(Self.realFix))
        let r1 = await explore.showRealLocation()
        XCTAssertNil(r1)
        let r2 = await explore.useMyLocationForWeather()
        XCTAssertNil(r2)
        XCTAssertNotNil(explore.addMember(name: "Grandma Wu", role: .guardian))
        XCTAssertNotNil(explore.addMember(name: "Uncle Bo", role: .protected_))
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

        // Nothing of the demo is left in memory either
        XCTAssertNil(explore.realLocation)
        XCTAssertNil(explore.weatherLocation)
        XCTAssertEqual(explore.addedMembers, [])
        XCTAssertEqual(explore.inviteHandoff, [], "names only carry over with \"Invite your real family\"")
        XCTAssertNil(explore.store)
        XCTAssertNil(DemoURLProtocol.store)
        // A new demo starts with the sample family only, back in Chengdu
        explore.start(role: .mom)
        let again = try XCTUnwrap(explore.coordinator)
        XCTAssertEqual(explore.store?.addedMembers, [])
        XCTAssertEqual(again.locationManager.bestAvailableLocation?.coordinate.latitude ?? 0, DemoRole.mom.homeCoordinate.latitude, accuracy: 1e-6)
        explore.exit()
    }

    // MARK: - 4. Real touches

    /// A spot far from every sample city (Montréal), so it is easy to look for.
    static let realFix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 45.508765, longitude: -73.554321),
                                    altitude: 30, horizontalAccuracy: 15, verticalAccuracy: 10, timestamp: Date())

    func testRealLocationNeverLeavesTheDevice() async throws {
        var carried: [String] = []
        DemoURLProtocol.bodyObserver = { [weak self] key, body in
            guard let body, let text = String(data: body, encoding: .utf8), text.contains("45.5087") else { return }
            self?.lock.withLock { carried.append(key) }
        }
        let explore = ExploreModeController.shared
        explore.locator = FakeLocator(.success(Self.realFix))
        explore.start(role: .mom)
        let demo = try XCTUnwrap(explore.coordinator)
        await waitUntil { demo.currentUser?.id == DemoDataset.momId }

        // Before agreeing: the sample family's city, never the device
        XCTAssertEqual(demo.locationManager.bestAvailableLocation?.coordinate.latitude ?? 0, 30.6586, accuracy: 1e-4)

        // The weather's fix is for the weather only: Mom's pin stays in Chengdu
        let r3 = await explore.useMyLocationForWeather()
        XCTAssertNil(r3)
        XCTAssertEqual(explore.weatherLocation?.coordinate.latitude ?? 0, 45.508765, accuracy: 1e-6)
        XCTAssertEqual(demo.locationManager.bestAvailableLocation?.coordinate.latitude ?? 0, 30.6586, accuracy: 1e-4)

        // "Show me where I really am": her own pin and share location use the fix
        let r4 = await explore.showRealLocation()
        XCTAssertNil(r4)
        XCTAssertEqual(demo.locationManager.bestAvailableLocation?.coordinate.latitude ?? 0, 45.508765, accuracy: 1e-6)
        XCTAssertEqual(demo.locationService.currentLocation?.longitude ?? 0, -73.554321, accuracy: 1e-6)

        // Everything that would send a position
        demo.performCheckIn()
        demo.sendLocationToGuardians()
        demo.triggerSOS(method: .longPress)
        await waitUntil { explore.store?.activeSOS(for: DemoDataset.momId) != nil }
        try? await Task.sleep(nanoseconds: 800_000_000)

        // Sarah's phone (the demo's "server" side) still has Mom in Chengdu
        explore.switchRole(to: .sarah)
        await waitUntil { demo.protectedPersons.contains { $0.id == DemoDataset.momId } }
        let mom = try XCTUnwrap(demo.protectedPersons.first { $0.id == DemoDataset.momId })
        XCTAssertEqual(mom.lastKnownLocation?.latitude ?? 0, 30.6586, accuracy: 1e-3)
        XCTAssertEqual(demo.locationManager.bestAvailableLocation?.coordinate.latitude ?? 0,
                       DemoRole.sarah.homeCoordinate.latitude, accuracy: 1e-6, "Sarah's phone is in Toronto")
        let sarahView = try XCTUnwrap(explore.store?.respond(method: "GET", path: "/v1/guardian/protected-persons", query: [:], body: nil))
        XCTAssertFalse(String(decoding: sarahView.1, as: UTF8.self).contains("45.5087"))

        // Back on Mom's phone she is where the person really is
        explore.switchRole(to: .mom)
        XCTAssertEqual(demo.locationManager.bestAvailableLocation?.coordinate.latitude ?? 0, 45.508765, accuracy: 1e-6)
        explore.stopRealLocation()
        XCTAssertEqual(demo.locationManager.bestAvailableLocation?.coordinate.latitude ?? 0, 30.6586, accuracy: 1e-4)

        explore.exit()
        XCTAssertNil(explore.realLocation)
        XCTAssertNil(explore.weatherLocation)
        XCTAssertFalse(LiveWeatherStore.isCached(Self.realFix))

        // Every request was answered on the phone; none went to a real host
        XCTAssertEqual(DemoURLProtocol.violations, [], "requests aimed at a real host")
        XCTAssertEqual(escaped, [], "requests that bypassed DemoURLProtocol")
        XCTAssertTrue(DemoURLProtocol.handled.contains("POST /v1/checkin"))
        // The check-in carried the fix, and DemoURLProtocol (on the phone) is what got it
        XCTAssertTrue(lock.withLock { carried }.contains("POST /v1/checkin"), "\(lock.withLock { carried })")
    }

    func testLocationRefusedKeepsTheSampleCity() async throws {
        let explore = ExploreModeController.shared
        explore.locator = FakeLocator(.failure(DemoLocateError.denied))
        explore.start(role: .mom)
        let demo = try XCTUnwrap(explore.coordinator)
        let refused = await explore.showRealLocation()
        XCTAssertEqual(refused, .denied)
        let weatherRefused = await explore.useMyLocationForWeather()
        XCTAssertEqual(weatherRefused, .denied)
        XCTAssertNil(explore.realLocation)
        XCTAssertNil(explore.weatherLocation)
        XCTAssertEqual(demo.locationManager.bestAvailableLocation?.coordinate.latitude ?? 0, 30.6586, accuracy: 1e-4)
    }

    func testMemberAddedInTheDemoAppearsInDemoStoreResponses() throws {
        let store = DemoStore(dataset: DemoDataset.build(now: Date(), language: .english), currentUserId: DemoDataset.sarahId)
        let decoder = APIClient(config: .init(baseURL: DemoURLProtocol.baseURL), offlineQueue: OfflineQueue(fileURL: nil)).decoder
        func get(_ path: String, _ query: [String: String] = [:]) throws -> Data {
            let r = try XCTUnwrap(store.respond(method: "GET", path: path, query: query, body: nil), path)
            XCTAssertEqual(r.0, 200, path)
            return r.1
        }

        XCTAssertNil(store.addMember(name: "   ", role: .guardian), "a name is needed")

        // Someone to protect: on Sarah's family list, near the family's home in Chengdu
        let uncle = try XCTUnwrap(store.addMember(name: "  Uncle Bo ", role: .protected_))
        XCTAssertEqual(uncle.name, "Uncle Bo")
        let persons = try decoder.decode([ProtectedPersonStatusResponse].self, from: get("/v1/guardian/protected-persons"))
        let row = try XCTUnwrap(persons.first { $0.personId == uncle.id })
        XCTAssertEqual(persons.count, 3)
        XCTAssertEqual(row.displayName, "Uncle Bo")
        XCTAssertNil(row.phone, "no number: nothing could be texted or called")
        let home = CLLocation(latitude: 30.6586, longitude: 104.0647)
        let spot = CLLocation(latitude: try XCTUnwrap(row.latitude), longitude: try XCTUnwrap(row.longitude))
        XCTAssertLessThan(spot.distance(from: home), 3000)
        XCTAssertGreaterThan(spot.distance(from: home), 300, "not on top of Mom's pin")
        let circle = try decoder.decode([Guardian].self, from: get("/v1/guardian/circle", ["personId": uncle.id]))
        XCTAssertEqual(circle.map(\.id), [DemoDataset.sarahId, DemoDataset.kevinId])

        // ...who can send a practice SOS that Sarah receives
        store.triggerSOS(personId: uncle.id)
        let active = try decoder.decode(ActiveSOSResponse.self, from: get("/v1/guardian/sos/active", ["personId": uncle.id]))
        XCTAssertTrue(active.active)
        XCTAssertEqual(active.sos?.personName, "Uncle Bo")
        XCTAssertEqual(active.sos?.latitude ?? 0, spot.coordinate.latitude, accuracy: 1e-9)
        let alerting = try decoder.decode([ProtectedPersonStatusResponse].self, from: get("/v1/guardian/protected-persons"))
        XCTAssertEqual(alerting.first { $0.personId == uncle.id }?.status, .alert)

        // A guardian: in Mom's circle, told about her check-in and her practice SOS
        let grandma = try XCTUnwrap(store.addMember(name: "Grandma Wu", role: .guardian))
        store.currentUserId = DemoDataset.momId
        let guardians = try decoder.decode([Guardian].self, from: get("/v1/protected/guardians"))
        XCTAssertEqual(guardians.map(\.id), [DemoDataset.sarahId, DemoDataset.kevinId, DemoDataset.lucyId, grandma.id])
        XCTAssertEqual(guardians.last?.user.displayName, "Grandma Wu")
        XCTAssertNil(guardians.last?.user.phone)
        let checkIn = try XCTUnwrap(store.respond(method: "POST", path: "/v1/checkin", query: [:], body: Data("{}".utf8)))
        let told = try JSONSerialization.jsonObject(with: checkIn.1) as? [String: Any]
        XCTAssertEqual(told?["guardiansNotified"] as? Int, 4)
        store.triggerSOS(personId: DemoDataset.momId)
        let momSOS = try XCTUnwrap(store.sosStatus(personId: DemoDataset.momId, now: Date().addingTimeInterval(45)))
        XCTAssertEqual(momSOS.guardiansNotified, 4)

        // The demo stays small
        for i in 0..<10 { store.addMember(name: "Cousin \(i)", role: .guardian) }
        XCTAssertEqual(store.addedMembers.count, DemoStore.maxAddedMembers)
    }

    func testAddedPersonOnTheGuardianPhoneAndTheInviteHandoff() async throws {
        let explore = ExploreModeController.shared
        explore.start(role: .sarah)
        let demo = try XCTUnwrap(explore.coordinator)
        await waitUntil { demo.protectedPersons.count == 2 }

        let uncle = try XCTUnwrap(explore.addMember(name: "Uncle Bo", role: .protected_))
        explore.addMember(name: "Grandma Wu", role: .guardian)
        await waitUntil { demo.protectedPersons.contains { $0.id == uncle.id && $0.user.displayName == "Uncle Bo" } }

        // His practice SOS reaches Sarah's phone
        explore.practiceSOS(from: uncle.id)
        await waitUntil { demo.guardianSOS[uncle.id] != nil }
        XCTAssertEqual(explore.notification?.action, .openAlert(personId: uncle.id))

        // "Ready to invite your real family?" → the names (and sides) go to sign-up, in memory
        var signupOpened = false
        let previous = explore.onSetUpRealFamily
        explore.onSetUpRealFamily = { signupOpened = true }
        defer { explore.onSetUpRealFamily = previous }
        explore.inviteRealFamily()
        XCTAssertFalse(ExploreMode.isActive)
        XCTAssertTrue(signupOpened)
        XCTAssertEqual(explore.inviteHandoff, [DemoInvitee(name: "Uncle Bo", role: .protected_),
                                               DemoInvitee(name: "Grandma Wu", role: .guardian)])
        // A guardian's invite makes me the protected one, and the other way round
        XCTAssertEqual(explore.inviteHandoff.map(\.inviterRole), [.guardian, .protected_])
        XCTAssertEqual(DemoURLProtocol.violations, [])
        XCTAssertEqual(escaped, [])
        XCTAssertFalse(DemoURLProtocol.handled.contains { $0.contains("/v1/invite") }, "no invite was created")
        explore.clearInviteHandoff()
        XCTAssertEqual(explore.inviteHandoff, [])
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
        // Sarah's own timeline is empty; Mom's (shown in Sarah's Records, named) has the SOS
        let timeline = try decoder.decode(TimelineResponse.self, from: get("/v1/timeline"))
        XCTAssertEqual(timeline.entries.count, 0)
        let momTimeline = try decoder.decode(TimelineResponse.self, from: get("/v1/timeline", ["personId": DemoDataset.momId]))
        XCTAssertEqual(momTimeline.entries.count, 5)
        XCTAssertEqual(momTimeline.entries.first?.type, .sosTriggered)

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

/// Hands out a fixed "real" location (or refuses), instead of the device's.
@MainActor
final class FakeLocator: DemoLocating {
    let result: Result<CLLocation, Error>
    init(_ result: Result<CLLocation, Error>) { self.result = result }
    func locateOnce() async throws -> CLLocation { try result.get() }
}

/// Records anything that goes through URLSession.shared / default protocol stack.
final class EscapeRecorder: URLProtocol {
    nonisolated(unsafe) static var onRequest: ((String) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool {
        onRequest?(request.url?.absoluteString ?? "?")
        return false
    }
}
