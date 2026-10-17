import SwiftUI

// MARK: - Page Indicator
//
// Shared page dots component. Shows filled dots for completed/current
// pages and dimmed dots for upcoming pages.

struct PageIndicator: View {
    let count: Int
    let current: Int
    var activeColor: Color = .white
    var inactiveColor: Color = .white.opacity(0.25)

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i <= current ? activeColor : inactiveColor)
                    .frame(width: 7, height: 7)
            }
        }
    }
}
