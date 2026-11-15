import XCTest
@testable import ShouDeng

/// Home → world clocks: the row is the person's own choice of cities; until they
/// change it, it shows their city and their family's.
@MainActor
final class WorldClockTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "WorldClockTests")!
        defaults.removePersistentDomain(forName: "WorldClockTests")
    }

    private let me = WorldClockEntry(id: "me", title: "Toronto", timeZone: TimeZone(identifier: "America/Toronto")!, isMe: true)
    private let mom = WorldClockEntry(id: "mom", title: "Chengdu", timeZone: TimeZone(identifier: "Asia/Shanghai")!, isMe: false, person: "Mom")
    private let lucy = WorldClockEntry(id: "lucy", title: "Paris", timeZone: TimeZone(identifier: "Europe/Paris")!, isMe: false, person: "Lucy")
    private let tokyo = WorldClockCity(name: "Tokyo", timeZoneId: "Asia/Tokyo")

    func testUntouchedRowIsMeAndFamily() {
        let s = WorldClockSettings(defaults: defaults)
        XCTAssertFalse(s.isCustomized)
        XCTAssertEqual(s.entries(me: me, family: [mom, lucy]).map(\.title), ["Toronto", "Chengdu", "Paris"])
    }

    func testAnyCityAnyOrderFamilyAndMeAreOptional() {
        let s = WorldClockSettings(defaults: defaults)
        XCTAssertTrue(s.add(tokyo, me: me, family: [mom, lucy]))
        XCTAssertTrue(s.isCustomized, "the first change makes it the person's own list")
        XCTAssertEqual(s.entries(me: me, family: [mom, lucy]).map(\.title), ["Toronto", "Chengdu", "Paris", "Tokyo"])

        // Remove my own clock and Mom's, put Tokyo first
        s.remove(atOffsets: IndexSet([0, 1]), me: me, family: [mom, lucy])
        s.move(fromOffsets: IndexSet(integer: 1), toOffset: 0, me: me, family: [mom, lucy])
        XCTAssertEqual(s.entries(me: me, family: [mom, lucy]).map(\.title), ["Tokyo", "Paris"])

        // A new family member doesn't sneak into a chosen list
        let kevin = WorldClockEntry(id: "kevin", title: "Shanghai", timeZone: TimeZone(identifier: "Asia/Shanghai")!, isMe: false)
        XCTAssertEqual(s.entries(me: me, family: [mom, lucy, kevin]).map(\.title), ["Tokyo", "Paris"])

        s.addMe(me, family: [mom, lucy])
        XCTAssertEqual(s.entries(me: me, family: [mom, lucy]).first?.isMe, true, "my own time back, first")
    }

    func testMyClockFollowsWhereIAm() {
        let s = WorldClockSettings(defaults: defaults)
        s.add(tokyo, me: me, family: [])
        let moved = WorldClockEntry(id: "me", title: "Vancouver", timeZone: TimeZone(identifier: "America/Vancouver")!, isMe: true)
        let row = s.entries(me: moved, family: [])
        XCTAssertEqual(row.first?.title, "Vancouver")
        XCTAssertEqual(row.first?.timeZone.identifier, "America/Vancouver")
    }

    func testTheListIsKeptUntilChangedAndCanGoBack() {
        let s = WorldClockSettings(defaults: defaults)
        s.add(tokyo, me: me, family: [mom])
        s.remove(atOffsets: IndexSet(integer: 1), me: me, family: [mom])
        let again = WorldClockSettings(defaults: defaults)   // the app opened again
        XCTAssertEqual(again.entries(me: me, family: [mom]).map(\.title), ["Toronto", "Tokyo"])
        again.reset()
        XCTAssertFalse(WorldClockSettings(defaults: defaults).isCustomized)
        XCTAssertEqual(again.entries(me: me, family: [mom]).map(\.title), ["Toronto", "Chengdu"])
    }

    func testAtMostEightNoDuplicatesNoUnknownZones() {
        let s = WorldClockSettings(defaults: defaults)
        let zones = ["Europe/London", "Asia/Tokyo", "Australia/Sydney", "Asia/Dubai", "America/Lima",
                     "Africa/Cairo", "Asia/Kolkata", "Europe/Berlin"]
        for id in zones { XCTAssertTrue(s.add(WorldClockCity(name: id, timeZoneId: id), me: nil, family: [])) }
        XCTAssertFalse(s.add(WorldClockCity(name: "Lagos", timeZoneId: "Africa/Lagos"), me: nil, family: []),
                       "max \(WorldClockSettings.maxClocks)")
        s.remove(atOffsets: IndexSet(integer: 0), me: nil, family: [])
        XCTAssertFalse(s.add(WorldClockCity(name: "Asia/Tokyo", timeZoneId: "Asia/Tokyo"), me: nil, family: []), "already there")
        XCTAssertFalse(s.add(WorldClockCity(name: "Atlantis", timeZoneId: "Ocean/Atlantis"), me: nil, family: []))
    }

    func testOfflineCitySearchFromTheTimeZoneDatabase() {
        XCTAssertTrue(WorldClockSettings.timeZoneMatches("shang").contains { $0.timeZoneId == "Asia/Shanghai" })
        XCTAssertTrue(WorldClockSettings.timeZoneMatches("New York").contains { $0.name == "New York" })
        XCTAssertTrue(WorldClockSettings.timeZoneMatches("x").isEmpty, "two letters at least")
    }

    func testTimeTextAndOffset() {
        let date = ISO8601DateFormatter().date(from: "2026-11-15T12:00:00Z")!
        XCTAssertEqual(WorldClockFormat.time(TimeZone(identifier: "Asia/Shanghai")!, at: date), "20:00")
        XCTAssertEqual(WorldClockFormat.time(TimeZone(identifier: "Asia/Kolkata")!, at: date), "17:30")
        XCTAssertEqual(WorldClockFormat.offset(.current, at: date), "±0 h")
    }

    func testTheDemoNeverChangesTheRealChoices() {
        let s = WorldClockSettings(defaults: defaults)
        s.add(tokyo, me: nil, family: [])
        ExploreMode.setActive(true)
        defer { ExploreMode.setActive(false) }
        s.load()
        XCTAssertFalse(s.isCustomized, "the demo starts with the automatic row")
        s.add(WorldClockCity(name: "London", timeZoneId: "Europe/London"), me: nil, family: [])
        ExploreMode.setActive(false)
        s.load()
        XCTAssertEqual(s.clocks.map(\.name), ["Tokyo"], "the demo's city is gone, the real list is untouched")
    }
}
