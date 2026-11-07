import Foundation

// MARK: - Deep Link Router
//
// Handles Universal Links and custom URL schemes.
// Routes: /invite/{code} (also /invite?code= and shoudeng://invite/{code}),
//         /evidence/{token}, /sos/{eventId},
//         /crew/{code} (also shoudeng://crew/join?code=) — a rider crew invite,
//         /start?for=rider&org={partner} — sign up as a rider (partner link)

enum DeepLinkDestination: Equatable {
    case invite(code: String)
    case evidence(shareToken: String)
    case sosEvent(eventId: String)
    case crew(code: String)
    case riderStart(partnerCode: String?)
}

struct DeepLinkRouter {

    static func parse(url: URL) -> DeepLinkDestination? {
        var pathComponents = url.pathComponents.filter { $0 != "/" }
        // shoudeng://invite/ABC123 — the first segment is the host
        if url.scheme == "shoudeng", let host = url.host, !host.isEmpty {
            pathComponents.insert(host, at: 0)
        }
        guard let first = pathComponents.first else { return nil }

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // Rider links: /start?for=rider&org=XXXXXX
        if first == "start" {
            guard query.first(where: { $0.name == "for" })?.value?.lowercased() == "rider" else { return nil }
            return .riderStart(partnerCode: query.first(where: { $0.name == "org" })?.value.flatMap(normalizedPartnerCode))
        }
        // Crew invites: /crew/ABC123, /crew/join?code=ABC123
        if first == "crew" {
            let raw = pathComponents.count >= 2 && pathComponents[1] != "join"
                ? pathComponents[1] : query.first(where: { $0.name == "code" })?.value ?? ""
            return normalizedCrewCode(raw).map { .crew(code: $0) }
        }

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

    /// Crew codes are 6 letters / digits (server: crew.ts)
    static func normalizedCrewCode(_ raw: String) -> String? {
        let code = raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return code.count == 6 ? code : nil
    }

    /// Partner codes: 6 characters without 0/O/1/I/L (server: partners.ts)
    static func normalizedPartnerCode(_ raw: String) -> String? {
        let code = raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let allowed = Set("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return code.count == 6 && code.allSatisfy(allowed.contains) ? code : nil
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
