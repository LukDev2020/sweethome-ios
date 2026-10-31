import SwiftUI

struct EmergencyYellowPagesView: View {
    @ObservedObject private var lang = LanguageManager.shared
    @State private var selectedCountry: String = {
        let region = Locale.current.region?.identifier ?? "CA"
        return RegionalEmergencyInfo.supportedRegions.contains(region) ? region : "CA"
    }()

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let cobalt = Color(red: 27/255, green: 94/255, blue: 189/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let offWhiteBg = Color(red: 251/255, green: 248/255, blue: 241/255)

    struct YPEntry: Identifiable {
        let id = UUID()
        let icon: String
        let iconColor: Color
        let title: String
        let subtitle: String
        let number: String
    }

    /// App Store markets first, then places family members often are.
    private var countries: [(code: String, flag: String, name: String)] {
        RegionalEmergencyInfo.supportedRegions.filter { $0 != "UA" && $0 != "KR" }.map { code in
            (code, Self.flag(code), RegionalEmergencyInfo.regionName(code))
        }
    }

    private static func flag(_ code: String) -> String {
        code.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }

    /// Emergency numbers come from the single table in RegionalEmergencyInfo (the
    /// same numbers the SOS screens use); extra directory rows follow.
    private var entries: [YPEntry] {
        let emergency = RegionalEmergencyInfo.forCountry(selectedCountry).numbers.map {
            YPEntry(icon: $0.icon, iconColor: $0.color == .red ? alert : cobalt, title: $0.label, subtitle: "", number: $0.number)
        }
        return emergency + extras
    }

    private var extras: [YPEntry] {
        switch selectedCountry {
        case "CA": return [
            YPEntry(icon: "building.columns.fill", iconColor: cobalt, title: "Chinese Consulate \u{2014} Toronto", subtitle: "240 St George St", number: "+1-416-964-7260"),
            YPEntry(icon: "heart.fill", iconColor: pro, title: "Crisis Helpline", subtitle: "Mental health support", number: "988"),
            YPEntry(icon: "phone.fill", iconColor: lamp, title: "Non-Emergency Police", subtitle: "Toronto Police", number: "+1-416-808-2222")
        ]
        case "CN": return [
            YPEntry(icon: "globe", iconColor: cobalt, title: "MFA Consular Protection", subtitle: "Overseas citizens 24h", number: "12308"),
            YPEntry(icon: "heart.fill", iconColor: pro, title: "Mental Health Hotline", subtitle: "Beijing Psychological Crisis", number: "010-82951332")
        ]
        case "JP": return [
            YPEntry(icon: "building.columns.fill", iconColor: cobalt, title: "Chinese Embassy \u{2014} Tokyo", subtitle: "3-4-33 Moto-Azabu, Minato", number: "+81-3-3403-3388"),
            YPEntry(icon: "globe", iconColor: lamp, title: "JNTO Tourist Helpline", subtitle: "English support 24h", number: "050-3816-2787")
        ]
        case "US": return [
            YPEntry(icon: "building.columns.fill", iconColor: cobalt, title: "Chinese Embassy \u{2014} D.C.", subtitle: "3505 International Pl NW", number: "+1-202-495-2266"),
            YPEntry(icon: "heart.fill", iconColor: pro, title: "Suicide & Crisis Lifeline", subtitle: "24/7 support", number: "988")
        ]
        case "GB": return [
            YPEntry(icon: "building.columns.fill", iconColor: cobalt, title: "Chinese Embassy \u{2014} London", subtitle: "49 Portland Pl", number: "+44-20-7299-4049")
        ]
        case "AU": return [
            YPEntry(icon: "building.columns.fill", iconColor: cobalt, title: "Chinese Embassy \u{2014} Canberra", subtitle: "15 Coronation Dr, Yarralumla", number: "+61-2-6228-3999"),
            YPEntry(icon: "cross.vial.fill", iconColor: safe, title: "Poisons Information", subtitle: "24h hotline", number: "13 11 26")
        ]
        case "FR": return [
            YPEntry(icon: "building.columns.fill", iconColor: cobalt, title: "Chinese Embassy \u{2014} Paris", subtitle: "11 Avenue George V", number: "+33-1-4952-1950")
        ]
        case "DE": return [
            YPEntry(icon: "building.columns.fill", iconColor: cobalt, title: "Chinese Embassy \u{2014} Berlin", subtitle: "Markisches Ufer 54", number: "+49-30-27588-0")
        ]
        default: return []
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Country selector
            HStack {
                Text(lang.localized("yp_region", fallback: "Region:"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ink.opacity(0.55))
                Picker("", selection: $selectedCountry) {
                    ForEach(countries, id: \.code) { c in
                        Text("\(c.flag) \(c.name)").tag(c.code)
                    }
                }
                .pickerStyle(.menu)
                .tint(ink)
            }

            // Directory card
            let country = countries.first(where: { $0.code == selectedCountry })
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: lang.localized("yp.directory.title"), "\(country?.flag ?? "") \(country?.name ?? "")"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(ink)
                    .padding(.bottom, 8)

                ForEach(entries) { entry in
                    entryRow(entry)
                    if entry.id != entries.last?.id {
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .padding(14)
            .background(offWhiteBg)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(ink.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func entryRow(_ entry: YPEntry) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7)
                .fill(entry.iconColor)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: entry.icon)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ink)
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(ink.opacity(0.55))
                }
            }

            Spacer()

            Button {
                callNumber(entry.number)
            } label: {
                Text(entry.number)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(cobalt)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(cobalt.opacity(0.08))
                    .cornerRadius(6)
            }
        }
        .padding(.vertical, 8)
    }

    private func callNumber(_ number: String) {
        let cleaned = number.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if let url = URL(string: "tel://\(cleaned)") {
            ExternalURL.open(url)
        }
    }
}
