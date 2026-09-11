import XCTest
@testable import ShouDeng

final class LocalStoreTests: XCTestCase {

    private var store: LocalStore!

    override func setUp() {
        super.setUp()
        store = LocalStore.shared
        store.clearAll()
        // Allow async clear to complete
        Thread.sleep(forTimeInterval: 0.1)
    }

    override func tearDown() {
        store.clearAll()
        Thread.sleep(forTimeInterval: 0.1)
        store = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeUser(id: String = "user-1", name: String = "Test") -> User {
        User(
            id: id,
            displayName: name,
            role: .protected_,
            avatarInitial: "T",
            timeZone: .current,
            countryCode: "CN",
            cityName: "Beijing",
            createdAt: Date()
        )
    }

    private func makeSOSEvent() -> SOSEvent {
        SOSEvent(
            id: "sos-1",
            protectedPersonId: "person-1",
            triggeredAt: Date(),
            triggerMethod: .longPress,
            location: nil,
            batteryLevel: 0.8,
            escalationState: .initiated,
            resolvedAt: nil,
            resolvedBy: nil,
            resolution: nil
        )
    }

    // MARK: - User Persistence

    func testSaveAndLoadCurrentUser() {
        let user = makeUser(id: "u-123", name: "Alice")
        store.saveCurrentUser(user)

        // Wait for async write
        Thread.sleep(forTimeInterval: 0.2)

        let loaded: User? = store.loadCurrentUser()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "u-123")
        XCTAssertEqual(loaded?.displayName, "Alice")
    }

    func testLoadCurrentUserWhenNoneReturnsNil() {
        let loaded = store.loadCurrentUser()
        XCTAssertNil(loaded)
    }

    // MARK: - User Role Persistence

    func testSaveAndLoadUserRole() {
        store.saveUserRole(.guardian)
        Thread.sleep(forTimeInterval: 0.2)

        let loaded = store.loadUserRole()
        XCTAssertEqual(loaded, .guardian)
    }

    func testSaveAndLoadProtectedRole() {
        store.saveUserRole(.protected_)
        Thread.sleep(forTimeInterval: 0.2)

        let loaded = store.loadUserRole()
        XCTAssertEqual(loaded, .protected_)
    }

    // MARK: - Guardians Persistence

    func testSaveAndLoadGuardians() {
        let guardians = [
            Guardian(
                id: "g-1",
                user: makeUser(id: "g-1", name: "Mom"),
                permissions: .defaultPermissions,
                isOnDuty: true,
                dutySchedule: nil,
                averageResponseTime: 30,
                linkedSince: Date()
            ),
        ]

        store.saveGuardians(guardians)
        Thread.sleep(forTimeInterval: 0.2)

        let loaded = store.loadGuardians()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "g-1")
        XCTAssertEqual(loaded.first?.user.displayName, "Mom")
        XCTAssertEqual(loaded.first?.isOnDuty, true)
    }

    func testLoadGuardiansWhenNoneReturnsEmptyArray() {
        let loaded = store.loadGuardians()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Active SOS Event

    func testSaveAndLoadActiveSOSEvent() {
        let event = makeSOSEvent()
        store.saveActiveSOSEvent(event)
        Thread.sleep(forTimeInterval: 0.2)

        let loaded = store.loadActiveSOSEvent()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "sos-1")
        XCTAssertEqual(loaded?.triggerMethod, .longPress)
        XCTAssertEqual(loaded?.escalationState, .initiated)
    }

    func testSaveNilClearsActiveSOSEvent() {
        store.saveActiveSOSEvent(makeSOSEvent())
        Thread.sleep(forTimeInterval: 0.2)

        store.saveActiveSOSEvent(nil)
        Thread.sleep(forTimeInterval: 0.2)

        let loaded = store.loadActiveSOSEvent()
        XCTAssertNil(loaded)
    }

    // MARK: - Timeline

    func testSaveAndLoadTimeline() {
        let entries = [
            TimelineEntry(
                id: "tl-1",
                timestamp: Date(),
                type: .checkIn,
                description: "Checked in at school",
                detail: nil
            ),
            TimelineEntry(
                id: "tl-2",
                timestamp: Date(),
                type: .enteredSafeZone,
                description: "Entered Home",
                detail: "Safe zone: Home"
            ),
        ]

        store.saveTimeline(entries)
        Thread.sleep(forTimeInterval: 0.2)

        let loaded = store.loadTimeline()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, "tl-1")
        XCTAssertEqual(loaded[0].type, .checkIn)
        XCTAssertEqual(loaded[1].type, .enteredSafeZone)
    }

    func testLoadTimelineWhenNoneReturnsEmptyArray() {
        let loaded = store.loadTimeline()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Clear All

    func testClearAllRemovesEverything() {
        store.saveCurrentUser(makeUser())
        store.saveUserRole(.guardian)
        store.saveActiveSOSEvent(makeSOSEvent())
        Thread.sleep(forTimeInterval: 0.2)

        store.clearAll()
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertNil(store.loadCurrentUser())
        XCTAssertNil(store.loadUserRole())
        XCTAssertNil(store.loadActiveSOSEvent())
        XCTAssertTrue(store.loadGuardians().isEmpty)
        XCTAssertTrue(store.loadTimeline().isEmpty)
    }

    // MARK: - Overwrite

    func testSavingOverwritesPreviousValue() {
        store.saveCurrentUser(makeUser(id: "u-1", name: "Alice"))
        Thread.sleep(forTimeInterval: 0.2)

        store.saveCurrentUser(makeUser(id: "u-2", name: "Bob"))
        Thread.sleep(forTimeInterval: 0.2)

        let loaded = store.loadCurrentUser()
        XCTAssertEqual(loaded?.id, "u-2")
        XCTAssertEqual(loaded?.displayName, "Bob")
    }
}
