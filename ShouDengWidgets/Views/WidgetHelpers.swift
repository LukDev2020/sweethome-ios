import SwiftUI

enum WidgetHelpers {

    static func relativeTimeString(from date: Date?) -> String {
        guard let date else { return "未知" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        return "\(Int(interval / 86400))天前"
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
