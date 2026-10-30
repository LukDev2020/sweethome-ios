import Foundation

// MARK: - Guided tour (5 steps per phone)
//
// Each step points a coach mark at a REAL control (the user learns the actual
// buttons) and either moves on (Next), waits for the user to use the control
// (Try it), or opens the screen it talks about.

struct DemoTourStep: Identifiable, Equatable {
    enum Action: Equatable {
        case next
        case tryIt(labelKey: String)
        case openAlert
        case openSheet(DemoSheet)
    }

    enum Completion: Equatable {
        case homeSafe, sosTriggered, acknowledged
    }

    let id: String
    let anchor: String?
    let titleKey: String
    let bodyKey: String
    let action: Action
    let completion: Completion?
    let teaches: DemoLesson?

    var primaryLabelKey: String {
        switch action {
        case .next: return "explore.tip.next"
        case .tryIt(let key): return key
        case .openAlert: return "explore.tip.openAlert"
        case .openSheet(.dutySchedule): return "explore.tip.showSchedule"
        case .openSheet(.claimMaterials): return "explore.tip.showRecords"
        }
    }
}

/// Coach-mark anchor ids attached to real views with `.coachMark(_:)`.
enum CoachAnchor {
    static let homeSafe = "protected.homeSafe"
    static let guardiansGlobe = "protected.globe"
    static let sosButton = "protected.sos"
    static let tracking = "protected.tracking"
    static let firstPerson = "guardian.firstPerson"
    static let alertPerson = "guardian.alertPerson"
    static let acknowledge = "guardian.ack"
    static let clocks = "guardian.clocks"
    static let claims = "guardian.claims"
}

enum DemoTour {
    static func steps(for role: DemoRole) -> [DemoTourStep] {
        switch role {
        case .mom:
            return [
                .init(id: "mom.homeSafe", anchor: CoachAnchor.homeSafe,
                      titleKey: "explore.tip.mom.homeSafe.title", bodyKey: "explore.tip.mom.homeSafe.body",
                      action: .tryIt(labelKey: "explore.tip.tryIt"), completion: .homeSafe, teaches: .homeSafe),
                .init(id: "mom.guardians", anchor: CoachAnchor.guardiansGlobe,
                      titleKey: "explore.tip.mom.guardians.title", bodyKey: "explore.tip.mom.guardians.body",
                      action: .next, completion: nil, teaches: nil),
                .init(id: "mom.sos", anchor: CoachAnchor.sosButton,
                      titleKey: "explore.tip.mom.sos.title", bodyKey: "explore.tip.mom.sos.body",
                      action: .tryIt(labelKey: "explore.tip.holdButton"), completion: .sosTriggered, teaches: .practiceSOS),
                .init(id: "mom.tracking", anchor: CoachAnchor.tracking,
                      titleKey: "explore.tip.mom.tracking.title", bodyKey: "explore.tip.mom.tracking.body",
                      action: .next, completion: nil, teaches: nil),
                .init(id: "mom.done", anchor: nil,
                      titleKey: "explore.tip.mom.done.title", bodyKey: "explore.tip.mom.done.body",
                      action: .next, completion: nil, teaches: nil),
            ]
        case .sarah:
            return [
                .init(id: "sarah.dashboard", anchor: CoachAnchor.firstPerson,
                      titleKey: "explore.tip.sarah.dashboard.title", bodyKey: "explore.tip.sarah.dashboard.body",
                      action: .next, completion: nil, teaches: .dashboard),
                .init(id: "sarah.respond", anchor: CoachAnchor.alertPerson,
                      titleKey: "explore.tip.sarah.respond.title", bodyKey: "explore.tip.sarah.respond.body",
                      action: .openAlert, completion: nil, teaches: nil),
                .init(id: "sarah.ack", anchor: CoachAnchor.acknowledge,
                      titleKey: "explore.tip.sarah.ack.title", bodyKey: "explore.tip.sarah.ack.body",
                      action: .tryIt(labelKey: "explore.tip.tryIt"), completion: .acknowledged, teaches: .respond),
                .init(id: "sarah.coverage", anchor: CoachAnchor.clocks,
                      titleKey: "explore.tip.sarah.coverage.title", bodyKey: "explore.tip.sarah.coverage.body",
                      action: .openSheet(.dutySchedule), completion: nil, teaches: .coverage),
                .init(id: "sarah.records", anchor: CoachAnchor.claims,
                      titleKey: "explore.tip.sarah.records.title", bodyKey: "explore.tip.sarah.records.body",
                      action: .openSheet(.claimMaterials), completion: nil, teaches: .records),
            ]
        }
    }
}
