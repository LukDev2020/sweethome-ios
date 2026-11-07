import SwiftUI

// MARK: - Privacy Policy View
//
// In-app privacy policy required by App Store.
// Shows both privacy policy and terms of service.

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(LegalCopy.blocks(for: lang.current,
                                                   emergencyNumber: coordinator.localEmergencyNumber).enumerated()),
                            id: \.offset) { _, block in
                        switch block {
                        case .title(let text): sectionTitle(text)
                        case .updated(let text): lastUpdated(text)
                        case .header(let text): sectionHeader(text)
                        case .body(let text): bodyText(text)
                        case .bullet(let title, let detail): bulletPoint(title, detail: detail)
                        case .divider: Divider().padding(.vertical, 8)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle(lang.localized("legal.navTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Label(lang.localized("legal.done"), systemImage: "checkmark") }
                }
            }
        }
    }

    // MARK: - Components

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.scaled(size: 18, weight: .bold))
            .padding(.bottom, 4)
    }

    private func lastUpdated(_ text: String) -> some View {
        Text(text)
            .font(.scaled(size: 12))
            .foregroundStyle(.secondary)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.scaled(size: 14, weight: .semibold))
            .padding(.top, 4)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.scaled(size: 13))
            .foregroundStyle(.primary.opacity(0.85))
            .lineSpacing(4)
    }

    private func bulletPoint(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.scaled(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.scaled(size: 13, weight: .medium))
                Text(detail)
                    .font(.scaled(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }
}

// MARK: - About View (accessible from settings)

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var showPrivacy = false

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(LanguageManager.shared.current.brandName)
                    .font(.scaled(size: 24, weight: .bold, design: .serif))

                Text(LanguageManager.shared.current.isChinese ? LanguageManager.shared.zh("让每一盏灯都不孤单") : "Family safety, always on")
                    .font(.scaled(size: 13))
                    .foregroundStyle(.secondary)

                Text(String(format: LanguageManager.shared.localized("legal.version"), version, build))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.tertiary)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showPrivacy = true
                    } label: {
                        Text(LanguageManager.shared.localized("legal.linkTitle"))
                            .font(.scaled(size: 13))
                    }

                    Text(LanguageManager.shared.current.isChinese ? LanguageManager.shared.zh("© 2026 守灯安全") : "© 2026 Lantern Care")
                        .font(.scaled(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle(LanguageManager.shared.localized("legal.about"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Label(LanguageManager.shared.localized("legal.done"), systemImage: "checkmark") }
                }
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyPolicyView().environmentObject(coordinator)
            }
        }
    }
}

// MARK: - Policy text
//
// Simplified Chinese is the source; Traditional is converted at runtime.
// Keep the four versions in step — have counsel review before each release.

enum LegalCopy {
    enum Block {
        case title(String), updated(String), header(String), body(String)
        case bullet(String, String)
        case divider
    }

    static func blocks(for language: AppLanguage, emergencyNumber: String) -> [Block] {
        switch language {
        case .english: return english(emergencyNumber)
        case .french: return french(emergencyNumber)
        case .japanese: return japanese(emergencyNumber)
        case .chinese: return chinese(emergencyNumber)
        case .traditionalChinese: return chinese(emergencyNumber).map(traditional)
        }
    }

    private static func traditional(_ block: Block) -> Block {
        let zh = LanguageManager.toTraditional
        switch block {
        case .title(let t): return .title(zh(t))
        case .updated(let t): return .updated(zh(t))
        case .header(let t): return .header(zh(t))
        case .body(let t): return .body(zh(t))
        case .bullet(let a, let b): return .bullet(zh(a), zh(b))
        case .divider: return .divider
        }
    }

    private static func chinese(_ sos: String) -> [Block] {[
        .title("隐私政策"),
        .updated("最后更新：2026 年 10 月 31 日"),
        .header("一、我们收集哪些信息"),
        .bullet("位置信息", "用于安全区检测、紧急求助定位和行动轨迹记录。仅在您授权后收集，且仅与您指定的守护者共享。"),
        .bullet("运动传感器数据", "用于跌倒检测。原始传感器读数只在设备上处理；我们只随位置一起上传活动类型（如步行、驾车），检测到跌倒时上传跌倒提醒。"),
        .bullet("手机号码", "用于账号注册和紧急短信通知。"),
        .bullet("设备信息", "电量、在线状态等，用于守护者了解被守护设备是否正常工作。"),
        .header("二、我们如何使用信息"),
        .body("所有收集的信息仅用于以下目的："),
        .bullet("紧急求助", "在 SOS 触发时向守护者发送您的位置。"),
        .bullet("安全监测", "检测异常情况（如跌倒、失联）并及时通知守护者。"),
        .bullet("报平安", "让守护者了解您的安全状态。"),
        .header("三、数据保留"),
        .body("免费方案：位置和在线记录保留 7 天，报平安记录保留 30 天。\n付费方案：位置和在线记录按方案保留 90、180 或 365 天，报平安记录一直保留。被守护者跟随为其付费的守护者的方案。\nSOS 事件记录和知情同意记录一直保留。"),
        .header("四、数据共享"),
        .body("您的位置和安全信息仅与您明确授权的守护者共享。我们不会出售您的个人信息。SOS 位置链接只在您或求助升级流程中生成，48 小时内失效。您主动生成的医疗卡分享链接最长有效 1 年，可随时撤销。您发到家庭动态的照片保存在不公开的链接中，持有链接的人可以打开。"),
        .header("五、数据存储地点与跨境传输"),
        .body("您的数据存储在美国（Google Cloud / Firebase，us-central1 区域）。为提供服务，以下服务商会处理您的部分信息：Google（账号登录、数据库与存储、推送通知、崩溃报告、地址查询）、Twilio（紧急短信和语音电话，美国）、Apple（推送通知、地图、App Store 付款）。如您身处美国以外，您的信息会被传输到美国处理，注册时我们会单独征得您的同意。我们与上述服务商签有数据处理条款，要求其以不低于本政策的标准保护您的信息。"),
        .header("六、数据安全"),
        .body("所有数据传输使用 TLS 加密。敏感凭证存储在 iOS 钥匙串中。服务器端数据静态加密。我们每天为位置和在线记录生成加密指纹（Merkle 根），用于发现记录是否被改动。"),
        .header("七、您的权利"),
        .bullet("访问权", "您可以随时在设置中导出全部数据，保存为一个文件。"),
        .bullet("删除权", "您可以在设置中注销账号，删除账号和全部数据。我们只保留法律要求的知情同意记录，以及处于法律保全期内的证据；刚写入的历史记录会在 24 小时内删除。"),
        .bullet("撤回同意", "您可以随时在系统设置中关闭位置或运动传感器权限。"),
        .header("八、联系我们"),
        .body("如您对隐私政策有任何疑问，请联系：\nprivacy@shoudeng.app"),
        .divider,
        .title("服务条款"),
        .updated("最后更新：2026 年 11 月 6 日"),
        .header("一、服务描述"),
        .body("守灯是一款个人安全应用，为被守护者和守护者提供紧急求助通知、位置共享、报平安、跌倒检测等功能。守灯不是紧急服务，不替代 \(sos) 等专业紧急服务。"),
        .header("二、不作保证"),
        .body("守灯按现状提供。我们会尽力送达通知，但不保证每条通知都能发出、及时送达、被看到或得到回应。通知依赖手机开机、电量、网络、系统权限（定位、通知、实时活动等）以及 Apple、Google 和运营商等第三方服务，任何一项出问题都可能导致延迟或失败。位置可能不准确。跌倒、语音和声音检测是可选功能，可能漏报或误报，不是医疗器械。遇到危险时，请务必先拨打 \(sos)。"),
        .header("三、守护者"),
        .body("守护者是用户自己选择的家人或朋友，不是专业救援人员。守灯不会派人到场救助，也不代表任何守护者承诺随时回应。守护者应在力所能及的范围内提供帮助，认为有人身危险时应拨打当地紧急号码。"),
        .header("四、知情同意与合法使用"),
        .body("只能在对方同意的情况下守护对方或查看对方的位置。禁止在他人不知情或不同意的情况下使用守灯追踪他人；为未成年人或无行为能力人使用本应用的，须由依法有权代其同意的人决定。违反本条的账号可能被暂停或注销。"),
        .header("五、责任限制"),
        .body("在法律允许的最大范围内，对于因通知未能发出、送达、被看到或得到回应，位置或检测不准确，服务中断，或第三方服务故障所造成的任何损失或伤害，以及任何间接、附带或后果性损失，守灯及其运营方不承担责任。在法律允许的范围内，我们对您的全部责任以您在此前 12 个月内为本服务支付的金额为限。本条不排除或限制依法不得排除或限制的责任，也不影响您作为消费者依法享有的权利。"),
        .header("六、订阅与付费"),
        .body("付费订阅通过 Apple App Store 处理。订阅自动续费，可在 Apple ID 设置中随时取消。取消后当前付费周期内仍可使用付费功能。"),
        .header("七、账号与数据"),
        .body("您有责任保管好账号安全。注销账号将永久删除所有相关数据，此操作不可撤销。"),
        .header("八、条款变更"),
        .body("我们可能更新本条款。重要变更会在应用内请您重新阅读并同意；不同意的，您可以停止使用并注销账号。"),
    ]}

    private static func english(_ sos: String) -> [Block] {[
        .title("Privacy Policy"),
        .updated("Last updated: October 31, 2026"),
        .header("1. What we collect"),
        .bullet("Location", "Used for safe-zone alerts, SOS location and your movement history. Collected only after you allow it, and shared only with the guardians you choose."),
        .bullet("Motion sensor data", "Used for fall detection. Raw sensor readings stay on your device; we upload only your activity type (such as walking or driving) with your location, and a fall alert if a fall is detected."),
        .bullet("Phone number", "Used to create your account and to send emergency text messages."),
        .bullet("Device information", "Battery level and online status, so guardians can tell the protected phone is working."),
        .header("2. How we use it"),
        .body("We use this information only to:"),
        .bullet("Send SOS alerts", "Share your location with your guardians when an SOS is triggered."),
        .bullet("Watch for problems", "Detect events such as a fall or loss of contact and notify your guardians."),
        .bullet("Check in", "Let your guardians know you are safe."),
        .header("3. How long we keep it"),
        .body("Free plan: location and online-status history is kept for 7 days, check-ins for 30 days.\nPaid plans: location and online-status history is kept for 90, 180 or 365 days depending on the plan; check-ins are kept. A protected person follows the plan of the guardian who pays for them.\nSOS records and consent records are kept indefinitely."),
        .header("4. Who we share it with"),
        .body("Your location and safety information is shared only with guardians you have explicitly approved. We never sell your personal information. SOS location links are created only by you or by the SOS escalation process and expire within 48 hours. A medical-card link you create stays valid for up to 1 year unless you revoke it. Photos you post to the family feed are stored at an unlisted link that anyone who has the link can open."),
        .header("5. Where your data is stored"),
        .body("Your data is stored in the United States (Google Cloud / Firebase, us-central1). To run the service, these providers process some of your information: Google (sign-in, database and storage, push notifications, crash reports, address lookup), Twilio (emergency text messages and voice calls, United States) and Apple (push notifications, Maps, App Store payments). If you live outside the United States, your information is transferred to and processed in the United States; we ask for your separate consent at sign-up. Our agreements with these providers require them to protect your information to at least the standard in this policy."),
        .header("6. Security"),
        .body("All data is encrypted in transit with TLS. Sensitive credentials are kept in the iOS Keychain. Server data is encrypted at rest, and a daily cryptographic fingerprint (Merkle root) of location and online-status records helps us detect changes."),
        .header("7. Your rights"),
        .bullet("Access", "Export all of your data from Settings at any time, saved as one file."),
        .bullet("Deletion", "Delete your account in Settings to erase your account and data. We keep only the consent records the law requires and evidence under a legal hold; history written in the last few minutes is erased within 24 hours."),
        .bullet("Withdraw consent", "Turn off location or motion access in iOS Settings at any time."),
        .header("8. Contact"),
        .body("Questions about this policy? Email privacy@shoudeng.app"),
        .divider,
        .title("Terms of Service"),
        .updated("Last updated: November 6, 2026"),
        .header("1. The service"),
        .body("Lantern Care is a personal safety app that gives the people being looked after and their guardians SOS alerts, location sharing, check-ins, fall detection and related features. Lantern Care is not an emergency service and does not replace emergency services such as \(sos)."),
        .header("2. No guarantee"),
        .body("Lantern Care is provided as is. We do our best to deliver alerts, but we do not guarantee that any alert is sent, delivered on time, seen or acted on. Alerts depend on phones being on and charged, network coverage, permissions (location, notifications, Live Activities) and third-party services such as Apple, Google and mobile carriers; a problem with any of them can delay or stop an alert. Locations can be inaccurate. Fall, voice and sound detection are optional, can miss events or trigger by mistake, and are not medical devices. In danger, always call \(sos) first."),
        .header("3. Guardians"),
        .body("Guardians are family members or friends chosen by the user, not professional responders. Lantern Care does not send anyone to help and does not promise that any guardian will respond. Guardians help as far as they reasonably can and should call the local emergency number if they believe someone is in danger."),
        .header("4. Consent and lawful use"),
        .body("Only look after someone, or view their location, with their agreement. Do not use Lantern Care to track anyone without their knowledge or consent. Use for a minor or a person who cannot consent must be decided by someone legally entitled to consent for them. We may suspend or close accounts that break this rule."),
        .header("5. Limitation of liability"),
        .body("To the fullest extent permitted by law, Lantern Care and its operator are not liable for any loss or harm arising from an alert not being sent, delivered, seen or acted on, from inaccurate location or detection, from interruptions of the service, or from the failure of third-party services, nor for any indirect, incidental or consequential loss. Where the law allows a cap, our total liability to you is limited to the amount you paid for the service in the 12 months before the claim. Nothing in these terms excludes or limits liability that cannot be excluded or limited by law, or your rights as a consumer."),
        .header("6. Subscriptions"),
        .body("Paid subscriptions are handled by the Apple App Store and renew automatically. You can cancel at any time in your Apple ID settings; paid features remain available until the end of the current period."),
        .header("7. Your account"),
        .body("You are responsible for keeping your account secure. Deleting your account permanently erases all associated data and cannot be undone."),
        .header("8. Changes"),
        .body("We may update these terms. For important changes we will ask you in the app to read and agree again; if you don't agree, you can stop using the service and delete your account."),
    ]}

    private static func japanese(_ sos: String) -> [Block] {[
        .title("プライバシーポリシー"),
        .updated("最終更新日：2026年10月31日"),
        .header("1. 収集する情報"),
        .bullet("位置情報", "安全エリアの通知、SOS 時の位置送信、移動履歴に使います。あなたが許可した場合にのみ収集し、あなたが選んだ見守る人とだけ共有します。"),
        .bullet("モーションセンサーのデータ", "転倒検知に使います。センサーの生データは端末内でのみ処理します。送信するのは、位置情報とあわせた移動の種類（徒歩、車など）と、転倒を検知した場合の通知だけです。"),
        .bullet("電話番号", "アカウントの作成と緊急 SMS の送信に使います。"),
        .bullet("端末の情報", "バッテリー残量やオンライン状態。見守る人が、端末が正常に動いているかを確認するために使います。"),
        .header("2. 情報の利用目的"),
        .body("収集した情報は、次の目的にのみ使います。"),
        .bullet("SOS の送信", "SOS が発信されたとき、見守る人にあなたの位置を送ります。"),
        .bullet("異常の検知", "転倒や連絡が取れない状態などを検知し、見守る人に知らせます。"),
        .bullet("無事の報告", "あなたが無事であることを見守る人に知らせます。"),
        .header("3. 保存期間"),
        .body("無料プラン：位置とオンライン状態の履歴は 7 日間、無事報告は 30 日間保存します。\n有料プラン：位置とオンライン状態の履歴はプランに応じて 90・180・365 日間保存し、無事報告は保存し続けます。見守られる人には、その人の分を支払っている見守る人のプランが適用されます。\nSOS の記録と同意の記録は期限なく保存します。"),
        .header("4. 共有"),
        .body("位置情報と安全に関する情報は、あなたが明示的に承認した見守る人とだけ共有します。個人情報を販売することはありません。SOS の位置リンクは、あなた自身または SOS のエスカレーション処理によってのみ作成され、48 時間以内に失効します。あなたが作成した医療カードの共有リンクは、取り消さない限り最長 1 年間有効です。家族フィードに投稿した写真は非公開のリンクに保存され、リンクを知っている人は開くことができます。"),
        .header("5. 保存場所と外国にある第三者への提供"),
        .body("あなたのデータは米国（Google Cloud / Firebase、us-central1 リージョン）に保存されます。サービス提供のため、次の事業者があなたの情報の一部を取り扱います：Google（ログイン、データベースとストレージ、プッシュ通知、クラッシュレポート、住所検索）、Twilio（緊急 SMS と音声通話、米国）、Apple（プッシュ通知、マップ、App Store の支払い）。米国以外にお住まいの場合、あなたの情報は米国に移転され、米国で処理されます。登録時に別途同意をいただきます。米国の個人情報保護制度は日本の制度と異なり、包括的な連邦法はありません。これらの事業者とは、本ポリシーと同等以上の水準で情報を保護することを契約で定めています。"),
        .header("6. セキュリティ"),
        .body("すべての通信は TLS で暗号化されます。重要な認証情報は iOS のキーチェーンに保存されます。サーバー上のデータは保存時に暗号化されます。位置とオンライン状態の記録には毎日暗号学的な指紋（マークルルート）を作成し、改変の検知に役立てています。"),
        .header("7. あなたの権利"),
        .bullet("開示", "設定からいつでもすべてのデータを 1 つのファイルとして書き出せます。"),
        .bullet("削除", "設定でアカウントを削除すると、アカウントとデータが消去されます。法律で必要な同意の記録と、法的保全中の証拠のみ保持します。直前に書き込まれた履歴は 24 時間以内に消去されます。"),
        .bullet("同意の撤回", "iOS の設定で、位置情報やモーションへのアクセスをいつでもオフにできます。"),
        .header("8. お問い合わせ"),
        .body("本ポリシーに関するお問い合わせ：privacy@shoudeng.app"),
        .divider,
        .title("利用規約"),
        .updated("最終更新日：2026年11月6日"),
        .header("1. サービス内容"),
        .body("Lantern Care は、見守られる人と見守る人のための個人向け安全アプリです。SOS 通知、位置共有、安否報告、転倒検知などの機能を提供します。Lantern Care は緊急通報サービスではなく、\(sos) などの緊急サービスの代わりにはなりません。"),
        .header("2. 保証の否認"),
        .body("Lantern Care は現状のまま提供されます。通知が届くよう最善を尽くしますが、通知が送信される、時間どおりに届く、確認される、または対応されることを保証するものではありません。通知は端末の電源やバッテリー、通信環境、権限（位置情報・通知・ライブアクティビティ）、Apple・Google・通信事業者などの第三者サービスに依存し、いずれかに問題があると遅延または失敗することがあります。位置情報が不正確な場合があります。転倒・音声・音の検知は任意の機能で、見逃しや誤作動があり、医療機器ではありません。危険なときは、必ず先に \(sos) に電話してください。"),
        .header("3. 見守る人"),
        .body("見守る人は利用者が選んだ家族や友人であり、救助の専門家ではありません。Lantern Care は誰かを現場に派遣することはなく、見守る人が必ず応答することも約束しません。見守る人は合理的にできる範囲で手助けし、危険があると考えた場合は現地の緊急番号に電話してください。"),
        .header("4. 同意と適法な利用"),
        .body("相手の同意がある場合にのみ、見守りや位置の確認を行ってください。本人に知らせず、または同意なく Lantern Care で人を追跡することは禁止です。未成年者や同意能力のない人のための利用は、法律上その人に代わって同意できる人が判断してください。違反したアカウントは停止または削除されることがあります。"),
        .header("5. 責任の制限"),
        .body("法律で認められる最大限の範囲で、Lantern Care およびその運営者は、通知が送信・配信・確認・対応されなかったこと、位置情報や検知の不正確さ、サービスの中断、第三者サービスの障害から生じた損失や損害、ならびに間接的・付随的・結果的な損失について責任を負いません。上限を設けることが認められる場合、当社の責任の総額は、請求前 12 か月間にお支払いいただいた金額を上限とします。本規約は、法律上除外または制限できない責任や、消費者としての権利を除外・制限するものではありません。"),
        .header("6. サブスクリプション"),
        .body("有料サブスクリプションは Apple の App Store で処理され、自動更新されます。Apple アカウントの設定からいつでも解約でき、解約後も現在の期間が終わるまで有料機能を利用できます。"),
        .header("7. アカウント"),
        .body("アカウントの安全な管理はご自身の責任となります。アカウントを削除すると関連するすべてのデータが完全に消去され、元に戻すことはできません。"),
        .header("8. 規約の変更"),
        .body("本規約は更新されることがあります。重要な変更については、アプリ内で改めてお読みいただき同意をお願いします。同意されない場合は、利用を中止しアカウントを削除できます。"),
    ]}

    private static func french(_ sos: String) -> [Block] {[
        .title("Politique de confidentialité"),
        .updated("Dernière mise à jour : 31 octobre 2026"),
        .header("1. Ce que nous collectons"),
        .bullet("Position", "Sert aux alertes de zone sûre, à la localisation en cas de SOS et à l'historique de vos déplacements. Collectée uniquement avec votre autorisation et partagée seulement avec les proches que vous choisissez."),
        .bullet("Capteurs de mouvement", "Servent à la détection de chute. Les mesures brutes restent sur votre appareil ; nous n'envoyons que le type d'activité (marche, voiture…) avec la position, et une alerte en cas de chute."),
        .bullet("Numéro de téléphone", "Sert à créer votre compte et à envoyer des SMS d'urgence."),
        .bullet("Informations sur l'appareil", "Niveau de batterie et statut en ligne, pour que vos proches sachent que le téléphone fonctionne."),
        .header("2. Comment nous les utilisons"),
        .body("Ces informations servent uniquement à :"),
        .bullet("Envoyer un SOS", "Transmettre votre position à vos proches lorsqu'un SOS est déclenché."),
        .bullet("Surveiller les problèmes", "Détecter une chute ou une perte de contact et prévenir vos proches."),
        .bullet("Signaler que tout va bien", "Permettre à vos proches de savoir que vous êtes en sécurité."),
        .header("3. Durée de conservation"),
        .body("Formule gratuite : historique de position et de connexion conservé 7 jours, signalements 30 jours.\nFormules payantes : historique conservé 90, 180 ou 365 jours selon la formule ; signalements conservés. Une personne protégée suit la formule du proche qui paie pour elle.\nLes événements SOS et les consentements sont conservés sans limite."),
        .header("4. Partage"),
        .body("Vos informations de position et de sécurité ne sont partagées qu'avec les proches que vous avez explicitement autorisés. Nous ne vendons jamais vos données personnelles. Les liens de position SOS ne sont créés que par vous ou par la procédure d'escalade SOS et expirent sous 48 heures. Un lien de fiche médicale que vous créez reste valable jusqu'à 1 an, sauf révocation. Les photos publiées dans le fil familial sont stockées à une adresse non répertoriée, accessible à toute personne qui possède le lien."),
        .header("5. Lieu de stockage et transferts internationaux"),
        .body("Vos données sont stockées aux États-Unis (Google Cloud / Firebase, région us-central1). Pour fournir le service, ces prestataires traitent une partie de vos informations : Google (connexion, base de données et stockage, notifications, rapports de plantage, recherche d'adresse), Twilio (SMS et appels d'urgence, États-Unis) et Apple (notifications, Plans, paiements App Store). Si vous résidez hors des États-Unis, vos informations y sont transférées et traitées ; nous vous demandons un consentement distinct à l'inscription. Nos contrats avec ces prestataires les obligent à protéger vos informations au moins au niveau de la présente politique."),
        .header("6. Sécurité"),
        .body("Toutes les données sont chiffrées en transit (TLS). Les identifiants sensibles sont conservés dans le trousseau iOS. Les données serveur sont chiffrées au repos, et une empreinte cryptographique quotidienne (racine de Merkle) des historiques de position et de connexion nous aide à détecter toute modification."),
        .header("7. Vos droits"),
        .bullet("Accès", "Exportez toutes vos données depuis les Réglages à tout moment, dans un seul fichier."),
        .bullet("Suppression", "Supprimez votre compte dans les Réglages pour effacer votre compte et vos données. Nous ne gardons que les consentements exigés par la loi et les éléments sous conservation légale ; l'historique des dernières minutes est effacé sous 24 heures."),
        .bullet("Retrait du consentement", "Désactivez l'accès à la position ou aux mouvements dans les Réglages iOS à tout moment."),
        .header("8. Contact"),
        .body("Une question sur cette politique ? Écrivez à privacy@shoudeng.app"),
        .divider,
        .title("Conditions d'utilisation"),
        .updated("Dernière mise à jour : 6 novembre 2026"),
        .header("1. Le service"),
        .body("Lantern Care est une app de sécurité personnelle qui offre aux personnes protégées et à leurs proches des alertes SOS, le partage de position, les signes de vie, la détection de chute et des fonctions associées. Lantern Care n'est pas un service d'urgence et ne remplace pas les services d'urgence comme le \(sos)."),
        .header("2. Absence de garantie"),
        .body("Lantern Care est fourni en l'état. Nous faisons de notre mieux pour transmettre les alertes, mais ne garantissons pas qu'une alerte soit envoyée, reçue à temps, vue ou suivie d'effet. Les alertes dépendent d'un téléphone allumé et chargé, du réseau, des autorisations (position, notifications, Activités en direct) et de services tiers comme Apple, Google et les opérateurs ; un problème avec l'un d'eux peut retarder ou empêcher une alerte. La position peut être imprécise. La détection de chute, de voix et de sons est facultative, peut manquer un événement ou se déclencher par erreur, et n'est pas un dispositif médical. En cas de danger, appelez toujours d'abord le \(sos)."),
        .header("3. Les gardiens"),
        .body("Les gardiens sont des proches choisis par l'utilisateur, pas des secouristes. Lantern Care n'envoie personne sur place et ne promet pas qu'un gardien répondra. Les gardiens aident dans la mesure du raisonnable et appellent le numéro d'urgence local s'ils pensent qu'une personne est en danger."),
        .header("4. Consentement et usage licite"),
        .body("Ne veillez sur une personne, ou ne consultez sa position, qu'avec son accord. N'utilisez pas Lantern Care pour suivre quelqu'un à son insu ou sans son consentement. L'usage pour un mineur ou une personne qui ne peut consentir relève de la personne légalement habilitée à consentir pour elle. Nous pouvons suspendre ou fermer les comptes qui enfreignent cette règle."),
        .header("5. Limitation de responsabilité"),
        .body("Dans toute la mesure permise par la loi, Lantern Care et son exploitant ne sont pas responsables des pertes ou dommages résultant d'une alerte non envoyée, non reçue, non vue ou non suivie d'effet, d'une position ou d'une détection inexacte, d'une interruption du service ou de la défaillance de services tiers, ni des pertes indirectes, accessoires ou consécutives. Lorsque la loi permet un plafond, notre responsabilité totale envers vous est limitée aux sommes payées pour le service au cours des 12 mois précédant la réclamation. Rien dans ces conditions n'exclut ni ne limite une responsabilité qui ne peut l'être en vertu de la loi, ni vos droits de consommateur."),
        .header("6. Abonnements"),
        .body("Les abonnements payants sont gérés par l'App Store d'Apple et se renouvellent automatiquement. Vous pouvez résilier à tout moment dans les réglages de votre identifiant Apple ; les fonctions payantes restent disponibles jusqu'à la fin de la période en cours."),
        .header("7. Votre compte"),
        .body("Vous êtes responsable de la sécurité de votre compte. La suppression du compte efface définitivement toutes les données associées et ne peut pas être annulée."),
        .header("8. Modifications"),
        .body("Nous pouvons mettre à jour ces conditions. Pour toute modification importante, nous vous demanderons dans l'app de les relire et de les accepter ; si vous refusez, vous pouvez cesser d'utiliser le service et supprimer votre compte."),
    ]}
}

/// A data export file waiting to be shared (Settings → Export all my data).
struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

// MARK: - Data location consent

/// Consent to storage and processing in the United States. Must match
/// DATA_TRANSFER_CONSENT_VERSION in the backend (services/consent.ts); bump both
/// when the wording changes and everyone is asked again.
enum DataTransferConsent {
    static let version = "2026-10-31"
}

/// Sign-up checkbox: "I agree that my data is stored and processed in the United States."
struct DataTransferConsentToggle: View {
    @Binding var isOn: Bool
    @ObservedObject private var lang = LanguageManager.shared
    @State private var showPolicy = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { isOn.toggle() } label: {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.scaled(size: 20))
                    .foregroundStyle(isOn ? Color(red: 63/255, green: 143/255, blue: 110/255) : .secondary)
            }
            .accessibilityLabel(lang.localized("consent.transfer.checkbox"))
            .accessibilityAddTraits(isOn ? .isSelected : [])
            VStack(alignment: .leading, spacing: 4) {
                Text(lang.localized("consent.transfer.checkbox"))
                    .font(.scaled(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
                Button(lang.localized("consent.transfer.readPolicy")) { showPolicy = true }
                    .font(.scaled(size: 12, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showPolicy) { PrivacyPolicyView() }
    }
}

/// Settings → Data → Data storage location. Shows where data is stored and lets
/// people who signed up before the consent existed agree. Never pops up by itself.
struct DataLocationView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var showPolicy = false
    @State private var isSaving = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(lang.localized("consent.transfer.title"))
                    .font(.scaled(size: 20, weight: .bold))
                Text(lang.localized("consent.transfer.body"))
                    .font(.scaled(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(lang.localized("consent.transfer.readPolicy")) { showPolicy = true }
                    .font(.scaled(size: 14, weight: .medium))

                if coordinator.needsDataTransferConsent {
                    if failed {
                        Text(lang.localized("consent.transfer.failed"))
                            .font(.scaled(size: 13))
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            do { try await coordinator.recordDataTransferConsent() } catch { failed = true }
                        }
                    } label: {
                        Text(lang.localized("consent.transfer.agree"))
                            .font(.scaled(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 1/255, green: 69/255, blue: 129/255)))
                    }
                    .disabled(isSaving)
                    Text(lang.localized("consent.transfer.declined.body"))
                        .font(.scaled(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label(lang.localized("consent.transfer.agreed"), systemImage: "checkmark.seal.fill")
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(Color(red: 63/255, green: 143/255, blue: 110/255))
                }
            }
            .padding(20)
        }
        .navigationTitle(lang.localized("settings.data.storageLocation"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPolicy) { PrivacyPolicyView().environmentObject(coordinator) }
    }
}

// MARK: - Terms agreement (login / sign-up)

/// "I've read and agree to the Terms of Service and Privacy Policy" — required before
/// a code is sent, so every account has agreed to the current Terms. The tap is logged
/// (ConsentLogger) and sent to the server after sign-in.
struct TermsAgreementRow: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage("terms_accepted_version") private var acceptedVersion = ""
    @State private var showTerms = false
    var tint: Color = Color(red: 1/255, green: 69/255, blue: 129/255)

    static var isAccepted: Bool {
        UserDefaults.standard.string(forKey: "terms_accepted_version") == DisclaimerCopy.Terms.version
    }

    private var accepted: Bool { acceptedVersion == DisclaimerCopy.Terms.version }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                if accepted {
                    acceptedVersion = ""
                } else {
                    acceptedVersion = DisclaimerCopy.Terms.version
                    ConsentLogger.shared.logTermsAccepted()
                }
            } label: {
                Image(systemName: accepted ? "checkmark.square.fill" : "square")
                    .font(.scaled(size: 20))
                    .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lang.localized("terms.agree"))
            .accessibilityAddTraits(accepted ? .isSelected : [])
            VStack(alignment: .leading, spacing: 4) {
                Text(lang.localized("terms.agree"))
                    .font(.scaled(size: 13))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
                Button(lang.localized("terms.read")) { showTerms = true }
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .underline()
                    .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showTerms) {
            PrivacyPolicyView().environmentObject(coordinator)
        }
    }
}
