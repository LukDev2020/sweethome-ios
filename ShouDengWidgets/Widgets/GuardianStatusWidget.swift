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
        .configurationDisplayName(WidgetHelpers.branded(WidgetDataStore.localized("widget.config.guardian")))
        .description(WidgetDataStore.localized("widget.config.guardian.desc"))
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
        content.environment(\.locale, WidgetDataStore.locale)
    }

    @ViewBuilder
    private var content: some View {
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
