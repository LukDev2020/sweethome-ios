import SwiftUI

// MARK: - Emergency Text Card View
//
// Multi-language emergency card: generates help message in local language.
// Large text display for showing to bystanders/first responders.
// Works offline with embedded translations.

struct EmergencyTextCardView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    @State private var selectedLang = "en"
    @State private var customMessage = ""
    @State private var showFullScreen = false

    // Embedded translations — works offline
    private let phrases: [(code: String, language: String, flag: String, helpText: String, emergencyNumber: String)] = [
        ("en", "English", "🇺🇸", "I need help. Please call emergency services.", "911"),
        ("zh", "中文", "🇨🇳", "我需要帮助，请拨打急救电话。", "120"),
        ("ja", "日本語", "🇯🇵", "助けてください。救急車を呼んでください。", "119"),
        ("ko", "한국어", "🇰🇷", "도움이 필요합니다. 응급 서비스에 전화해 주세요.", "119"),
        ("fr", "Français", "🇫🇷", "J'ai besoin d'aide. Appelez les secours s'il vous plaît.", "15"),
        ("de", "Deutsch", "🇩🇪", "Ich brauche Hilfe. Bitte rufen Sie den Notdienst.", "112"),
        ("es", "Español", "🇪🇸", "Necesito ayuda. Por favor llame a emergencias.", "112"),
        ("pt", "Português", "🇧🇷", "Preciso de ajuda. Por favor, ligue para a emergência.", "112"),
        ("it", "Italiano", "🇮🇹", "Ho bisogno di aiuto. Per favore chiamate il pronto soccorso.", "118"),
        ("ru", "Русский", "🇷🇺", "Мне нужна помощь. Пожалуйста, вызовите скорую помощь.", "103"),
        ("ar", "العربية", "🇸🇦", "أحتاج مساعدة. من فضلك اتصل بالطوارئ.", "911"),
        ("th", "ไทย", "🇹🇭", "ฉันต้องการความช่วยเหลือ กรุณาโทรเรียกรถพยาบาล", "1669"),
        ("vi", "Tiếng Việt", "🇻🇳", "Tôi cần giúp đỡ. Xin hãy gọi cấp cứu.", "115"),
        ("uk", "Українська", "🇺🇦", "Мені потрібна допомога. Будь ласка, викличте швидку.", "103"),
        ("tr", "Türkçe", "🇹🇷", "Yardıma ihtiyacım var. Lütfen acil servisi arayın.", "112"),
        ("hi", "हिन्दी", "🇮🇳", "मुझे मदद चाहिए। कृपया आपातकालीन सेवाओं को बुलाएं।", "112"),
        ("ms", "Bahasa Melayu", "🇲🇾", "Saya perlukan bantuan. Sila hubungi perkhidmatan kecemasan.", "999"),
        ("pl", "Polski", "🇵🇱", "Potrzebuję pomocy. Proszę zadzwonić po pogotowie.", "112"),
        ("nl", "Nederlands", "🇳🇱", "Ik heb hulp nodig. Bel alstublieft de hulpdiensten.", "112"),
        ("sv", "Svenska", "🇸🇪", "Jag behöver hjälp. Ring ambulansen tack.", "112"),
    ]

    private var currentPhrase: (code: String, language: String, flag: String, helpText: String, emergencyNumber: String) {
        phrases.first { $0.code == selectedLang } ?? phrases[0]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Language picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(phrases, id: \.code) { phrase in
                                Button {
                                    selectedLang = phrase.code
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(phrase.flag)
                                        Text(phrase.language)
                                            .font(.system(size: 12))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        selectedLang == phrase.code
                                            ? alert.opacity(0.15)
                                            : Color(.systemGray6)
                                    )
                                    .foregroundStyle(selectedLang == phrase.code ? alert : ink)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Main card
                    VStack(spacing: 16) {
                        Image(systemName: "staroflife.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(alert)

                        Text(currentPhrase.helpText)
                            .font(.system(size: 28, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(ink)

                        // Medical info from card
                        if let card = loadLocalMedicalInfo() {
                            if let blood = card.bloodType {
                                infoRow("Blood / 血型", value: blood)
                            }
                            if !card.allergies.isEmpty {
                                infoRow("Allergies / 过敏", value: card.allergies.joined(separator: ", "))
                            }
                        }

                        Divider()

                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .foregroundStyle(alert)
                            Text(currentPhrase.emergencyNumber)
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .foregroundStyle(alert)
                        }

                        Text("Emergency Number")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 10)
                    )
                    .padding(.horizontal, 16)

                    // Full screen button
                    Button { showFullScreen = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                            Text("全屏显示")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(alert)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(alert.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 16)

                    Text("语言不通时，将屏幕展示给身边的人。\n急救卡信息离线可用，不需要网络。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 24)
                }
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("多语言急救卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showFullScreen) {
                fullScreenCard
            }
        }
    }

    // MARK: - Full Screen Card

    private var fullScreenCard: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "staroflife.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(alert)

                Text(currentPhrase.helpText)
                    .font(.system(size: 36, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(alert)
                        .font(.system(size: 28))
                    Text(currentPhrase.emergencyNumber)
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .foregroundStyle(alert)
                }

                Spacer()

                Button { showFullScreen = false } label: {
                    Text("关闭")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ink)
        }
        .padding(.horizontal, 8)
    }

    private func loadLocalMedicalInfo() -> MedicalCardData? {
        // Load from UserDefaults for offline access
        guard let data = UserDefaults.standard.data(forKey: "medical_card_cache"),
              let card = try? JSONDecoder().decode(MedicalCardData.self, from: data) else {
            return nil
        }
        return card
    }
}
