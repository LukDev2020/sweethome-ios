import XCTest
@testable import ShouDeng

/// Rider onboarding (docs/rider-onboarding-plan.md): links, the setup checklist, the
/// forgotten-shift prompt, the on-device "riding for work?" suggestion, and Explore
/// Mode never touching the real shift.
@MainActor
final class RiderOnboardingTests: XCTestCase {

    // MARK: Links

    func testCrewLinksOpenTheCrewInAnyForm() {
        let forms = [
            "https://shoudeng.app/crew/abc123",
            "https://www.shoudeng.app/crew/ABC123",
            "https://shoudeng.app/crew/join?code=abc-123",
            "shoudeng://crew/join?code=ABC123",
        ]
        for f in forms {
            XCTAssertEqual(DeepLinkRouter.parse(url: URL(string: f)!), .crew(code: "ABC123"), f)
        }
        XCTAssertNil(DeepLinkRouter.parse(url: URL(string: "https://shoudeng.app/crew/ABC")!))
    }

    func testPartnerLinksChooseRider() {
        XCTAssertEqual(DeepLinkRouter.parse(url: URL(string: "https://shoudeng.app/start?for=rider&org=ab2cd3")!),
                       .riderStart(partnerCode: "AB2CD3"))
        XCTAssertEqual(DeepLinkRouter.parse(url: URL(string: "shoudeng://start?for=rider")!), .riderStart(partnerCode: nil))
        // A malformed partner code is dropped, the rider choice stays
        XCTAssertEqual(DeepLinkRouter.parse(url: URL(string: "https://shoudeng.app/start?for=rider&org=OOO111")!),
                       .riderStart(partnerCode: nil))
        XCTAssertNil(DeepLinkRouter.parse(url: URL(string: "https://shoudeng.app/start")!))
    }

    func testCrewQRIsAWebLinkThatWorksWithoutTheApp() {
        let crew = Crew(id: "c", name: "CBD", inviteCode: "ABC123", isOwner: true, members: [], cautions: [])
        XCTAssertEqual(crew.inviteURL.absoluteString, "https://shoudeng.app/crew/ABC123")
        XCTAssertEqual(DeepLinkRouter.parse(url: crew.inviteURL), .crew(code: "ABC123"))
    }

    // MARK: Checklist, shift, platforms

    func testChecklistEssentialsAreCrewWatcherAndLockCard() {
        var c = RiderChecklist(crew: true, watcher: true, lockCard: true, email: false, faceID: false)
        XCTAssertTrue(c.essentialsDone)
        XCTAssertEqual(c.doneCount, 3)
        c.watcher = false
        XCTAssertFalse(c.essentialsDone)
    }

    func testAShiftLongPastItsEndLooksForgotten() {
        let now = Date()
        XCTAssertFalse(AppCoordinator.shiftLooksForgotten(nil, now: now))
        XCTAssertFalse(AppCoordinator.shiftLooksForgotten(RiderShift(startedAt: now.addingTimeInterval(-3600), plannedEnd: now.addingTimeInterval(-20 * 60)), now: now))
        XCTAssertTrue(AppCoordinator.shiftLooksForgotten(RiderShift(startedAt: now.addingTimeInterval(-9 * 3600), plannedEnd: now.addingTimeInterval(-5 * 3600)), now: now))
        XCTAssertFalse(AppCoordinator.shiftLooksForgotten(RiderShift(startedAt: now.addingTimeInterval(-10 * 3600), plannedEnd: nil), now: now))
        XCTAssertTrue(AppCoordinator.shiftLooksForgotten(RiderShift(startedAt: now.addingTimeInterval(-15 * 3600), plannedEnd: nil), now: now))
    }

    func testPlatformsShowLocalOnesFirstAndEveryOneOnce() {
        let au = RiderPlatforms.forCountry("AU")
        XCTAssertEqual(Array(au.prefix(3)), ["ubereats", "doordash", "menulog"])
        XCTAssertEqual(Set(au), Set(RiderPlatforms.all))
        XCTAssertEqual(au.count, RiderPlatforms.all.count)
        XCTAssertEqual(au.last, "other")
        XCTAssertEqual(Array(RiderPlatforms.forCountry("CN").prefix(2)), ["meituan", "eleme"])
    }

    // MARK: "Riding for work?"

    private func day(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    func testThreeDaysOfLongRidesSuggestRiderMode() {
        var samples: [RiderSuggestion.Sample] = []
        for d in [2, 3, 5] {
            samples.append(.init(start: day(d, 18), cycling: true))
            samples.append(.init(start: day(d, 18, 45), cycling: false))
        }
        XCTAssertEqual(RiderSuggestion.ridingDays(samples, now: day(6, 12)), 3)
        XCTAssertTrue(RiderSuggestion.shouldSuggest(samples, now: day(6, 12)))
    }

    func testShortCommutesDoNot() {
        var samples: [RiderSuggestion.Sample] = []
        for d in 1...6 {
            samples.append(.init(start: day(d, 8), cycling: true))
            samples.append(.init(start: day(d, 8, 12), cycling: false))   // 12 minutes
        }
        XCTAssertEqual(RiderSuggestion.ridingDays(samples, now: day(7, 12)), 0)
        // Two long days only
        let two = [RiderSuggestion.Sample(start: day(2, 18), cycling: true), .init(start: day(2, 19), cycling: false),
                   .init(start: day(3, 18), cycling: true), .init(start: day(3, 19), cycling: false)]
        XCTAssertFalse(RiderSuggestion.shouldSuggest(two, now: day(6, 12)))
    }

    // MARK: Explore Mode never touches the real shift (the bug behind "On shift 8:53")

    func testDemoNeitherReadsNorWritesTheRealShift() async throws {
        ExploreModeController.shared.exit()
        let real = RiderShift(startedAt: Date().addingTimeInterval(-3600), plannedEnd: nil)
        let saved = UserDefaults.standard.data(forKey: "rider_shift")
        UserDefaults.standard.set(try JSONEncoder().encode(real), forKey: "rider_shift")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "rider_shift") } else { UserDefaults.standard.removeObject(forKey: "rider_shift") }
            ExploreModeController.shared.exit()
        }

        ExploreModeController.shared.start(role: .mom)
        let demo = try XCTUnwrap(ExploreModeController.shared.coordinator)
        XCTAssertNil(demo.riderShift, "the demo must not show the real shift")

        await demo.startShift(plannedEnd: nil)
        XCTAssertNotNil(demo.riderShift)
        let after = try XCTUnwrap(UserDefaults.standard.data(forKey: "rider_shift"))
        XCTAssertEqual(try JSONDecoder().decode(RiderShift.self, from: after), real, "the demo shift must stay in the demo")
    }
}
