import XCTest
import UIKit
import SwiftUI
import ImageIO
@testable import ShouDeng

/// Family circle phase 1: the feed decodes lossily, the server list is the truth
/// (only unsent posts are kept locally), failed sends are marked and retried,
/// file:// links never reach the server, and photos are downsized.
@MainActor
final class FamilyFeedTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func json(_ s: String) -> Data { s.data(using: .utf8)! }

    private func makeCoordinator() async -> AppCoordinator {
        let coordinator = AppCoordinator(environment: .init(
            isDemo: true, // in-memory LocalStore; requests still go to the stub
            baseURL: "https://api.test",
            sessionConfiguration: StubURLProtocol.session(),
            offlineQueue: OfflineQueue(fileURL: nil),
            defaults: UserDefaults(suiteName: "family-feed-tests-\(UUID().uuidString)")!
        ))
        // Not signed in: nothing else (profile, guardians…) hits the stub. Let the
        // signed-out handler (which clears the feed) run before the test seeds it.
        try? await Task.sleep(nanoseconds: 100_000_000)
        StubURLProtocol.requests = []
        return coordinator
    }

    private func post(_ id: String, minutesAgo: Double, delivery: FamilyPostDelivery? = nil) -> FamilyPost {
        FamilyPost(id: id, authorId: "mom", authorName: "Mom", authorInitial: "M", authorAvatarPath: nil,
                   text: "post \(id)", mediaURLs: [], createdAt: Date().addingTimeInterval(-minutesAgo * 60),
                   comments: [], commentCount: 0, latitude: nil, longitude: nil, locationName: nil,
                   delivery: delivery)
    }

    private func requestBody(_ path: String) throws -> [String: Any] {
        let recorded = try XCTUnwrap(StubURLProtocol.requests.last { $0.method == "POST" && $0.path == path })
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(recorded.body)) as? [String: Any])
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Decoding

    func testOneMalformedPostDoesNotBlankTheFeed() async {
        StubURLProtocol.handler = { _ in (200, self.json(#"""
        [
          {"id":"p1","authorId":"sarah","authorName":"Sarah","authorInitial":"S","text":"Hi Mom",
           "mediaURLs":["https://storage.googleapis.com/b/1.jpg", 7],"createdAt":"2026-10-31T09:00:00.000Z",
           "comments":[{"id":"c1","authorId":"mom","authorName":"Mom","text":"Hi","createdAt":"2026-10-31T09:05:00.000Z"},
                       {"id":"broken"}],
           "commentCount":4,"latitude":30.65,"longitude":104.06,"locationName":"Chengdu"},
          {"authorId":"kevin","text":"no id"},
          {"id":"p2","authorId":"kevin","createdAt":"2026-10-31T08:00:00Z","commentCount":"lots","latitude":null}
        ]
        """#)) }
        let coordinator = await makeCoordinator()

        let ok = await coordinator.fetchFamilyPosts()

        XCTAssertTrue(ok)
        XCTAssertFalse(coordinator.familyFeedRefreshFailed)
        XCTAssertEqual(coordinator.familyPosts.map(\.id), ["p1", "p2"])
        let p1 = coordinator.familyPosts[0]
        XCTAssertEqual(p1.mediaURLs, ["https://storage.googleapis.com/b/1.jpg"])
        XCTAssertEqual(p1.comments.map(\.id), ["c1"])
        XCTAssertEqual(p1.comments.first?.authorInitial, "M", "missing initial falls back to the name")
        XCTAssertEqual(p1.commentCount, 4)
        XCTAssertEqual(p1.locationName, "Chengdu")
        XCTAssertEqual(p1.latitude, 30.65)
        let p2 = coordinator.familyPosts[1]
        XCTAssertEqual(p2.text, "")
        XCTAssertEqual(p2.authorName, "")
        XCTAssertEqual(p2.authorInitial, "?")
        XCTAssertEqual(p2.mediaURLs, [])
        XCTAssertEqual(p2.commentCount, 0)
        XCTAssertNil(p2.latitude)
        XCTAssertNil(p2.delivery)
    }

    func testFailedRefreshKeepsCachedPostsAndSaysSo() async {
        let coordinator = await makeCoordinator()
        coordinator.familyPosts = [post("cached", minutesAgo: 5)]
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        let ok = await coordinator.fetchFamilyPosts()

        XCTAssertFalse(ok)
        XCTAssertTrue(coordinator.familyFeedRefreshFailed)
        XCTAssertEqual(coordinator.familyPosts.map(\.id), ["cached"])

        StubURLProtocol.handler = { _ in (200, self.json("[]")) }
        _ = await coordinator.fetchFamilyPosts()
        XCTAssertFalse(coordinator.familyFeedRefreshFailed)
    }

    // MARK: - Merge

    func testMergeKeepsUnsentAndDropsWhatTheServerNoLongerHas() {
        let failed = FamilyPostDelivery(state: .failed, attempts: 1, pendingImages: [])
        var edited = post("both", minutesAgo: 30)
        edited.text = "edited on the server"
        let local = [
            post("unsent", minutesAgo: 1, delivery: failed),
            post("deletedByAuthor", minutesAgo: 10),
            post("both", minutesAgo: 30),
            post("justConfirmed", minutesAgo: 0.5),
        ]
        let merged = FamilyFeedSync.merge(server: [edited, post("new", minutesAgo: 20)], local: local,
                                          keep: ["justConfirmed"])

        XCTAssertEqual(merged.map(\.id), ["justConfirmed", "unsent", "new", "both"])
        XCTAssertEqual(merged.first { $0.id == "both" }?.text, "edited on the server", "server copy wins")
        XCTAssertEqual(merged.first { $0.id == "unsent" }?.delivery, failed)
        XCTAssertNil(merged.first { $0.id == "deletedByAuthor" })
    }

    func testMergeWithoutUnsentPostsIsTheServerList() {
        let merged = FamilyFeedSync.merge(server: [post("a", minutesAgo: 1)],
                                          local: [post("a", minutesAgo: 1), post("gone", minutesAgo: 2)])
        XCTAssertEqual(merged.map(\.id), ["a"])
    }

    // MARK: - Sending

    func testFileURLsAreNeverSentAndTheLocationIs() async throws {
        let coordinator = await makeCoordinator()
        var unsent = post("3F2504E0-4F89-11D3-9A0C-0305E82C3301", minutesAgo: 1,
                          delivery: FamilyPostDelivery(state: .failed))
        unsent.mediaURLs = ["file:///private/var/mobile/tmp/chat_1.jpg", "https://storage.googleapis.com/b/2.jpg"]
        unsent.latitude = 30.6586
        unsent.longitude = 104.0647
        unsent.locationName = "Chengdu"
        coordinator.familyPosts = [unsent]
        StubURLProtocol.handler = { req in
            req.url?.path == "/v1/family/posts" && req.httpMethod == "POST"
                ? (201, self.json(#"{"postId":"3F2504E0-4F89-11D3-9A0C-0305E82C3301"}"#))
                : (200, self.json("[]"))
        }

        let sent = await coordinator.deliverFamilyPost(id: unsent.id)

        XCTAssertTrue(sent)
        let body = try requestBody("/v1/family/posts")
        XCTAssertEqual(body["mediaURLs"] as? [String], ["https://storage.googleapis.com/b/2.jpg"])
        XCTAssertEqual(body["clientPostId"] as? String, unsent.id)
        XCTAssertEqual(body["latitude"] as? Double, 30.6586)
        XCTAssertEqual(body["longitude"] as? Double, 104.0647)
        XCTAssertEqual(body["locationName"] as? String, "Chengdu")
        let all = StubURLProtocol.requests.compactMap { $0.body.flatMap { String(data: $0, encoding: .utf8) } }
        XCTAssertFalse(all.contains { $0.contains("file:") }, "no request may carry a local path")
        XCTAssertNil(coordinator.familyPosts.first?.delivery)
        XCTAssertEqual(coordinator.familyPosts.first?.mediaURLs, ["https://storage.googleapis.com/b/2.jpg"])
    }

    func testFailedSendIsMarkedKeptThroughRefreshAndRetried() async {
        let coordinator = await makeCoordinator()
        StubURLProtocol.handler = { _ in (503, self.json(#"{"error":"down"}"#)) }

        let id = await coordinator.queueFamilyPost(text: "Home safe", images: [])
        XCTAssertNotNil(id)
        XCTAssertEqual(coordinator.familyPosts.first?.delivery?.state, .sending)
        await coordinator.sendFamilyPost(id: id!)

        XCTAssertEqual(coordinator.familyPosts.first?.delivery?.state, .failed, "shown as not sent, not as sent")
        XCTAssertEqual(coordinator.familyPosts.first?.delivery?.attempts, 1)

        // The server is back: the refresh keeps the unsent post, then retries it
        var created = false
        StubURLProtocol.handler = { req in
            if req.httpMethod == "POST" && req.url?.path == "/v1/family/posts" {
                created = true
                return (201, self.json(#"{"postId":"\#(id!)"}"#))
            }
            return (200, self.json("[]"))
        }
        let ok = await coordinator.fetchFamilyPosts()
        XCTAssertTrue(ok)
        XCTAssertEqual(coordinator.familyPosts.map(\.id), [id!])
        await waitUntil { coordinator.familyPosts.first?.delivery == nil }
        XCTAssertTrue(created)
        XCTAssertNil(coordinator.familyPosts.first?.delivery)
    }

    func testAutomaticRetriesStopAfterTheLimit() async {
        let coordinator = await makeCoordinator()
        coordinator.familyPosts = [post("given-up-0001", minutesAgo: 1, delivery: FamilyPostDelivery(
            state: .failed, attempts: FamilyFeedSync.maxAutomaticAttempts))]
        StubURLProtocol.handler = { _ in (201, self.json(#"{"postId":"given-up-0001"}"#)) }

        await coordinator.retryUnsentFamilyPosts(automatic: true)
        XCTAssertEqual(coordinator.familyPosts.first?.delivery?.state, .failed)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)

        await coordinator.sendFamilyPost(id: "given-up-0001") // the Retry button always works
        XCTAssertNil(coordinator.familyPosts.first(where: { $0.id == "given-up-0001" })?.delivery)
    }

    func testPhotosAreDownsizedUploadedThenPosted() async throws {
        let coordinator = await makeCoordinator()
        let photo = try XCTUnwrap(Self.photo(width: 4032, height: 3024).jpegData(compressionQuality: 0.95))
        StubURLProtocol.handler = { req in
            switch req.url?.path {
            case "/v1/family/upload": return (200, self.json(#"{"url":"https://storage.googleapis.com/b/family/mom/1.jpg"}"#))
            case "/v1/family/posts" where req.httpMethod == "POST": return (201, self.json(#"{"postId":"srv-1"}"#))
            default: return (200, self.json("[]"))
            }
        }

        let queued = await coordinator.queueFamilyPost(text: "", images: [photo])
        let id = try XCTUnwrap(queued)
        let pending = try XCTUnwrap(coordinator.familyPosts.first?.delivery?.pendingImages.first)
        let stored = try XCTUnwrap(coordinator.localStore.loadFamilyMedia(name: pending))
        XCTAssertLessThanOrEqual(Self.longEdge(stored), 1600)
        XCTAssertLessThan(stored.count, photo.count)

        let sent = await coordinator.deliverFamilyPost(id: id)

        XCTAssertTrue(sent)
        let upload = try requestBody("/v1/family/upload")
        XCTAssertEqual(upload["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual((upload["data"] as? String).flatMap { Data(base64Encoded: $0) }, stored)
        XCTAssertEqual(try requestBody("/v1/family/posts")["mediaURLs"] as? [String],
                       ["https://storage.googleapis.com/b/family/mom/1.jpg"])
        XCTAssertEqual(coordinator.familyPosts.first?.id, "srv-1")
        XCTAssertNil(coordinator.familyPosts.first?.delivery)
        XCTAssertNil(coordinator.localStore.loadFamilyMedia(name: pending), "the local copy is removed once uploaded")
    }

    func testFailedUploadKeepsThePhotoForRetry() async throws {
        let coordinator = await makeCoordinator()
        let photo = try XCTUnwrap(Self.photo(width: 800, height: 600).jpegData(compressionQuality: 0.9))
        StubURLProtocol.handler = { _ in (413, self.json(#"{"error":"File too large","code":"UPLOAD_TOO_LARGE"}"#)) }

        let queued = await coordinator.queueFamilyPost(text: "Look", images: [photo])
        let id = try XCTUnwrap(queued)
        await coordinator.sendFamilyPost(id: id)

        let post = try XCTUnwrap(coordinator.familyPosts.first)
        XCTAssertEqual(post.delivery?.state, .failed)
        XCTAssertEqual(post.delivery?.pendingImages.count, 1)
        XCTAssertNotNil(coordinator.localStore.loadFamilyMedia(name: post.delivery!.pendingImages[0]))
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.path == "/v1/family/posts" }, "no post without its photo")

        coordinator.deleteUnsentFamilyPost(id: id)
        XCTAssertTrue(coordinator.familyPosts.isEmpty)
    }

    // MARK: - Restoring older caches

    func testLegacyLocalOnlyPostsBecomeUnsent() {
        let legacy = post("6F9619FF-8B86-D011-B42D-00C04FC964FF", minutesAgo: 60)
        var legacyPhotoOnly = post("7F9619FF-8B86-D011-B42D-00C04FC964FF", minutesAgo: 50)
        legacyPhotoOnly.text = ""
        legacyPhotoOnly.mediaURLs = ["file:///tmp/gone.jpg"]
        let server = post("AbCdEfGhIjKlMnOpQrSt", minutesAgo: 40)
        var sending = post("8F9619FF-8B86-D011-B42D-00C04FC964FF", minutesAgo: 1,
                           delivery: FamilyPostDelivery(state: .sending))
        sending.text = "x"

        let migrated = FamilyFeedSync.legacyFailedSends([legacy, legacyPhotoOnly, server], myId: "mom") { _ in nil }
        XCTAssertEqual(migrated.map(\.id), [legacy.id, server.id], "a photo-only post whose file is gone is dropped")
        XCTAssertEqual(migrated[0].delivery?.state, .failed)
        XCTAssertNil(migrated[1].delivery)

        XCTAssertEqual(FamilyFeedSync.interruptedSendsFailed([sending]).first?.delivery?.state, .failed)
    }

    func testOnlyHTTPSLinksAreRemote() {
        XCTAssertEqual(FamilyFeedSync.remoteMediaURLs(
            ["file:///tmp/a.jpg", "https://x.test/b.jpg", "http://x.test/c.jpg", "/var/d.jpg", "HTTPS://x.test/e.jpg"]),
            ["https://x.test/b.jpg", "HTTPS://x.test/e.jpg"])
    }

    // MARK: - Explore Mode

    /// A demo coordinator wired like ExploreModeController.start(role: .mom).
    private func makeDemo() async -> (AppCoordinator, DemoStore) {
        let store = DemoStore(dataset: DemoDataset.build(), currentUserId: DemoDataset.momId)
        DemoURLProtocol.store = store
        let coordinator = AppCoordinator(environment: .init(
            isDemo: true,
            baseURL: DemoURLProtocol.baseURL,
            sessionConfiguration: DemoURLProtocol.sessionConfiguration(),
            offlineQueue: OfflineQueue(fileURL: nil),
            defaults: UserDefaults(suiteName: "family-feed-demo-\(UUID().uuidString)")!
        ))
        try? await Task.sleep(nanoseconds: 100_000_000)
        coordinator.beginDemoPersona(userId: DemoDataset.momId, role: .protected_)
        await waitUntil { coordinator.currentUser != nil }
        return (coordinator, store)
    }

    func testExploreModeFeedSendsPhotosAndReplies() async throws {
        let (coordinator, store) = await makeDemo()
        defer { DemoURLProtocol.store = nil }

        let ok = await coordinator.fetchFamilyPosts()
        XCTAssertTrue(ok)
        XCTAssertEqual(coordinator.familyPosts.map(\.id), ["demo-p1", "demo-p2", "demo-p3"])

        let photo = try XCTUnwrap(Self.photo(width: 2000, height: 1500).jpegData(compressionQuality: 0.9))
        let queued = await coordinator.queueFamilyPost(text: "Tea at the river", images: [photo])
        let id = try XCTUnwrap(queued)
        await coordinator.sendFamilyPost(id: id)

        let mine = try XCTUnwrap(coordinator.familyPosts.first)
        XCTAssertEqual(mine.id, id)
        XCTAssertNil(mine.delivery, "the demo accepts the post like the server would")
        XCTAssertEqual(mine.authorId, DemoDataset.momId)
        let url = try XCTUnwrap(mine.mediaURLs.first.flatMap(URL.init(string:)))
        XCTAssertEqual(url.host, DemoURLProtocol.host)
        XCTAssertNotNil(store.mediaData(for: url), "the photo is shown from the demo store")
        XCTAssertTrue(store.dataset.posts.contains { $0.id == id })

        let replied = await coordinator.addComment(postId: "demo-p2", text: "Sunday works!")
        XCTAssertTrue(replied)
        _ = await coordinator.fetchFamilyPosts()
        let p2 = try XCTUnwrap(coordinator.familyPosts.first { $0.id == "demo-p2" })
        XCTAssertEqual(p2.comments.last?.text, "Sunday works!")
        XCTAssertEqual(p2.commentCount, 1)
        XCTAssertTrue(DemoURLProtocol.violations.isEmpty, "nothing left the phone")
    }

    /// Renders the feed (Explore Mode data + a sent photo, an unsent post, the
    /// refresh banner, and the load-error state) to PNGs for a visual check. Runs
    /// only with TEST_RUNNER_FAMILY_FEED_SNAPSHOT=1.
    func testSnapshotExploreModeFeed() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FAMILY_FEED_SNAPSHOT"] == "1")
        let (coordinator, store) = await makeDemo()
        defer { DemoURLProtocol.store = nil }
        _ = await coordinator.fetchFamilyPosts()
        let photo = try XCTUnwrap(Self.photo(width: 2000, height: 1500).jpegData(compressionQuality: 0.9))
        if let id = await coordinator.queueFamilyPost(text: "Tea at the river", images: [photo]) {
            await coordinator.sendFamilyPost(id: id)
        }
        DemoURLProtocol.store = nil // "offline": the next send and refresh fail
        if let id = await coordinator.queueFamilyPost(text: "Back home now", images: []) {
            await coordinator.sendFamilyPost(id: id)
        }
        _ = await coordinator.fetchFamilyPosts()
        XCTAssertTrue(coordinator.familyFeedRefreshFailed)
        DemoURLProtocol.store = store // demo photos are read from the store
        try await snapshot(coordinator, name: "family-feed-explore")

        coordinator.familyPosts = []
        try await snapshot(coordinator, name: "family-feed-error")
    }

    private func snapshot(_ coordinator: AppCoordinator, name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: FamilyFeedView().environmentObject(coordinator))
        window.makeKeyAndVisible()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("[FamilyFeedTests] snapshot: \(url.path)")
        window.isHidden = true
    }

    // MARK: - Helpers

    private static func photo(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        }
    }

    private static func longEdge(_ jpeg: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return .max }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? .max
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? .max
        return max(w, h)
    }
}
