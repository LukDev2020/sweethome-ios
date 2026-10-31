import SwiftUI

// MARK: - Fold-aware two-pane split
//
// Two panes side by side for the regular-width layouts (iPhone Duo inner screen, iPad).
// On iOS 27.1+ the split follows the fold (`GeometryProxy.reservedRegions(kind: .division)`):
// the leading pane ends where the fold region starts and the trailing pane begins where it
// ends, so nothing — above all no SOS control — sits on the fold. Without a fold (iPad, or a
// fold that would leave a pane too narrow) the panes are 50/50.
//
// DEBUG: launch with `-DuoSimulatedFold <points>` to fake a vertical fold of that width in the
// middle of every split (tinted red) when checking layouts on an iPad simulator.

struct FoldSplitLayout: Equatable {
    var leading: CGFloat
    var gap: CGFloat
    var trailing: CGFloat
    /// The split is at the fold (rather than 50/50).
    var followsFold = false

    static let dividerWidth: CGFloat = 1
    static let defaultMinPaneWidth: CGFloat = 240

    /// - Parameters:
    ///   - width: the container width.
    ///   - division: horizontal extent of a vertical fold region, in the container's coordinates
    ///     (the region's frame already includes the margins interactive content must keep).
    static func resolve(width: CGFloat,
                        division: ClosedRange<CGFloat>?,
                        minPaneWidth: CGFloat = defaultMinPaneWidth) -> FoldSplitLayout {
        let width = max(0, width)
        if let division {
            let start = max(0, division.lowerBound)
            let end = min(width, max(start + dividerWidth, division.upperBound))
            if start >= minPaneWidth, width - end >= minPaneWidth {
                return FoldSplitLayout(leading: start, gap: end - start, trailing: width - end, followsFold: true)
            }
        }
        let leading = max(0, ((width - dividerWidth) / 2).rounded(.down))
        return FoldSplitLayout(leading: leading, gap: dividerWidth,
                               trailing: max(0, width - leading - dividerWidth))
    }

    /// The fold to split at, if this container has one.
    static func division(in proxy: GeometryProxy) -> ClosedRange<CGFloat>? {
        #if DEBUG
        let simulated = UserDefaults.standard.double(forKey: "DuoSimulatedFold")
        if simulated > 0 {
            let mid = proxy.size.width / 2
            return (mid - simulated / 2)...(mid + simulated / 2)
        }
        #endif
        if #available(iOS 27.1, *) {
            // A vertical fold divides left from right; a horizontal one (tabletop) is not a
            // side-by-side split.
            let fold = proxy.reservedRegions(kind: .division)
                .first { $0.isActive && $0.frame.height > $0.frame.width }
            if let fold { return fold.frame.minX...fold.frame.maxX }
        }
        return nil
    }

    static var isSimulatingFold: Bool {
        #if DEBUG
        return UserDefaults.standard.double(forKey: "DuoSimulatedFold") > 0
        #else
        return false
        #endif
    }
}

struct FoldSplitView<Leading: View, Trailing: View>: View {
    var minPaneWidth: CGFloat = FoldSplitLayout.defaultMinPaneWidth
    var dividerColor: Color = Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.13)
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        GeometryReader { proxy in
            let layout = FoldSplitLayout.resolve(
                width: proxy.size.width,
                division: FoldSplitLayout.division(in: proxy),
                minPaneWidth: minPaneWidth
            )
            HStack(spacing: 0) {
                leading()
                    .frame(width: layout.leading)
                    .frame(maxHeight: .infinity)
                ZStack {
                    if FoldSplitLayout.isSimulatingFold && layout.followsFold {
                        Color.red.opacity(0.15)
                    }
                    Rectangle().fill(dividerColor).frame(width: FoldSplitLayout.dividerWidth)
                }
                .frame(width: layout.gap)
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                trailing()
                    .frame(width: layout.trailing)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Fold-avoiding column
//
// For full-screen content that is one column (SOS countdown, fall check): on a folded-open
// screen it goes in the trailing pane, clear of the fold; otherwise it is centred with a
// readable maximum width.

struct FoldAvoidingColumn<Content: View>: View {
    var maxWidth: CGFloat = 480
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let layout = FoldSplitLayout.resolve(width: proxy.size.width,
                                                 division: FoldSplitLayout.division(in: proxy))
            let folded = layout.followsFold
            // One structure for both cases, so folding never rebuilds the content.
            HStack(spacing: 0) {
                Color.clear.frame(width: folded ? layout.leading + layout.gap : 0)
                content()
                    .frame(width: folded ? layout.trailing : min(maxWidth, proxy.size.width))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
