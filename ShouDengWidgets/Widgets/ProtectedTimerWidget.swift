import WidgetKit
import SwiftUI

struct ProtectedTimerWidget: Widget {
    let kind = "ProtectedTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimerTimelineProvider()) { entry in
            ProtectedTimerWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    SharedColors.ink
                }
        }
        .configurationDisplayName("守灯 · 回家计时")
        .description("显示回家倒计时")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

struct ProtectedTimerWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TimerEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            TimerInlineView(entry: entry)
        case .accessoryCircular:
            TimerCircularView(entry: entry)
        case .accessoryRectangular:
            TimerRectangularView(entry: entry)
        default:
            TimerCircularView(entry: entry)
        }
    }
}
