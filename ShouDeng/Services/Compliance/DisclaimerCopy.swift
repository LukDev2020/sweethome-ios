import Foundation

// MARK: - Versioned Disclaimer Copy
//
// ALL user-facing legal/disclaimer text lives here.
// Legal reviews one file. Version bump re-triggers disclosure.
// Never scatter disclaimer text across view files.

enum DisclaimerCopy {

    // MARK: - Onboarding (3 screens)

    enum Onboarding {
        /// Bump when the wording changes: everyone sees the screens again (RootView).
        /// v2.0: matches the app — sharing stops immediately (there is no 6-hour delay),
        /// lists everything family can see, warns that detection can miss or misfire.
        static let version = "v2.0"

        struct Screen {
            let id: String
            let icon: String          // SF Symbol name
            let title: String
            let body: String
            let buttonTitle: String
        }

        static let screens: [Screen] = screensZh

        static func screens(for language: AppLanguage) -> [Screen] {
            switch language {
            case .chinese: return screensZh
            case .traditionalChinese:
                let lm = LanguageManager.shared
                return screensZh.map { Screen(id: $0.id, icon: $0.icon, title: lm.zh($0.title),
                                              body: lm.zh($0.body), buttonTitle: lm.zh($0.buttonTitle)) }
            case .english: return screensEn
            case .french: return screensFr
            case .japanese: return screensJa
            }
        }

        // Shown before sign-in, so written for both the person looked after and family.
        private static let screensZh: [Screen] = [
            Screen(
                id: "onboard.not_emergency",
                icon: "exclamationmark.triangle",
                title: "守灯不是紧急服务",
                body: "遇到危险时，请先拨打当地紧急号码。\n\n守灯只负责通知你选定的家人，无法替代警察、消防或急救。通知可能延迟或失败——例如手机关机、没有信号或关闭了通知——我们也无法保证有人及时回应。",
                buttonTitle: "我明白了"
            ),
            Screen(
                id: "onboard.scope",
                icon: "eye",
                title: "家人能看到什么",
                body: "被守护的人与自己选定的家人分享：位置（SOS 期间还有行动路线）、电量、报平安记录，以及在家庭动态里发的内容。\n\n聊天记录、相册、通话记录和其他应用的内容永远看不到——守灯也无法访问这些。",
                buttonTitle: "继续"
            ),
            Screen(
                id: "onboard.control",
                icon: "hand.raised",
                title: "控制权在你手里",
                body: "共享可以随时暂停（最长 4 小时），家人也可以随时移除，立即生效。\n\n跌倒、语音和声音检测都是可选功能，可能漏报或误报，也不是医疗器械。",
                buttonTitle: "开始使用"
            ),
        ]

        private static let screensEn: [Screen] = [
            Screen(
                id: "onboard.not_emergency",
                icon: "exclamationmark.triangle",
                title: "Lantern Care Is Not an Emergency Service",
                body: "In danger, always call your local emergency number first.\n\nLantern Care alerts the family members you choose; it cannot replace police, fire or ambulance. Alerts can be late or fail — for example if a phone is off, has no signal or has notifications turned off — and we can't guarantee that anyone responds.",
                buttonTitle: "I Understand"
            ),
            Screen(
                id: "onboard.scope",
                icon: "eye",
                title: "What Family Members Can See",
                body: "The person being looked after shares with the family members they choose: their location (and their path during an SOS), battery, check-ins, and what they post in the family circle.\n\nNever their messages, photo library, calls or other apps — Lantern Care can't access those.",
                buttonTitle: "Continue"
            ),
            Screen(
                id: "onboard.control",
                icon: "hand.raised",
                title: "You Are in Control",
                body: "Sharing can be paused for up to 4 hours, and a family member can be removed at any time — it takes effect right away.\n\nFall, voice and sound detection are optional. They can miss an event or go off by mistake, and they are not medical devices.",
                buttonTitle: "Get Started"
            ),
        ]

        private static let screensJa: [Screen] = [
            Screen(
                id: "onboard.not_emergency",
                icon: "exclamationmark.triangle",
                title: "Lantern Care は緊急通報サービスではありません",
                body: "危険なときは、まず現地の緊急番号（日本では救急・消防 119、警察 110）に電話してください。\n\nLantern Care はあなたが選んだ家族に知らせるアプリで、警察・消防・救急の代わりにはなりません。電源が切れている、圏外、通知がオフなどの理由で通知が遅れたり届かなかったりすることがあり、誰かが必ず応答するとは保証できません。",
                buttonTitle: "わかりました"
            ),
            Screen(
                id: "onboard.scope",
                icon: "eye",
                title: "家族に見えるもの",
                body: "見守られる人は、自分で選んだ家族と次の情報を共有します：位置（SOS 中は移動ルートも）、バッテリー残量、安否報告、家族の共有スペースへの投稿。\n\nメッセージ、写真ライブラリ、通話履歴、その他のアプリの内容は見えません。Lantern Care もそれらにはアクセスできません。",
                buttonTitle: "次へ"
            ),
            Screen(
                id: "onboard.control",
                icon: "hand.raised",
                title: "決めるのはあなたです",
                body: "共有はいつでも一時停止（最長 4 時間）でき、家族はいつでも外せます。どちらもすぐに反映されます。\n\n転倒・音声・音の検知は任意の機能です。見逃しや誤作動があり、医療機器ではありません。",
                buttonTitle: "はじめる"
            ),
        ]

        private static let screensFr: [Screen] = [
            Screen(
                id: "onboard.not_emergency",
                icon: "exclamationmark.triangle",
                title: "Lantern Care n'est pas un service d'urgence",
                body: "En cas de danger, appelez toujours d'abord le numéro d'urgence local.\n\nLantern Care prévient les proches que vous choisissez ; il ne remplace ni la police, ni les pompiers, ni les secours. Une alerte peut arriver en retard ou échouer — téléphone éteint, sans réseau ou notifications désactivées, par exemple — et nous ne pouvons pas garantir que quelqu'un réponde.",
                buttonTitle: "Je comprends"
            ),
            Screen(
                id: "onboard.scope",
                icon: "eye",
                title: "Ce que voient les proches",
                body: "La personne protégée partage avec les proches qu'elle choisit : sa position (et son trajet pendant un SOS), sa batterie, ses signes de vie et ce qu'elle publie dans le cercle familial.\n\nJamais ses messages, sa photothèque, ses appels ni ses autres applications — Lantern Care n'y a pas accès.",
                buttonTitle: "Continuer"
            ),
            Screen(
                id: "onboard.control",
                icon: "hand.raised",
                title: "Vous gardez le contrôle",
                body: "Le partage peut être mis en pause (jusqu'à 4 heures) et un proche retiré à tout moment, avec effet immédiat.\n\nLa détection de chute, de voix et de sons est facultative. Elle peut manquer un événement ou se déclencher par erreur, et ce n'est pas un dispositif médical.",
                buttonTitle: "Commencer"
            ),
        ]
    }

    // MARK: - Guardian responsibilities (after sign-in, guardian role)

    /// One screen a guardian confirms once per version (texts in Localizable "duty.*").
    enum GuardianDuty {
        static let version = "v1.0"
        static let consentKey = "guardian.duty"
    }

    // MARK: - Terms of Service / Privacy Policy acceptance (login screen)

    enum Terms {
        /// The date of the Terms of Service text in LegalView; bump to ask again.
        static let version = "2026-11-06"
        static let consentKey = "terms.accept"
    }

    // MARK: - Escalation channels

    /// SMS and voice calls go through Twilio, which is switched off for now: an SOS
    /// reaches guardians by push only. While false the app must not describe text or
    /// call steps as happening. Turn on together with the Twilio secrets.
    enum EscalationChannels {
        static let phoneEnabled = false
    }

    // MARK: - Feature Disclosures (per-feature, first use)

    enum FeatureDisclosure: String, CaseIterable, Identifiable {
        case sos
        case location
        case trajectory
        case fallDetection
        case emergencyAudio
        case autoVoiceCall

        var id: String { rawValue }
        var version: String { "v1.1" }

        var storageKey: String {
            "disclosure_\(rawValue)_\(version)"
        }

        var icon: String {
            switch self {
            case .sos:            return "sos"
            case .location:       return "location.slash"
            case .trajectory:     return "point.topleft.down.to.point.bottomright.curvepath"
            case .fallDetection:  return "figure.fall"
            case .emergencyAudio: return "mic.badge.xmark"
            case .autoVoiceCall:  return "phone.arrow.up.right"
            }
        }

        /// Localized (en / zh-Hans / fr) — these sheets used to be Chinese-only.
        var title: String {
            LanguageManager.shared.localized("disclosure.\(rawValue).title")
        }

        var body: String { body(emergencyNumber: "112") }

        /// The SOS text names the local emergency number (911, 112, 110…).
        func body(emergencyNumber: String) -> String {
            let text = LanguageManager.shared.localized("disclosure.\(rawValue).body")
            return self == .sos ? String(format: text, emergencyNumber) : text
        }

        /// Whether this disclosure uses "开启 | 暂不开启" buttons instead of single acknowledge
        var requiresOptIn: Bool {
            switch self {
            case .location, .trajectory, .fallDetection, .emergencyAudio:
                return true
            case .sos, .autoVoiceCall:
                return false
            }
        }

        /// Whether this is high-sensitivity and must be separately consented
        var isHighSensitivity: Bool {
            self == .trajectory
        }

        /// Consent log key for this disclosure
        var consentKey: String {
            switch self {
            case .sos:            return "consent.sos"
            case .location:       return "consent.location"
            case .trajectory:     return "consent.trajectory"
            case .fallDetection:  return "consent.fall_detect"
            case .emergencyAudio: return "consent.audio"
            case .autoVoiceCall:  return "consent.voice_call"
            }
        }
    }

    // MARK: - Degradation Messages

    enum Degradation {

        struct Warning: Identifiable {
            let id: String
            let severity: Severity
            let protectedMessage: String
            let guardianMessage: String
            let detailText: String
            let protectedActions: [Action]
            let guardianActions: [Action]

            enum Severity {
                case caution   // lamp color
                case critical  // alert color
            }

            struct Action {
                let title: String
                let type: ActionType
            }

            enum ActionType {
                case openSettings
                case dismiss
                case call
                case message
            }

            init(
                id: String,
                severity: Severity,
                protectedMessage: String,
                guardianMessage: String,
                detailText: String,
                protectedActions: [Action] = [],
                guardianActions: [Action] = []
            ) {
                self.id = id
                self.severity = severity
                self.protectedMessage = protectedMessage
                self.guardianMessage = guardianMessage
                self.detailText = detailText
                self.protectedActions = protectedActions
                self.guardianActions = guardianActions
            }
        }

        static func locationRevoked(personName: String) -> Warning {
            Warning(
                id: "location_revoked",
                severity: .critical,
                protectedMessage: "你的家人现在看不到你",
                guardianMessage: "\(personName)的位置共享已中断",
                detailText: "定位权限已被系统改为「使用期间」。你不在应用内时，家人将看不到你的位置。",
                protectedActions: [
                    .init(title: "去设置修复", type: .openSettings),
                    .init(title: "稍后", type: .dismiss),
                ],
                guardianActions: [
                    .init(title: "拨号", type: .call),
                    .init(title: "发消息", type: .message),
                ]
            )
        }

        static func deviceOffline(personName: String, hours: Int) -> Warning {
            Warning(
                id: "device_offline",
                severity: hours >= 4 ? .critical : .caution,
                protectedMessage: "你的设备已离线 · 守护者看到的是最后已知状态",
                guardianMessage: "\(personName)的设备已 \(hours) 小时未上报",
                detailText: "可能是关机、离线或权限变更，不代表有危险，但你可能需要主动联系确认。",
                guardianActions: [
                    .init(title: "拨号", type: .call),
                    .init(title: "发消息", type: .message),
                ]
            )
        }

        static func batteryLow(personName: String, level: Int) -> Warning {
            Warning(
                id: "battery_low",
                severity: .critical,
                protectedMessage: "电量极低（\(level)%）· 关机后守护者将无法收到你的信号",
                guardianMessage: "\(personName)的电量低于 \(level)% · 设备可能即将关机",
                detailText: "设备电量已降至 \(level)%。如果设备关机，位置上报、心跳信号和紧急求助功能都将停止。\n\n建议尽快充电或通过其他方式联系。"
            )
        }

        static func backgroundRefreshDisabled(personName: String) -> Warning {
            Warning(
                id: "bg_refresh_disabled",
                severity: .caution,
                protectedMessage: "后台刷新被系统关闭 · 定位和心跳上报可能中断",
                guardianMessage: "\(personName)的应用后台权限受限 · 上报已中断",
                detailText: "iOS 系统或省电模式已限制守灯的后台运行能力。这意味着位置上报和心跳信号可能不完整。\n\n请前往「设置 > 通用 > 后台 App 刷新」确认守灯已开启。",
                protectedActions: [
                    .init(title: "去设置修复", type: .openSettings),
                    .init(title: "稍后", type: .dismiss),
                ]
            )
        }

        static func notificationDisabled(personName: String) -> Warning {
            Warning(
                id: "notification_disabled",
                severity: .caution,
                protectedMessage: "通知权限已关闭 · 你可能收不到求助相关的消息",
                guardianMessage: "\(personName)可能收不到你的消息",
                detailText: "通知权限被关闭后，守灯无法在紧急情况下向你推送提醒。\n\n请前往「设置 > 通知 > 守灯」开启通知。",
                protectedActions: [
                    .init(title: "去设置修复", type: .openSettings),
                    .init(title: "稍后", type: .dismiss),
                ]
            )
        }

        static func noGuardianOnDuty() -> Warning {
            Warning(
                id: "no_guardian_on_duty",
                severity: .caution,
                protectedMessage: "当前无人值班 · 触发求助时仅有推送通知",
                guardianMessage: "当前无守护者值班 · 建议调整排程或邀请其他时区的家人",
                detailText: "当前时段没有守护者排班。如果此时触发紧急求助，系统会向所有守护者发送推送通知，但深夜推送可能无法叫醒对方。\n\n升级至加强版可启用自动语音外呼，在无人响应时拨打电话。"
            )
        }

        static func serverFault() -> Warning {
            Warning(
                id: "server_fault",
                severity: .caution,
                protectedMessage: "服务异常 · 部分功能可能暂时不可用",
                guardianMessage: "服务异常 · 数据可能不完整",
                detailText: "守灯服务器当前出现异常，部分功能可能暂时不可用。我们正在修复中。\n\n紧急情况下请直接拨打当地紧急号码。"
            )
        }
    }

    // MARK: - SOS In-Progress Banner

    enum SOS {
        /// The banner must never claim the family was notified before the server
        /// confirms it, and names the LOCAL emergency number.
        static func persistentBanner(delivered: Bool, noGuardians: Bool, emergencyNumber: String) -> String {
            let lm = LanguageManager.shared
            let key = noGuardians ? "sos.banner.noGuardians" : (delivered ? "sos.banner.delivered" : "sos.banner.sending")
            return String(format: lm.localized(key), emergencyNumber)
        }
    }

    // MARK: - Banned Words (for development-time checks)

    static let bannedWords = [
        "监控", "追踪", "保证", "确保", "保障", "报警", "实时", "一键报警", "精准检测",
    ]

    // MARK: - Replacement Phrases

    static let replacementPhrases: [(banned: String, replacement: String)] = [
        ("保障您家人的安全", "在紧急时刻更快联系上你的家人"),
        ("我们会救援", "我们会通知您指定的联系人"),
        ("24小时保护您", "24 小时自动升级通知"),
        ("精准检测跌倒", "检测可能的跌倒，可能漏报或误报"),
        ("实时位置", "最近一次上报的位置（附时间戳）"),
        ("永不失联", "长时间无回应时主动提醒您的家人"),
    ]

    // MARK: - Location Display Rule
    // 界面铁律：永不显示裸的「当前位置」，一律写作「12 分钟前 · 基辅」

    static func formattedLocationTimestamp(_ date: Date, cityName: String) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)

        if minutes < 1 {
            return "刚刚 · \(cityName)"
        } else if minutes < 60 {
            return "\(minutes) 分钟前 · \(cityName)"
        } else {
            let hours = minutes / 60
            return "\(hours) 小时前 · \(cityName)"
        }
    }
}
