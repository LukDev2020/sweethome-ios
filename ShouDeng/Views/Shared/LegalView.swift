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
                    Button(lang.localized("legal.done")) { dismiss() }
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
                    Button(LanguageManager.shared.localized("legal.done")) { dismiss() }
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
        .bullet("运动传感器数据", "用于跌倒检测。数据仅在设备本地处理，不上传服务器。"),
        .bullet("手机号码", "用于账号注册和紧急短信通知。"),
        .bullet("设备信息", "电量、在线状态等，用于守护者了解被守护设备是否正常工作。"),
        .header("二、我们如何使用信息"),
        .body("所有收集的信息仅用于以下目的："),
        .bullet("紧急求助", "在 SOS 触发时向守护者发送您的位置。"),
        .bullet("安全监测", "检测异常情况（如跌倒、失联）并及时通知守护者。"),
        .bullet("报平安", "让守护者了解您的安全状态。"),
        .header("三、数据保留"),
        .body("免费用户：位置数据保留 7 天，签到记录保留 30 天。\n付费用户：位置数据保留 90 天，签到记录永久保留。\nSOS 事件记录和知情同意审计日志永久保留。"),
        .header("四、数据共享"),
        .body("您的位置和安全信息仅与您明确授权的守护者共享。我们不会向任何第三方出售您的个人信息。紧急分享链接仅在您或系统升级链自动生成时创建，且有效期不超过 48 小时。"),
        .header("五、数据存储地点与跨境传输"),
        .body("您的数据存储在美国（Google Cloud / Firebase，us-central1 区域）。紧急短信和语音电话通过 Twilio（美国）发送。如您身处美国以外，使用本应用即表示您的信息会被传输到美国处理。我们与上述服务商签有数据处理条款，要求其以不低于本政策的标准保护您的信息。"),
        .header("六、数据安全"),
        .body("所有数据传输使用 TLS 加密。敏感凭证存储在 iOS 钥匙串中。服务器端数据静态加密。每日生成 Merkle 树完整性证明，确保数据未被篡改。"),
        .header("七、您的权利"),
        .bullet("访问权", "您可以随时在设置中导出您的全部数据。"),
        .bullet("删除权", "您可以在设置中注销账号，永久删除所有数据。"),
        .bullet("撤回同意", "您可以随时在系统设置中关闭位置或运动传感器权限。"),
        .header("八、联系我们"),
        .body("如您对隐私政策有任何疑问，请联系：\nprivacy@shoudeng.app"),
        .divider,
        .title("服务条款"),
        .updated("最后更新：2026 年 10 月 31 日"),
        .header("一、服务描述"),
        .body("守灯是一款个人安全守护应用，为被守护者和守护者提供紧急求助、位置共享、跌倒检测等安全功能。本应用不替代 \(sos) 等专业紧急服务。"),
        .header("二、免责声明"),
        .body("守灯作为辅助安全工具，不保证在所有情况下都能成功发送警报。网络故障、设备损坏、电量耗尽等因素可能影响服务可用性。在紧急情况下，请务必同时拨打当地急救电话 \(sos)。"),
        .header("三、订阅与付费"),
        .body("付费订阅通过 Apple App Store 处理。订阅自动续费，可在 Apple ID 设置中随时取消。取消后当前付费周期内仍可使用付费功能。"),
        .header("四、账号与数据"),
        .body("您有责任保管好账号安全。注销账号将永久删除所有相关数据，此操作不可撤销。"),
    ]}

    private static func english(_ sos: String) -> [Block] {[
        .title("Privacy Policy"),
        .updated("Last updated: October 31, 2026"),
        .header("1. What we collect"),
        .bullet("Location", "Used for safe-zone alerts, SOS location and your movement history. Collected only after you allow it, and shared only with the guardians you choose."),
        .bullet("Motion sensor data", "Used for fall detection. Processed on your device only and never uploaded."),
        .bullet("Phone number", "Used to create your account and to send emergency text messages."),
        .bullet("Device information", "Battery level and online status, so guardians can tell the protected phone is working."),
        .header("2. How we use it"),
        .body("We use this information only to:"),
        .bullet("Send SOS alerts", "Share your location with your guardians when an SOS is triggered."),
        .bullet("Watch for problems", "Detect events such as a fall or loss of contact and notify your guardians."),
        .bullet("Check in", "Let your guardians know you are safe."),
        .header("3. How long we keep it"),
        .body("Free plan: location data is kept for 7 days and check-ins for 30 days.\nPaid plans: location data is kept for 90 days and check-ins indefinitely.\nSOS records and consent audit logs are kept indefinitely."),
        .header("4. Who we share it with"),
        .body("Your location and safety information is shared only with guardians you have explicitly approved. We never sell your personal information. Emergency share links are created only by you or by the SOS escalation process, and expire within 48 hours."),
        .header("5. Where your data is stored"),
        .body("Your data is stored in the United States (Google Cloud / Firebase, us-central1). Emergency text messages and voice calls are sent through Twilio (United States). If you live outside the United States, using the app means your information is transferred to and processed in the United States. Our agreements with these providers require them to protect your information to at least the standard in this policy."),
        .header("6. Security"),
        .body("All data is encrypted in transit with TLS. Sensitive credentials are kept in the iOS Keychain. Server data is encrypted at rest, and a daily Merkle-tree integrity proof shows records have not been altered."),
        .header("7. Your rights"),
        .bullet("Access", "Export all of your data from Settings at any time."),
        .bullet("Deletion", "Delete your account in Settings to permanently erase all of your data."),
        .bullet("Withdraw consent", "Turn off location or motion access in iOS Settings at any time."),
        .header("8. Contact"),
        .body("Questions about this policy? Email privacy@shoudeng.app"),
        .divider,
        .title("Terms of Service"),
        .updated("Last updated: October 31, 2026"),
        .header("1. The service"),
        .body("Lantern Care is a personal safety app that gives protected people and their guardians SOS alerts, location sharing, fall detection and related features. It does not replace emergency services such as \(sos)."),
        .header("2. Disclaimer"),
        .body("Lantern Care is a supporting safety tool and cannot guarantee that every alert is delivered. Network outages, device damage, a flat battery and other factors can affect it. In an emergency, always call \(sos) as well."),
        .header("3. Subscriptions"),
        .body("Paid subscriptions are handled by the Apple App Store and renew automatically. You can cancel at any time in your Apple ID settings; paid features remain available until the end of the current period."),
        .header("4. Your account"),
        .body("You are responsible for keeping your account secure. Deleting your account permanently erases all associated data and cannot be undone."),
    ]}

    private static func french(_ sos: String) -> [Block] {[
        .title("Politique de confidentialité"),
        .updated("Dernière mise à jour : 31 octobre 2026"),
        .header("1. Ce que nous collectons"),
        .bullet("Position", "Sert aux alertes de zone sûre, à la localisation en cas de SOS et à l'historique de vos déplacements. Collectée uniquement avec votre autorisation et partagée seulement avec les proches que vous choisissez."),
        .bullet("Capteurs de mouvement", "Servent à la détection de chute. Traités uniquement sur votre appareil, jamais envoyés."),
        .bullet("Numéro de téléphone", "Sert à créer votre compte et à envoyer des SMS d'urgence."),
        .bullet("Informations sur l'appareil", "Niveau de batterie et statut en ligne, pour que vos proches sachent que le téléphone fonctionne."),
        .header("2. Comment nous les utilisons"),
        .body("Ces informations servent uniquement à :"),
        .bullet("Envoyer un SOS", "Transmettre votre position à vos proches lorsqu'un SOS est déclenché."),
        .bullet("Surveiller les problèmes", "Détecter une chute ou une perte de contact et prévenir vos proches."),
        .bullet("Signaler que tout va bien", "Permettre à vos proches de savoir que vous êtes en sécurité."),
        .header("3. Durée de conservation"),
        .body("Formule gratuite : positions conservées 7 jours, signalements 30 jours.\nFormules payantes : positions conservées 90 jours, signalements sans limite.\nLes événements SOS et les journaux de consentement sont conservés sans limite."),
        .header("4. Partage"),
        .body("Vos informations de position et de sécurité ne sont partagées qu'avec les proches que vous avez explicitement autorisés. Nous ne vendons jamais vos données personnelles. Les liens de partage d'urgence ne sont créés que par vous ou par la procédure d'escalade SOS, et expirent dans un délai de 48 heures."),
        .header("5. Lieu de stockage et transferts internationaux"),
        .body("Vos données sont stockées aux États-Unis (Google Cloud / Firebase, région us-central1). Les SMS et appels d'urgence passent par Twilio (États-Unis). Si vous résidez hors des États-Unis, l'utilisation de l'app implique le transfert et le traitement de vos informations aux États-Unis. Nos contrats avec ces prestataires les obligent à protéger vos informations au moins au niveau de la présente politique."),
        .header("6. Sécurité"),
        .body("Toutes les données sont chiffrées en transit (TLS). Les identifiants sensibles sont conservés dans le trousseau iOS. Les données serveur sont chiffrées au repos et une preuve d'intégrité quotidienne (arbre de Merkle) montre qu'elles n'ont pas été modifiées."),
        .header("7. Vos droits"),
        .bullet("Accès", "Exportez toutes vos données depuis les Réglages à tout moment."),
        .bullet("Suppression", "Supprimez votre compte dans les Réglages pour effacer définitivement vos données."),
        .bullet("Retrait du consentement", "Désactivez l'accès à la position ou aux mouvements dans les Réglages iOS à tout moment."),
        .header("8. Contact"),
        .body("Une question sur cette politique ? Écrivez à privacy@shoudeng.app"),
        .divider,
        .title("Conditions d'utilisation"),
        .updated("Dernière mise à jour : 31 octobre 2026"),
        .header("1. Le service"),
        .body("Lantern Care est une app de sécurité personnelle qui offre aux personnes protégées et à leurs proches des alertes SOS, le partage de position, la détection de chute et des fonctions associées. Elle ne remplace pas les services d'urgence comme le \(sos)."),
        .header("2. Avertissement"),
        .body("Lantern Care est un outil d'appoint et ne peut garantir que chaque alerte soit transmise. Une panne de réseau, un appareil endommagé, une batterie vide ou d'autres facteurs peuvent l'en empêcher. En cas d'urgence, appelez toujours aussi le \(sos)."),
        .header("3. Abonnements"),
        .body("Les abonnements payants sont gérés par l'App Store d'Apple et se renouvellent automatiquement. Vous pouvez résilier à tout moment dans les réglages de votre identifiant Apple ; les fonctions payantes restent disponibles jusqu'à la fin de la période en cours."),
        .header("4. Votre compte"),
        .body("Vous êtes responsable de la sécurité de votre compte. La suppression du compte efface définitivement toutes les données associées et ne peut pas être annulée."),
    ]}
}
