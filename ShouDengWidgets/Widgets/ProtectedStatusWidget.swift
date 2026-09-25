import WidgetKit
import SwiftUI

struct ProtectedStatusWidget: Widget {
    let kind = "ProtectedStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProtectedTimelineProvider()) { entry in
            ProtectedStatusWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    SharedColors.ink
                }
        }
        .configurationDisplayName("守灯 · 被守护者")
        .description("显示你的守护状态、SOS 和报平安提醒")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .systemSmall,
            .systemMedium,
        ])
    }
}

struct ProtectedStatusWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ProtectedStatusEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            ProtectedInlineView(entry: entry)
        case .accessoryCircular:
            ProtectedCircularView(entry: entry)
        case .accessoryRectangular:
            ProtectedRectangularView(entry: entry)
        case .systemSmall:
            ProtectedSmallView(entry: entry)
        case .systemMedium:
            ProtectedMediumView(entry: entry)
        default:
            ProtectedSmallView(entry: entry)
        }
    }
}
