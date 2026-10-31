import XCTest
import SwiftUI
@testable import ShouDeng

/// iPhone Duo: two-pane split at the fold, and state kept when folding/unfolding.
@MainActor
final class DuoLayoutTests: XCTestCase {

    // MARK: - Split at the fold

    func testWithoutAFoldThePanesAreHalfAndHalf() {
        let layout = FoldSplitLayout.resolve(width: 669, division: nil)
        XCTAssertEqual(layout.leading, 334)
        XCTAssertEqual(layout.gap, 1)
        XCTAssertEqual(layout.trailing, 334)
        XCTAssertFalse(layout.followsFold)
    }

    func testTheSplitFollowsTheFoldAndNothingSitsOnIt() {
        // Inner screen in landscape: fold region (with its margins) around x = 475
        let layout = FoldSplitLayout.resolve(width: 951, division: 463...487)
        XCTAssertTrue(layout.followsFold)
        XCTAssertEqual(layout.leading, 463, "leading pane ends where the fold region starts")
        XCTAssertEqual(layout.gap, 24, "the fold region itself is left empty")
        XCTAssertEqual(layout.trailing, 464, "trailing pane starts where the fold region ends")
        XCTAssertEqual(layout.leading + layout.gap + layout.trailing, 951)
    }

    func testAnOffCentreFoldThatLeavesAPaneTooNarrowFallsBackToHalves() {
        // e.g. a sidebar pushed the content so the fold is near the leading edge
        let layout = FoldSplitLayout.resolve(width: 650, division: 170...190)
        XCTAssertFalse(layout.followsFold)
        XCTAssertEqual(layout.leading + layout.gap + layout.trailing, 650)
    }

    func testAZeroWidthFoldStillGetsADivider() {
        let layout = FoldSplitLayout.resolve(width: 669, division: 334.5...334.5)
        XCTAssertTrue(layout.followsFold)
        XCTAssertEqual(layout.gap, FoldSplitLayout.dividerWidth)
        XCTAssertEqual(layout.leading + layout.gap + layout.trailing, 669)
    }

    func testNarrowWidthsNeverGoNegative() {
        let layout = FoldSplitLayout.resolve(width: 0, division: nil)
        XCTAssertGreaterThanOrEqual(layout.leading, 0)
        XCTAssertGreaterThanOrEqual(layout.trailing, 0)
    }

    // MARK: - State survives fold / unfold

    /// Counts how often a tab's state is created.
    final class StateToken: ObservableObject {
        static var created = 0
        init() { Self.created += 1 }
    }

    private struct ProbeTab: View {
        @StateObject private var token = StateToken()
        @Environment(\.horizontalSizeClass) private var sizeClass
        var body: some View {
            // Different layouts per width, like the real screens
            if sizeClass == .regular { Text("two panes") } else { Text("one pane") }
        }
    }

    private struct Host: View {
        @State var selected = 0
        var body: some View {
            DuoAdaptiveTabContainer(
                selectedTab: $selected,
                tabs: [
                    DuoTabItem(id: 0, title: "Home", icon: "house", view: AnyView(ProbeTab())),
                    DuoTabItem(id: 1, title: "Family", icon: "person.2", view: AnyView(Text("family")),
                               placesOwnAccessory: true),
                ],
                tintColor: .blue,
                bottomAccessory: AnyView(Text("SOS"))
            )
        }
    }

    func testFoldingKeepsTheTabsState() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
        let host = UIHostingController(rootView: Host())
        window.rootViewController = host
        host.traitOverrides.horizontalSizeClass = .compact
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        StateToken.created = 0
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let afterFirstLayout = StateToken.created
        XCTAssertEqual(afterFirstLayout, 1)

        // Unfold (regular), fold again (compact)
        for sizeClass in [UIUserInterfaceSizeClass.regular, .compact, .regular] {
            host.traitOverrides.horizontalSizeClass = sizeClass
            window.frame.size.width = sizeClass == .regular ? 669 : 466
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
        XCTAssertEqual(StateToken.created, afterFirstLayout,
                       "changing size class must not rebuild the tab (typed text, selection would be lost)")
    }
}
