import Foundation

// MARK: - Deep Link Router
//
// Handles Universal Links and custom URL schemes.
// Routes: /invite/{code} (also /invite?code= and shoudeng://invite/{code}),
//         /evidence/{token}, /sos/{eventId}

enum DeepLinkDestination: Equatable {
    case invite(code: String)
    case evidence(shareToken: String)
    case sosEvent(eventId: String)
}

struct DeepLinkRouter {

    static func parse(url: URL) -> DeepLinkDestination? {
        var pathComponents = url.pathComponents.filter { $0 != "/" }
        // shoudeng://invite/ABC123 — the first segment is the host
        if url.scheme == "shoudeng", let host = url.host, !host.isEmpty {
            pathComponents.insert(host, at: 0)
        }
        guard let first = pathComponents.first else { return nil }

        // Shared invite links use ?code=ABC123
        if first == "invite", pathComponents.count == 1 {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            guard let code = query?.first(where: { $0.name == "code" })?.value else { return nil }
            return inviteDestination(code)
        }
        guard pathComponents.count >= 2 else { return nil }

        switch first {
        case "invite":
            return inviteDestination(pathComponents[1])
        case "evidence":
            return .evidence(shareToken: pathComponents[1])
        case "sos":
            return .sosEvent(eventId: pathComponents[1])
        default:
            return nil
        }
    }

    /// Invite codes are letters and digits; anything else in a link is noise.
    static func normalizedInviteCode(_ raw: String) -> String? {
        let code = raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return (4...12).contains(code.count) ? code : nil
    }

    private static func inviteDestination(_ raw: String) -> DeepLinkDestination? {
        normalizedInviteCode(raw).map { .invite(code: $0) }
    }

    static func parse(userActivity: NSUserActivity) -> DeepLinkDestination? {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return nil }
        return parse(url: url)
    }
}
