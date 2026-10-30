import SwiftUI

// MARK: - Coach marks
//
// `.coachMark(id)` marks a REAL control so Explore Mode can spotlight it. It
// reports the control's on-screen frame while a demo is running and is inert
// otherwise.

extension View {
    func coachMark(_ id: String) -> some View {
        modifier(CoachMarkModifier(id: id))
    }
}

private struct CoachMarkModifier: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content.background {
            if ExploreMode.isActive {
                GeometryReader { geo in
                    let frame = geo.frame(in: .global)
                    Color.clear
                        .onAppear { report(frame) }
                        .onChange(of: frame) { _, new in report(new) }
                        .onDisappear { report(nil) }
                }
            }
        }
    }

    private func report(_ frame: CGRect?) {
        let id = self.id
        Task { @MainActor in ExploreModeController.shared.report(anchor: id, frame: frame) }
    }
}
