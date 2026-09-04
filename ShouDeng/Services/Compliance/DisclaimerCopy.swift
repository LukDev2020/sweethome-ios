import Foundation

// MARK: - Versioned Disclaimer Copy
//
// ALL user-facing legal/disclaimer text lives here.
// Legal reviews one file. Version bump re-triggers disclosure.
// Never scatter disclaimer text across view files.

enum DisclaimerCopy {

    // MARK: - Onboarding (3 screens)

    enum Onboarding {
        static let version = "v1.1"

        struct Screen {
            let id: String
            let icon: String          // SF Symbol name
            let title: String
            let body: String
            let buttonTitle: String
        }

        static let screens: [Screen] = [
            Screen(
                id: "onboard.not_emergency",
                icon: "exclamationmark.triangle",
                title: "守灯不是紧急服务",
                body: "遇到危险时，请优先拨打当地紧急号码。\n\n守灯的作用是通知你的家人和联系人，无法替代警方、消防或急救。我们会尽力送达通知，但无法保证网络、设备或对方一定能及时响应。",
                buttonTitle: "我明白了"
            ),
            Screen(
                id: "onboard.scope",
                icon: "eye.slash",
                title: "我们只看安全需要的",
                body: "家人可以看到你的位置、电量和是否在线。\n\n他们看不到你的聊天记录、相册、通话记录，也看不到任何其他应用的内容。\n\n这些内容我们同样不会收集。",
                buttonTitle: "继续"
            ),
            Screen(
                id: "onboard.control",
                icon: "hand.raised",
                title: "控制权在你手里",
                body: "你随时可以关闭任何一项共享。\n\n关闭后延迟 6 小时生效——这是为了防止在胁迫下被要求当场关闭。如果你处于安全环境，6 小时后共享将彻底停止。",
                buttonTitle: "开始使用"
            ),
        ]
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

        var title: String {
            switch self {
            case .sos:            return "发出求助前请确认"
            case .location:       return "共享你的位置"
            case .trajectory:     return "轨迹记录"
            case .fallDetection:  return "跌倒检测"
            case .emergencyAudio: return "求助时的环境录音"
            case .autoVoiceCall:  return "自动语音外呼"
            }
        }

        var body: String {
            switch self {
            case .sos:
                return "求助将通知你指定的联系人。\n\n如果情况危急，请同时拨打 112。守灯不会代你拨打急救电话。"
            case .location:
                return "开启后，你选择的家人可以看到你最近一次上报的位置。\n\n位置每次上报都带有时间，他们看到的是「几分钟前你在哪」，不是持续的跟随。"
            case .trajectory:
                return "开启后，守灯会保存你最近 7 天走过的路线，用于在紧急情况下帮助家人判断你可能去了哪里。\n\n日常情况下家人只能看到你最近的位置，看不到路线。只有在你触发求助时，最近两小时的轨迹才会对他们可见。"
            case .fallDetection:
                return "跌倒检测基于手机传感器估算，不是医疗设备，未经任何监管机构认证。\n\n它可能漏掉真实的跌倒，也可能被日常动作误触发。请不要将其作为唯一的安全手段。"
            case .emergencyAudio:
                return "部分国家和地区要求录音需经所有在场者同意。请了解你所在地的法律后再开启。\n\n录音仅在求助期间进行，结束后自动停止。"
            case .autoVoiceCall:
                return "如果推送和短信都没人回应，系统会依次拨打你的联系人电话，直到有人接听并按键确认。\n\n这是为了应对深夜——电话比推送更容易叫醒人。"
            }
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
        static let persistentBanner = "已通知你的家人。如情况危急，请同时拨打 112。"
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
