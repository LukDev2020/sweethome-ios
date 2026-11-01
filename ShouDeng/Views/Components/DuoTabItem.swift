import SwiftUI

struct DuoTabItem: Identifiable {
    let id: Int
    let title: String
    let icon: String
    let view: AnyView
    /// The tab draws the bottom accessory (SOS) itself, inside its own NavigationStack,
    /// because it has a bottom bar of its own (the family-circle composer). An inset
    /// attached outside the NavigationStack is not passed in, so it covered the composer.
    var placesOwnAccessory: Bool = false
}

private struct TabBottomAccessoryKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

extension EnvironmentValues {
    /// Set for tabs with `placesOwnAccessory`: the SOS button to show above their bottom bar.
    var tabBottomAccessory: AnyView? {
        get { self[TabBottomAccessoryKey.self] }
        set { self[TabBottomAccessoryKey.self] = newValue }
    }
}

// MARK: - Readable segmented tabs

/// A segmented control whose labels follow the in-app text size (`.scaled`); the
/// system segmented Picker uses small fixed text that was hard to read.
struct ReadableSegmentedTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.scaled(size: 15, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? ink : ink.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(selected ? Color(.systemBackground) : .clear)
                                .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }
}
