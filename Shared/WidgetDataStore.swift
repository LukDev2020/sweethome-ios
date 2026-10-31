import Foundation

/// Reads/writes WidgetState to App Group shared UserDefaults.
/// Used by both the main app (write) and widget extension (read).
enum WidgetDataStore {

    static let appGroupId = "group.com.shoudeng.app"
    private static let stateKey = "widget_state"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Explore Mode: no writes to the shared App Group (widgets, Live Activity)
    nonisolated(unsafe) static var writesSuspended = false

    static func write(_ state: WidgetState) {
        guard !writesSuspended, let defaults = sharedDefaults else { return }
        if let data = try? encoder.encode(state) {
            defaults.set(data, forKey: stateKey)
        }
    }

    static func read() -> WidgetState {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: stateKey),
              let state = try? decoder.decode(WidgetState.self, from: data) else {
            return .empty
        }
        return state
    }

    static func clear() {
        guard !writesSuspended else { return }
        sharedDefaults?.removeObject(forKey: stateKey)
    }

    // MARK: - Pending widget actions
    //
    // Widget / Live Activity intents run in the extension, which has no session
    // token. They record the action here and open the app, which sends it to the
    // server (check-in → guardians get "home safe"; arrived → timer dismissed).

    enum PendingAction: String, Codable {
        case checkIn
        case arrived
    }

    private struct PendingEntry: Codable {
        let action: PendingAction
        let at: Date
    }

    private static let pendingKey = "widget_pending_actions"

    static func enqueuePendingAction(_ action: PendingAction, at date: Date = Date()) {
        guard !writesSuspended, let defaults = sharedDefaults else { return }
        var entries = (defaults.data(forKey: pendingKey)).flatMap { try? decoder.decode([PendingEntry].self, from: $0) } ?? []
        entries.append(PendingEntry(action: action, at: date))
        if let data = try? encoder.encode(Array(entries.suffix(10))) {
            defaults.set(data, forKey: pendingKey)
        }
    }

    /// Returns and clears pending actions newer than `maxAge`.
    static func takePendingActions(maxAge: TimeInterval = 600, now: Date = Date()) -> [PendingAction] {
        guard !writesSuspended, let defaults = sharedDefaults else { return [] }
        let entries = (defaults.data(forKey: pendingKey)).flatMap { try? decoder.decode([PendingEntry].self, from: $0) } ?? []
        defaults.removeObject(forKey: pendingKey)
        return entries.filter { now.timeIntervalSince($0.at) <= maxAge && $0.at <= now.addingTimeInterval(5) }.map(\.action)
    }

    // MARK: - Language Sync

    private static let languageKey = "app_language"

    static func writeLanguage(_ lang: String) {
        guard !writesSuspended else { return }
        sharedDefaults?.set(lang, forKey: languageKey)
    }

    /// Returns the app's display name based on language setting.
    /// Chinese → "守灯", English/French/other → "Lantern Care"
    static var appName: String {
        let lang = sharedDefaults?.string(forKey: languageKey) ?? "zh-Hans"
        if lang == "zh-Hant" { return "守燈" }
        return lang.hasPrefix("zh") ? "守灯" : "Lantern Care"
    }

    /// Current language code (for widget/Live Activity localization)
    static var currentLanguage: String {
        sharedDefaults?.string(forKey: languageKey) ?? "zh-Hans"
    }

    /// Localized string lookup for widget extension (no .lproj access).
    /// Traditional Chinese (Hong Kong, Macao, Taiwan) reuses the Chinese copy in
    /// Traditional characters.
    static func localized(_ key: String) -> String {
        let text = baseLocalized(key)
        guard currentLanguage == "zh-Hant" else { return text }
        return text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }

    private static let japanese: [String: String] = [
        "la.normal": "通常", "la.on.duty": "見守り中", "la.guardians": "人が見守り中",
        "la.online": "人がオンライン", "la.sos.button": "SOS", "la.checkin.button": "無事",
        "la.location.button": "位置", "la.home.countdown": "帰宅まで", "la.last.checkin": "前回の無事報告",
        "la.allergy": "アレルギー：", "la.home.timer": "タイマー作動中", "la.sos.active": "SOS 発信中",
        "la.sos.title": "緊急 SOS", "la.sos.body": "Lantern Care の SOS が発信されました",
        "la.persons.count": "人の家族", "la.all.safe": "全員無事", "la.needs.attention": "要確認",
        "la.emergency": "緊急", "la.call": "電話 ", "la.safe": "無事", "la.overdue": "報告なし",
        "la.alert": "緊急 SOS", "la.offline": "オフライン", "la.people.safe": "人が無事",
        "widget.sos.title": "緊急 SOS", "widget.sos.description": "ワンタップで SOS",
        "widget.sos.tap": "タップで SOS", "widget.login.required": "ログインしてください",
    ]

    private static func baseLocalized(_ key: String) -> String {
        let lang = currentLanguage
        if lang.hasPrefix("ja"), let text = japanese[key] { return text }
        let isZh = lang.hasPrefix("zh")
        let isFr = lang.hasPrefix("fr")

        switch key {
        // Live Activity - Protected
        case "la.normal":       return isZh ? "正常" : isFr ? "Normal" : "Normal"
        case "la.on.duty":      return isZh ? "值班中" : isFr ? "En service" : "On Duty"
        case "la.guardians":    return isZh ? "位守护者" : isFr ? " gardiens" : " guardians"
        case "la.online":       return isZh ? "人在线" : isFr ? " en ligne" : " online"
        case "la.sos.button":   return isZh ? "求助" : isFr ? "SOS" : "SOS"
        case "la.checkin.button": return isZh ? "平安" : isFr ? "OK" : "OK"
        case "la.location.button": return isZh ? "位置" : isFr ? "Position" : "Location"
        case "la.home.countdown": return isZh ? "回家倒计时" : isFr ? "Retour maison" : "Home countdown"
        case "la.last.checkin": return isZh ? "上次报平安" : isFr ? "Dernier signal" : "Last check-in"
        case "la.allergy":      return isZh ? "过敏: " : isFr ? "Allergies : " : "Allergies: "
        case "la.home.timer":   return isZh ? "回家计时中" : isFr ? "Minuterie active" : "Timer active"
        case "la.sos.active":   return isZh ? "紧急求助中" : isFr ? "SOS actif" : "SOS Active"
        case "la.sos.title":    return isZh ? "SOS 紧急求助" : isFr ? "SOS d'urgence" : "SOS Emergency"
        case "la.sos.body":     return isZh ? "守灯已触发紧急求助" : isFr ? "Le SOS Lantern Care a été déclenché" : "Lantern Care SOS has been triggered"

        // Live Activity - Guardian
        case "la.persons.count": return isZh ? "位家人" : isFr ? " membres" : " family"
        case "la.all.safe":     return isZh ? "全部安全" : isFr ? "Tous en sécurité" : "All Safe"
        case "la.needs.attention": return isZh ? "需关注" : isFr ? "Attention" : "Needs Attention"
        case "la.emergency":    return isZh ? "紧急" : isFr ? "Urgence" : "Emergency"
        case "la.call":         return isZh ? "呼叫 " : isFr ? "Appeler " : "Call "
        case "la.safe":         return isZh ? "安全" : isFr ? "En sécurité" : "Safe"
        case "la.overdue":      return isZh ? "未报平安" : isFr ? "En retard" : "Overdue"
        case "la.alert":        return isZh ? "紧急求助" : isFr ? "Alerte" : "Alert"
        case "la.offline":      return isZh ? "离线" : isFr ? "Hors ligne" : "Offline"
        case "la.people.safe":  return isZh ? "人安全" : isFr ? " en sécurité" : " safe"

        // Widget — SOS
        case "widget.sos.title":   return isZh ? "紧急求助" : isFr ? "SOS Urgence" : "Emergency SOS"
        case "widget.sos.description": return isZh ? "一键触发紧急求助" : isFr ? "SOS en un tap" : "One-tap SOS"
        case "widget.sos.tap":     return isZh ? "点击求助" : isFr ? "Appuyer" : "Tap for SOS"
        case "widget.login.required": return isZh ? "请先登录" : isFr ? "Connexion requise" : "Login required"

        default: return key
        }
    }
}
