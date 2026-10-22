import WidgetKit
import SwiftUI

// MARK: - SOS Widget (SafeTap Pattern)
//
// One-tap SOS from home screen. Displays a large SOS button that
// triggers the SOSIntent to open the app and start the SOS flow.

@available(iOS 17.0, *)
struct SOSWidget: Widget {
    let kind: String = "SOSWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SOSTimelineProvider()) { entry in
            SOSWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetDataStore.localized("widget.sos.title"))
        .description(WidgetDataStore.localized("widget.sos.description"))
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Timeline Provider

struct SOSTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SOSEntry {
        SOSEntry(date: Date(), isLoggedIn: true, userName: "守灯")
    }

    func getSnapshot(in context: Context, completion: @escaping (SOSEntry) -> Void) {
        let state = WidgetDataStore.read()
        completion(SOSEntry(
            date: Date(),
            isLoggedIn: state.isLoggedIn,
            userName: state.userName ?? ""
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SOSEntry>) -> Void) {
        let state = WidgetDataStore.read()
        let entry = SOSEntry(
            date: Date(),
            isLoggedIn: state.isLoggedIn,
            userName: state.userName ?? ""
        )
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Entry

struct SOSEntry: TimelineEntry {
    let date: Date
    let isLoggedIn: Bool
    let userName: String
}

// MARK: - View

@available(iOS 17.0, *)
struct SOSWidgetView: View {
    var entry: SOSEntry

    var body: some View {
        if entry.isLoggedIn {
            Button(intent: SOSIntent()) {
                ZStack {
                    Circle()
                        .fill(Color.red.gradient)
                        .padding(8)

                    VStack(spacing: 4) {
                        Text("SOS")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.white)

                        Text(WidgetDataStore.localized("widget.sos.tap"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .buttonStyle(.plain)
            .containerBackground(.black, for: .widget)
        } else {
            VStack {
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(WidgetDataStore.localized("widget.login.required"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .containerBackground(.background, for: .widget)
        }
    }
}
