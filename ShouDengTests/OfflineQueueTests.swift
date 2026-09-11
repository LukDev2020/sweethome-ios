import XCTest
@testable import ShouDeng

final class OfflineQueueTests: XCTestCase {

    private var queue: OfflineQueue!

    override func setUp() {
        super.setUp()
        queue = OfflineQueue()
        // Clear any existing items
        _ = queue.dequeueAll()
    }

    override func tearDown() {
        _ = queue.dequeueAll()
        queue = nil
        super.tearDown()
    }

    // MARK: - Enqueue / Dequeue

    func testEnqueueAndDequeue() {
        let item = OfflineQueue.Item(
            method: "POST",
            path: "/v1/heartbeat",
            body: "{\"test\":true}".data(using: .utf8)
        )

        queue.enqueue(item)

        // Small delay for async disk write
        let exp = expectation(description: "wait for disk write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        let items = queue.dequeueAll()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].method, "POST")
        XCTAssertEqual(items[0].path, "/v1/heartbeat")
    }

    func testDequeueAllClearsQueue() {
        let item1 = OfflineQueue.Item(method: "POST", path: "/v1/a", body: nil)
        let item2 = OfflineQueue.Item(method: "POST", path: "/v1/b", body: nil)

        queue.enqueue(item1)
        queue.enqueue(item2)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        let items = queue.dequeueAll()
        XCTAssertEqual(items.count, 2)

        // After dequeue, queue should be empty
        let remaining = queue.dequeueAll()
        XCTAssertEqual(remaining.count, 0)
    }

    func testPendingCount() {
        XCTAssertEqual(queue.pendingCount, 0)

        queue.enqueue(OfflineQueue.Item(method: "POST", path: "/v1/test", body: nil))

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testItemHasUniqueId() {
        let item1 = OfflineQueue.Item(method: "POST", path: "/v1/a", body: nil)
        let item2 = OfflineQueue.Item(method: "POST", path: "/v1/a", body: nil)
        XCTAssertNotEqual(item1.id, item2.id)
    }

    func testItemSerializationRoundTrip() throws {
        let original = OfflineQueue.Item(
            method: "PUT",
            path: "/v1/user/me",
            body: "{\"name\":\"测试\"}".data(using: .utf8)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OfflineQueue.Item.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.method, original.method)
        XCTAssertEqual(decoded.path, original.path)
        XCTAssertEqual(decoded.body, original.body)
    }
}
