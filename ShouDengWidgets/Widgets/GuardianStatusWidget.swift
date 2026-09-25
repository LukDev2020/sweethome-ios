import WidgetKit
import SwiftUI

struct GuardianStatusWidget: Widget {
    let kind = "GuardianStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GuardianTimelineProvider()) { entry in
            GuardianStatusWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    SharedColors.ink
                }
        }
        .configurationDisplayName("守灯 · 守护者")
        .description("显示被守护者的安全状态和警报")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .systemSmall,
            .systemMedium,
        ])
    }
}

struct GuardianStatusWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: GuardianStatusEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            GuardianInlineView(entry: entry)
        case .accessoryCircular:
            GuardianCircularView(entry: entry)
        case .accessoryRectangular:
            GuardianRectangularView(entry: entry)
        case .systemSmall:
            GuardianSmallView(entry: entry)
        case .systemMedium:
            GuardianMediumView(entry: entry)
        default:
            GuardianSmallView(entry: entry)
        }
    }
}
