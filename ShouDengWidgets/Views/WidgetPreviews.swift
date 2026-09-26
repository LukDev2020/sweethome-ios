import SwiftUI
import WidgetKit

// MARK: - Xcode Previews for all widget states

#Preview("Protected - Normal (Circular)", as: .accessoryCircular) {
    ProtectedStatusWidget()
} timeline: {
    ProtectedStatusEntry(
        date: Date(), scenario: .normal, guardianCount: 3,
        lastCheckIn: Date().addingTimeInterval(-1800), sosTriggeredAt: nil,
        timerDeadline: nil, timerLabel: nil, updatedAt: Date()
    )
}

#Preview("Protected - Normal (Rectangular)", as: .accessoryRectangular) {
    ProtectedStatusWidget()
} timeline: {
    ProtectedStatusEntry(
        date: Date(), scenario: .normal, guardianCount: 3,
        lastCheckIn: Date().addingTimeInterval(-1800), sosTriggeredAt: nil,
        timerDeadline: nil, timerLabel: nil, updatedAt: Date()
    )
}

#Preview("Protected - Normal (Inline)", as: .accessoryInline) {
    ProtectedStatusWidget()
} timeline: {
    ProtectedStatusEntry(
        date: Date(), scenario: .normal, guardianCount: 3,
        lastCheckIn: Date().addingTimeInterval(-1800), sosTriggeredAt: nil,
        timerDeadline: nil, timerLabel: nil, updatedAt: Date()
    )
}

#Preview("Protected - SOS (Circular)", as: .accessoryCircular) {
    ProtectedStatusWidget()
} timeline: {
    ProtectedStatusEntry(
        date: Date(), scenario: .sosActive, guardianCount: 3,
        lastCheckIn: Date().addingTimeInterval(-1800), sosTriggeredAt: Date().addingTimeInterval(-300),
        timerDeadline: nil, timerLabel: nil, updatedAt: Date()
    )
}

#Preview("Protected - SOS (Rectangular)", as: .accessoryRectangular) {
    ProtectedStatusWidget()
} timeline: {
    ProtectedStatusEntry(
        date: Date(), scenario: .sosActive, guardianCount: 3,
        lastCheckIn: Date().addingTimeInterval(-1800), sosTriggeredAt: Date().addingTimeInterval(-300),
        timerDeadline: nil, timerLabel: nil, updatedAt: Date()
    )
}

#Preview("Protected - Overdue (Rectangular)", as: .accessoryRectangular) {
    ProtectedStatusWidget()
} timeline: {
    ProtectedStatusEntry(
        date: Date(), scenario: .overdue, guardianCount: 3,
        lastCheckIn: Date().addingTimeInterval(-36000), sosTriggeredAt: nil,
        timerDeadline: nil, timerLabel: nil, updatedAt: Date()
    )
}

#Preview("Protected - Normal (Small)", as: .systemSmall) {
    ProtectedStatusWidget()
} timeline: {
    ProtectedStatusEntry(
        date: Date(), scenario: .normal, guardianCount: 3,
        lastCheckIn: Date().addingTimeInterval(-1800), sosTriggeredAt: nil,
        timerDeadline: nil, timerLabel: nil, updatedAt: Date()
    )
}

#Preview("Protected - SOS (Small)", as: .systemSmall) {
    ProtectedStatusWidget()
} timeline: {
    ProtectedStatusEntry(
        date: Date(), scenario: .sosActive, guardianCount: 3,
        lastCheckIn: Date().addingTimeInterval(-1800), sosTriggeredAt: Date().addingTimeInterval(-300),
        timerDeadline: nil, timerLabel: nil, updatedAt: Date()
    )
}

#Preview("Protected - Normal (Medium)", as: .systemMedium) {
    ProtectedStatusWidget()
} timeline: {
    ProtectedStatusEntry(
        date: Date(), scenario: .normal, guardianCount: 3,
        lastCheckIn: Date().addingTimeInterval(-1800), sosTriggeredAt: nil,
        timerDeadline: nil, timerLabel: nil, updatedAt: Date()
    )
}

#Preview("Guardian - All Safe (Circular)", as: .accessoryCircular) {
    GuardianStatusWidget()
} timeline: {
    GuardianStatusEntry(
        date: Date(), scenario: .allSafe,
        persons: [
            WidgetProtectedPerson(id: "1", displayName: "小雨", initial: "雨", status: "normal", lastCheckIn: Date().addingTimeInterval(-1800), batteryLevel: 0.72, homeTimerDeadline: nil),
            WidgetProtectedPerson(id: "2", displayName: "小晴", initial: "晴", status: "normal", lastCheckIn: Date().addingTimeInterval(-3600), batteryLevel: 0.45, homeTimerDeadline: nil),
        ],
        updatedAt: Date()
    )
}

#Preview("Guardian - All Safe (Rectangular)", as: .accessoryRectangular) {
    GuardianStatusWidget()
} timeline: {
    GuardianStatusEntry(
        date: Date(), scenario: .allSafe,
        persons: [
            WidgetProtectedPerson(id: "1", displayName: "小雨", initial: "雨", status: "normal", lastCheckIn: Date().addingTimeInterval(-1800), batteryLevel: 0.72, homeTimerDeadline: nil),
        ],
        updatedAt: Date()
    )
}

#Preview("Guardian - SOS Alert (Rectangular)", as: .accessoryRectangular) {
    GuardianStatusWidget()
} timeline: {
    GuardianStatusEntry(
        date: Date(), scenario: .sosAlert,
        persons: [
            WidgetProtectedPerson(id: "1", displayName: "小雨", initial: "雨", status: "alert", lastCheckIn: Date().addingTimeInterval(-300), batteryLevel: 0.72, homeTimerDeadline: nil),
        ],
        updatedAt: Date()
    )
}

#Preview("Guardian - All Safe (Medium)", as: .systemMedium) {
    GuardianStatusWidget()
} timeline: {
    GuardianStatusEntry(
        date: Date(), scenario: .allSafe,
        persons: [
            WidgetProtectedPerson(id: "1", displayName: "小雨", initial: "雨", status: "normal", lastCheckIn: Date().addingTimeInterval(-1800), batteryLevel: 0.72, homeTimerDeadline: nil),
            WidgetProtectedPerson(id: "2", displayName: "小晴", initial: "晴", status: "overdue", lastCheckIn: Date().addingTimeInterval(-36000), batteryLevel: 0.15, homeTimerDeadline: nil),
            WidgetProtectedPerson(id: "3", displayName: "爸爸", initial: "爸", status: "normal", lastCheckIn: Date().addingTimeInterval(-600), batteryLevel: 0.90, homeTimerDeadline: nil),
        ],
        updatedAt: Date()
    )
}

#Preview("Guardian - SOS Alert (Medium)", as: .systemMedium) {
    GuardianStatusWidget()
} timeline: {
    GuardianStatusEntry(
        date: Date(), scenario: .sosAlert,
        persons: [
            WidgetProtectedPerson(id: "1", displayName: "小雨", initial: "雨", status: "alert", lastCheckIn: Date().addingTimeInterval(-300), batteryLevel: 0.72, homeTimerDeadline: nil),
            WidgetProtectedPerson(id: "2", displayName: "小晴", initial: "晴", status: "normal", lastCheckIn: Date().addingTimeInterval(-3600), batteryLevel: 0.45, homeTimerDeadline: nil),
        ],
        updatedAt: Date()
    )
}

#Preview("Timer - Active (Circular)", as: .accessoryCircular) {
    ProtectedTimerWidget()
} timeline: {
    TimerEntry(date: Date(), isActive: true, deadline: Date().addingTimeInterval(3600), label: "回家倒计时", isLoggedIn: true)
}

#Preview("Timer - Active (Rectangular)", as: .accessoryRectangular) {
    ProtectedTimerWidget()
} timeline: {
    TimerEntry(date: Date(), isActive: true, deadline: Date().addingTimeInterval(3600), label: "回家倒计时", isLoggedIn: true)
}
