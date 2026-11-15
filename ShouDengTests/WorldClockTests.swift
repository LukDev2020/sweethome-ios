import XCTest
@testable import ShouDeng

/// Home → world clocks: what the row shows, the choices kept, the city search.
@MainActor
final class WorldClockTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "WorldClockTests")!
        defaults.removePersistentDomain(forName: "WorldClockTests")
    }

    private let me = WorldClockEntry(id: "me", title: "Toronto", timeZone: TimeZone(identifier: "America/Toronto")!, isMe: true)
    private let mom = WorldClockEntry(id: "mom", title: "Chengdu", timeZone: TimeZone(identifier: "Asia/Shanghai")!, isMe: false)
    private let lucy = WorldClockEntry(id: "lucy", title: "Paris", timeZone: TimeZone(identifier: "Europe/Paris")!, isMe: false)

    func testRowIsMeThenFamilyThenAddedCities() {
        let s = WorldClockSettings(defaults: defaults)
        XCTAssertEqual(s.entries(me: me, family: [mom, lucy]).map(\.id), ["me", "mom", "lucy"])

        s.setMember("lucy", shown: false)
        XCTAssertTrue(s.add(WorldClockCity(name: "Tokyo", timeZoneId: "Asia/Tokyo")))
        XCTAssertEqual(s.entries(me: me, family: [mom, lucy]).map(\.title), ["Toronto", "Chengdu", "Tokyo"])
    }

    func testChoicesAreKeptUntilChanged() {
        let s = WorldClockSettings(defaults: defaults)
        s.setMember("mom", shown: false)
        s.add(WorldClockCity(name: "London", timeZoneId: "Europe/London"))
        s.add(WorldClockCity(name: "Tokyo", timeZoneId: "Asia/Tokyo"))
        s.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        let again = WorldClockSettings(defaults: defaults)   // the app opened again
        XCTAssertEqual(again.hiddenMemberIds, ["mom"])
        XCTAssertEqual(again.cities.map(\.name), ["Tokyo", "London"])

        again.setMember("mom", shown: true)
        again.remove(atOffsets: IndexSet(integer: 0))
        let third = WorldClockSettings(defaults: defaults)
        XCTAssertTrue(third.hiddenMemberIds.isEmpty)
        XCTAssertEqual(third.cities.map(\.name), ["London"])
    }

    func testAtMostFourCitiesNoDuplicatesNoUnknownZones() {
        let s = WorldClockSettings(defaults: defaults)
        for (name, id) in [("London", "Europe/London"), ("Tokyo", "Asia/Tokyo"), ("Sydney", "Australia/Sydney"), ("Dubai", "Asia/Dubai")] {
            XCTAssertTrue(s.add(WorldClockCity(name: name, timeZoneId: id)))
        }
        XCTAssertFalse(s.add(WorldClockCity(name: "Lima", timeZoneId: "America/Lima")), "max \(WorldClockSettings.maxCities)")
        s.remove(atOffsets: IndexSet(integer: 3))
        XCTAssertFalse(s.add(WorldClockCity(name: "London", timeZoneId: "Europe/London")), "already there")
        XCTAssertFalse(s.add(WorldClockCity(name: "Atlantis", timeZoneId: "Ocean/Atlantis")))
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
        s.add(WorldClockCity(name: "London", timeZoneId: "Europe/London"))
        ExploreMode.setActive(true)
        defer { ExploreMode.setActive(false) }
        s.load()
        XCTAssertTrue(s.cities.isEmpty, "the demo starts clean")
        s.add(WorldClockCity(name: "Tokyo", timeZoneId: "Asia/Tokyo"))
        ExploreMode.setActive(false)
        s.load()
        XCTAssertEqual(s.cities.map(\.name), ["London"], "the demo's city is gone, the real one is untouched")
    }
}
