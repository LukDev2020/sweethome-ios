import SwiftUI

enum WidgetHelpers {

    /// "just now", "5 min. ago", "il y a 3 h", "3小时前"… in the app's language.
    static func relativeTimeString(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return WidgetDataStore.localized("widget.time.unknown") }
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return WidgetDataStore.localized("widget.time.justNow") }
        var ago = DateComponents()
        if interval < 3600 { ago.minute = -Int(interval / 60) }
        else if interval < 86400 { ago.hour = -Int(interval / 3600) }
        else { ago.day = -Int(interval / 86400) }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = WidgetDataStore.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(from: ago)
    }

    /// A table string with one `%@`, filled with a live `Text` (timer, relative date).
    static func text(_ key: String, _ inner: Text) -> Text {
        let parts = WidgetDataStore.localized(key).components(separatedBy: "%@")
        let before = parts.first ?? ""
        let after = parts.dropFirst().joined()
        return Text("\(Text(verbatim: before))\(inner)\(Text(verbatim: after))")
    }

    /// "守灯 · …" / "Beaconify · …" for one-line lock-screen widgets.
    static func branded(_ text: String) -> String {
        "\(WidgetDataStore.appName) · \(text)"
    }

    static func isStale(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) > 1800
    }

    static func isVeryStale(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) > 7200
    }

    static func statusColor(for status: String) -> Color {
        switch status {
        case "normal": return SharedColors.safe
        case "overdue": return SharedColors.warning
        case "alert": return SharedColors.alert
        case "unreachable": return SharedColors.offline
        default: return SharedColors.safe
        }
    }

    static func prioritySorted(_ persons: [WidgetProtectedPerson]) -> [WidgetProtectedPerson] {
        persons.sorted { a, b in
            statusPriority(a.status) > statusPriority(b.status)
        }
    }

    private static func statusPriority(_ status: String) -> Int {
        switch status {
        case "alert": return 3
        case "overdue": return 2
        case "unreachable": return 1
        default: return 0
        }
    }
}
