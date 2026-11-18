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
        /// Lock-screen card "Location": send a fresh location to the family
        case shareLocation
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
    /// Chinese → "守灯", English/French/other → "Beaconify"
    static var appName: String {
        let lang = currentLanguage
        if lang == "zh-Hant" { return "守燈" }
        return lang.hasPrefix("zh") ? "守灯" : "Beaconify"
    }

    /// Current language code (for widget/Live Activity localization): the language
    /// chosen in the app. Before the app has written one (e.g. the widget gallery
    /// right after install) it follows the phone's language.
    static var currentLanguage: String {
        sharedDefaults?.string(forKey: languageKey) ?? deviceLanguage()
    }

    /// The phone's preferred language mapped onto the app's languages — the same
    /// rule the app uses on first launch (LanguageManager.detectLanguage).
    static func deviceLanguage(preferred: String? = Locale.preferredLanguages.first) -> String {
        guard let preferred else { return "en" }
        if preferred.hasPrefix("zh") {
            let traditional = preferred.contains("Hant") || ["zh-TW", "zh-HK", "zh-MO"].contains { preferred.hasPrefix($0) }
            return traditional ? "zh-Hant" : "zh-Hans"
        }
        if preferred.hasPrefix("fr") { return "fr" }
        if preferred.hasPrefix("ja") { return "ja" }
        return "en"
    }

    /// Locale for dates and relative times in the current language.
    static var locale: Locale { Locale(identifier: currentLanguage) }

    /// A table string with `%@` / `%d` placeholders filled in.
    static func localizedFormat(_ key: String, _ args: CVarArg...) -> String {
        String(format: localized(key), arguments: args)
    }

    /// A count in a phrase: "1 guardian" / "3 guardians". Uses `key.one` for one
    /// (French: 0 and 1) when that string exists, else `key`. Format takes `%d`.
    static func localized(_ key: String, count: Int) -> String {
        let lang = currentLanguage
        let singular = lang.hasPrefix("fr") ? count <= 1 : !lang.hasPrefix("zh") && !lang.hasPrefix("ja") && count == 1
        let one = key + ".one"
        let useOne = singular && baseLocalized(one) != one
        return String(format: localized(useOne ? one : key), count)
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
        "la.sos.title": "緊急 SOS", "la.sos.body": "Beaconify の SOS が発信されました",
        "la.persons.count": "人の家族", "la.all.safe": "全員無事", "la.needs.attention": "要確認",
        "la.emergency": "緊急", "la.call": "電話 ", "la.safe": "無事", "la.overdue": "報告なし",
        "la.alert": "緊急 SOS", "la.offline": "オフライン", "la.people.safe": "人が無事",
        "widget.sos.title": "緊急 SOS", "widget.sos.description": "ワンタップで SOS",
        "widget.sos.tap": "タップで SOS", "widget.login.required": "ログインしてください",
        "la.guardians.none": "見守る人はまだいません", "la.latest": "最新の動き",
        "la.location.sent": "家族に位置を送信しました", "la.blood": "血液型 ", "la.meds": "常備薬 ",
        "la.slot.empty": "未登録", "la.open.app": "アプリを開く", "la.persons.none": "家族はまだいません",
        "la.rider.onShift": "勤務中", "la.rider.offShift": "勤務外", "la.rider.crewNearby": " 人のクルーが近く",
        "la.rider.noCrew": "クルーはまだいません", "la.rider.checkAt": "終了 ", "la.rider.report": "報告", "la.rider.crash": "事故",
        "la.rider.helping": "手当て中？傷口を強く押さえて · 電話 ", "la.rider.onTheWay": "さんが向かっています",
        "la.rider.crewAlerted": "クルーに通知済み", "la.rider.call": "電話 ", "la.rider.safe": "無事です",
        // Home / lock-screen widgets
        "widget.config.protected": "見守られる人", "widget.config.protected.desc": "見守り状況・SOS・無事報告のリマインダー",
        "widget.config.guardian": "見守る人", "widget.config.guardian.desc": "家族の安全状況とアラート",
        "widget.config.timer.desc": "帰宅までのカウントダウン",
        "widget.signIn.app": "%@にログイン", "widget.signIn.toSeeStatus": "ログインして状況を確認",
        "widget.tapToOpen": "タップして開く", "widget.tapToSignIn": "タップしてログイン",
        "widget.protected.active": "%@ 見守り中", "widget.checkin.due": "無事を報告して",
        "widget.last.short": "前回：%@", "widget.last.checkin": "前回の無事報告：%@", "widget.updated": "更新 %@",
        "widget.guardians.setup": "見守る人を追加", "widget.guardians.label": "見守る人",
        "widget.guardians.count": "%d人が見守り中", "widget.guardians.protecting": "%d人があなたを見守っています",
        "widget.network.setup": "見守りの輪をつくる", "widget.invite.guardians": "家族を見守る人に招待",
        "widget.invite.family": "家族を招待", "widget.invite.join": "家族を招待しましょう",
        "widget.sos.elapsed": "経過 %@", "widget.sos.triggeredAgo": "発信：%@", "widget.sos.triggered": "SOS を発信しました",
        "widget.sos.alert": "SOS 警報", "widget.person.sos": "%@ SOS", "widget.person.sentSOS": "%@ が助けを求めています",
        "widget.person.overdue": "%@ 報告なし", "widget.someone.overdue": "報告がない人がいます",
        "widget.person.offline": "%@ オフライン", "widget.device.offline": "端末がオフライン",
        "widget.people.safe": "%d人が無事", "widget.more": "+%d人", "widget.status.header": "見守り状況",
        "widget.timer.title": "帰宅タイマー", "widget.timer.home": "帰宅まで %@", "widget.timer.remaining": "残り %@",
        "widget.timer.running": "計測中", "widget.timer.inProgress": "帰宅タイマー作動中", "widget.timer.none": "タイマーなし",
        "widget.timer.notSet": "タイマー未設定", "widget.timer.overdue": "時間超過", "widget.timer.expired": "帰宅時間超過",
        "widget.time.justNow": "たった今", "widget.time.unknown": "不明",
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
        case "la.sos.body":     return isZh ? "守灯已触发紧急求助" : isFr ? "Le SOS Beaconify a été déclenché" : "Beaconify SOS has been triggered"

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

        // Live Activity — fixed-size cards (empty fields show "—")
        case "la.guardians.none": return isZh ? "还没有守护者" : isFr ? "Aucun gardien" : "No guardians yet"
        case "la.latest":       return isZh ? "最新动态" : isFr ? "Dernière nouvelle" : "Latest"
        case "la.location.sent": return isZh ? "已向家人发送位置" : isFr ? "Position envoyée à la famille" : "Location sent to family"
        case "la.blood":        return isZh ? "血型 " : isFr ? "Groupe " : "Blood "
        case "la.meds":         return isZh ? "急救药 " : isFr ? "Médicament " : "Meds "
        case "la.slot.empty":   return isZh ? "未添加" : isFr ? "Non ajouté" : "Not added"
        case "la.open.app":     return isZh ? "打开 App" : isFr ? "Ouvrir l'app" : "Open app"
        case "la.persons.none": return isZh ? "还没有家人" : isFr ? "Aucun proche" : "No family yet"

        // Live Activity — rider mode
        case "la.rider.onShift":  return isZh ? "上班中" : isFr ? "En service" : "On shift"
        case "la.rider.offShift": return isZh ? "未上班" : isFr ? "Hors service" : "Off shift"
        case "la.rider.crewNearby": return isZh ? " 名车队成员在附近" : isFr ? " équipiers à proximité" : " crew nearby"
        case "la.rider.noCrew":   return isZh ? "还没有车队" : isFr ? "Pas encore d'équipe" : "No crew yet"
        case "la.rider.checkAt":  return isZh ? "下班 " : isFr ? "Fin " : "Ends "
        case "la.rider.report":   return isZh ? "报告" : isFr ? "Signaler" : "Report"
        case "la.rider.crash":    return isZh ? "车祸" : isFr ? "Accident" : "Crash"
        case "la.rider.helping":  return isZh ? "在帮忙？用力按住伤口 · 拨打 " : isFr ? "Vous aidez ? Appuyez fort sur la plaie · appelez le " : "Helping? Press hard on the wound · call "
        case "la.rider.onTheWay": return isZh ? " 正在赶来" : isFr ? " arrive" : " on the way"
        case "la.rider.crewAlerted": return isZh ? "已通知车队" : isFr ? "Équipe prévenue" : "Crew alerted"
        case "la.rider.call":     return isZh ? "拨打 " : isFr ? "Appeler " : "Call "
        case "la.rider.safe":     return isZh ? "我安全" : isFr ? "Je vais bien" : "I'm safe"

        // Widget — SOS
        case "widget.sos.title":   return isZh ? "紧急求助" : isFr ? "SOS Urgence" : "Emergency SOS"
        case "widget.sos.description": return isZh ? "一键触发紧急求助" : isFr ? "SOS en un tap" : "One-tap SOS"
        case "widget.sos.tap":     return isZh ? "点击求助" : isFr ? "Appuyer" : "Tap for SOS"
        case "widget.login.required": return isZh ? "请先登录" : isFr ? "Connexion requise" : "Login required"

        // Widget — protected, guardian and home-timer widgets (and their gallery names)
        case "widget.config.protected": return isZh ? "被守护者" : isFr ? "Personne protégée" : "Protected"
        case "widget.config.protected.desc": return isZh ? "显示你的守护状态、SOS 和报平安提醒" : isFr ? "Votre statut, le SOS et les rappels de nouvelles" : "Your status, SOS and check-in reminders"
        case "widget.config.guardian": return isZh ? "守护者" : isFr ? "Gardien" : "Guardian"
        case "widget.config.guardian.desc": return isZh ? "显示被守护者的安全状态和警报" : isFr ? "La sécurité de vos proches et leurs alertes" : "Your family's safety status and alerts"
        case "widget.config.timer.desc": return isZh ? "显示回家倒计时" : isFr ? "Le compte à rebours de votre retour" : "Your home countdown"
        case "widget.signIn.app":  return isZh ? "登录%@" : isFr ? "Connexion à %@" : "Sign in to %@"
        case "widget.signIn.toSeeStatus": return isZh ? "请登录查看守护状态" : isFr ? "Connectez-vous pour voir le statut" : "Sign in to see status"
        case "widget.tapToOpen":   return isZh ? "点击打开" : isFr ? "Touchez pour ouvrir" : "Tap to open"
        case "widget.tapToSignIn": return isZh ? "点击登录查看守护状态" : isFr ? "Touchez pour vous connecter" : "Tap to sign in"
        case "widget.protected.active": return isZh ? "%@守护中" : isFr ? "%@ actif" : "%@ is on"
        case "widget.checkin.due": return isZh ? "请报平安" : isFr ? "Donnez des nouvelles" : "Please check in"
        case "widget.last.short":  return isZh ? "上次：%@" : isFr ? "Dernier : %@" : "Last: %@"
        case "widget.last.checkin": return isZh ? "上次报平安：%@" : isFr ? "Dernier signal : %@" : "Last check-in: %@"
        case "widget.updated":     return isZh ? "更新于 %@" : isFr ? "Mis à jour %@" : "Updated %@"
        case "widget.guardians.setup": return isZh ? "设置守护者" : isFr ? "Ajouter des gardiens" : "Add guardians"
        case "widget.guardians.label": return isZh ? "守护者" : isFr ? "Gardiens" : "Guardians"
        case "widget.guardians.count": return isZh ? "%d位守护者" : isFr ? "%d gardiens" : "%d guardians"
        case "widget.guardians.count.one": return isZh ? "%d位守护者" : isFr ? "%d gardien" : "%d guardian"
        case "widget.guardians.protecting": return isZh ? "%d位守护者正在保护你" : isFr ? "%d gardiens veillent sur vous" : "%d guardians watching over you"
        case "widget.guardians.protecting.one": return isZh ? "%d位守护者正在保护你" : isFr ? "%d gardien veille sur vous" : "%d guardian watching over you"
        case "widget.network.setup": return isZh ? "设置守护网络" : isFr ? "Créez votre cercle" : "Set up your circle"
        case "widget.invite.guardians": return isZh ? "邀请家人成为你的守护者" : isFr ? "Invitez vos proches à veiller sur vous" : "Invite family to be your guardians"
        case "widget.invite.family": return isZh ? "邀请家人" : isFr ? "Inviter un proche" : "Invite family"
        case "widget.invite.join": return isZh ? "邀请家人加入守护" : isFr ? "Invitez vos proches" : "Invite your family"
        case "widget.sos.elapsed": return isZh ? "已进行 %@" : isFr ? "Depuis %@" : "For %@"
        case "widget.sos.triggeredAgo": return isZh ? "%@触发" : isFr ? "Déclenché %@" : "Sent %@"
        case "widget.sos.triggered": return isZh ? "已触发紧急求助" : isFr ? "SOS envoyé" : "SOS sent"
        case "widget.sos.alert":   return isZh ? "SOS 警报" : isFr ? "Alerte SOS" : "SOS alert"
        case "widget.person.sos":  return isZh ? "%@ SOS" : isFr ? "%@ SOS" : "%@ SOS"
        case "widget.person.sentSOS": return isZh ? "%@ 发出求助" : isFr ? "%@ a besoin d'aide" : "%@ needs help"
        case "widget.person.overdue": return isZh ? "%@ 未报平安" : isFr ? "%@ sans nouvelles" : "%@ hasn't checked in"
        case "widget.someone.overdue": return isZh ? "有人未报平安" : isFr ? "Un proche sans nouvelles" : "Someone hasn't checked in"
        case "widget.person.offline": return isZh ? "%@ 设备离线" : isFr ? "%@ hors ligne" : "%@ offline"
        case "widget.device.offline": return isZh ? "设备离线" : isFr ? "Appareil hors ligne" : "Device offline"
        case "widget.people.safe": return isZh ? "%d人安全" : isFr ? "%d en sécurité" : "%d safe"
        case "widget.more":        return isZh ? "+%d人" : isFr ? "+%d autres" : "+%d more"
        case "widget.more.one":    return isZh ? "+%d人" : isFr ? "+%d autre" : "+%d more"
        case "widget.status.header": return isZh ? "守护状态" : isFr ? "État de la famille" : "Family status"
        case "widget.timer.title": return isZh ? "回家计时" : isFr ? "Retour maison" : "Home timer"
        case "widget.timer.home":  return isZh ? "回家 %@" : isFr ? "Retour dans %@" : "Home in %@"
        case "widget.timer.remaining": return isZh ? "剩余 %@" : isFr ? "Reste %@" : "%@ left"
        case "widget.timer.running": return isZh ? "计时中" : isFr ? "En cours" : "Running"
        case "widget.timer.inProgress": return isZh ? "回家倒计时进行中" : isFr ? "Compte à rebours en cours" : "Home countdown running"
        case "widget.timer.none":  return isZh ? "无计时" : isFr ? "Pas de minuterie" : "No timer"
        case "widget.timer.notSet": return isZh ? "未设置计时器" : isFr ? "Aucune minuterie" : "No timer set"
        case "widget.timer.overdue": return isZh ? "已超时" : isFr ? "Dépassé" : "Overdue"
        case "widget.timer.expired": return isZh ? "回家超时" : isFr ? "Retour en retard" : "Late home"
        case "widget.time.justNow": return isZh ? "刚刚" : isFr ? "à l'instant" : "just now"
        case "widget.time.unknown": return isZh ? "未知" : isFr ? "inconnu" : "unknown"

        default: return key
        }
    }
}
