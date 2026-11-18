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
        .configurationDisplayName(WidgetHelpers.branded(WidgetDataStore.localized("widget.config.protected")))
        .description(WidgetDataStore.localized("widget.config.protected.desc"))
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
        content.environment(\.locale, WidgetDataStore.locale)
    }

    @ViewBuilder
    private var content: some View {
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
