import Foundation

// MARK: - Versioned Disclaimer Copy
//
// ALL user-facing legal/disclaimer text lives here.
// Legal reviews one file. Version bump re-triggers disclosure.
// Never scatter disclaimer text across view files.

enum DisclaimerCopy {

    // MARK: - Onboarding (3 screens)

    enum Onboarding {
        static let version = "v1.0"

        struct Screen {
            let id: String
            let icon: String          // SF Symbol name
            let title: String
            let body: String
            let buttonTitle: String
        }

        static let screens: [Screen] = [
            Screen(
                id: "onboarding_1",
                icon: "exclamationmark.triangle",
                title: "守灯不是紧急服务",
                body: "遇险请优先拨打当地紧急号码（如 112、911）。\n\n守灯会尽力将通知送达你指定的家人，但无法保证网络、设备或对方一定能及时响应。",
                buttonTitle: "我明白了"
            ),
            Screen(
                id: "onboarding_2",
                icon: "eye.slash",
                title: "我们看什么、不看什么",
                body: "我们可能访问：\n  - 位置（你选择共享时）\n  - 电量与在线状态\n  - 健康传感器（你授权时）\n\n我们绝不访问：\n  - 聊天记录\n  - 相册\n  - 通话记录\n  - 任何其他应用内容",
                buttonTitle: "我明白了"
            ),
            Screen(
                id: "onboarding_3",
                icon: "hand.raised",
                title: "你始终拥有控制权",
                body: "你随时可以关闭任何一项共享。\n\n关闭后延迟 6 小时生效——这是为了防止在胁迫下被要求当场关闭。如果你处于安全环境，6 小时后共享将彻底停止。",
                buttonTitle: "开始使用"
            ),
        ]
    }

    // MARK: - Feature Disclosures (per-feature, first use)

    enum FeatureDisclosure: String, CaseIterable, Identifiable {
        case sos
        case location
        case fallDetection
        case emergencyAudio

        var id: String { rawValue }
        var version: String { "v1.0" }

        var storageKey: String {
            "disclosure_\(rawValue)_\(version)"
        }

        var icon: String {
            switch self {
            case .sos:            return "sos"
            case .location:       return "location.slash"
            case .fallDetection:  return "figure.fall"
            case .emergencyAudio: return "mic.badge.xmark"
            }
        }

        var title: String {
            switch self {
            case .sos:            return "关于紧急求助"
            case .location:       return "关于位置共享"
            case .fallDetection:  return "关于跌倒检测"
            case .emergencyAudio: return "关于环境录音"
            }
        }

        var body: String {
            switch self {
            case .sos:
                return "守灯会通知你指定的联系人，但不会代你拨打急救电话。\n\n请在安全时自行拨打当地紧急号码。"
            case .location:
                return "守护者看到的是你最近一次上报的位置，不是精确实时位置。\n\n设备离线、关机或权限变更时，位置会停止更新，我们会如实告知双方。"
            case .fallDetection:
                return "跌倒检测基于手机传感器推断，可能漏报或误报。\n\n它不能替代医疗设备或专业监护。"
            case .emergencyAudio:
                return "紧急求助期间，手机会录制周围声音并发送给你的守护者，用于判断现场情况。\n\n求助结束后自动停止，录音保留 72 小时后删除。"
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

            enum Severity {
                case caution   // lamp color
                case critical  // alert color
            }
        }

        static func locationRevoked(personName: String) -> Warning {
            Warning(
                id: "location_revoked",
                severity: .critical,
                protectedMessage: "位置共享已中断 · 守护者无法看到你的位置",
                guardianMessage: "\(personName)的位置共享已中断 · 可能是权限变更或关机",
                detailText: "系统检测到位置权限被关闭或降级。守护者端目前看到的是最后一次上报的位置。\n\n如果这不是你的操作，请前往「设置 > 隐私 > 定位服务」检查守灯的权限。"
            )
        }

        static func deviceOffline(personName: String, hours: Int) -> Warning {
            Warning(
                id: "device_offline",
                severity: hours >= 4 ? .critical : .caution,
                protectedMessage: "你的设备已离线 · 守护者看到的是最后已知状态",
                guardianMessage: "\(personName)的设备已 \(hours) 小时未上报 · 可能是关机、离线或权限变更，不代表有危险",
                detailText: "设备上一次与服务器通信已超过 \(hours) 小时。可能的原因包括关机、飞行模式、网络不可用或电量耗尽。\n\n建议通过其他方式主动联系确认。"
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
                guardianMessage: "\(personName)的应用后台权限受限 · 数据可能不完整",
                detailText: "iOS 系统或省电模式已限制守灯的后台运行能力。这意味着位置上报和心跳信号可能不完整。\n\n请前往「设置 > 通用 > 后台 App 刷新」确认守灯已开启。"
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
    }

    // MARK: - Banned Words (for development-time checks)

    static let bannedWords = [
        "监控", "追踪", "保证", "确保", "保障", "报警", "实时", "一键报警",
    ]
}
