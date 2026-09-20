import Foundation

// MARK: - Deep Link Router
//
// Handles Universal Links and custom URL schemes.
// Routes: /invite/{code}, /evidence/{token}, /sos/{eventId}

enum DeepLinkDestination: Equatable {
    case invite(code: String)
    case evidence(shareToken: String)
    case sosEvent(eventId: String)
}

struct DeepLinkRouter {

    static func parse(url: URL) -> DeepLinkDestination? {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return nil }

        switch pathComponents[0] {
        case "invite":
            return .invite(code: pathComponents[1])
        case "evidence":
            return .evidence(shareToken: pathComponents[1])
        case "sos":
            return .sosEvent(eventId: pathComponents[1])
        default:
            return nil
        }
    }

    static func parse(userActivity: NSUserActivity) -> DeepLinkDestination? {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return nil }
        return parse(url: url)
    }
}
