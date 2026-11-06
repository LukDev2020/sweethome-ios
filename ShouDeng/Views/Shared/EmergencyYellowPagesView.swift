import SwiftUI

struct EmergencyYellowPagesView: View {
    @ObservedObject private var lang = LanguageManager.shared
    @State private var selectedCountry: String

    /// - Parameter country: where the numbers should start (the person's emergency
    ///   country); the phone's region was used before, so Mom in Chengdu saw Canada.
    init(country: String? = nil) {
        let fallback = Locale.current.region?.identifier ?? "CA"
        let code = (country?.isEmpty == false ? country! : fallback).uppercased()
        _selectedCountry = State(initialValue: RegionalEmergencyInfo.supportedRegions.contains(code) ? code : fallback)
    }

    private let ink = Color.appInk
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let cobalt = Color(red: 27/255, green: 94/255, blue: 189/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let offWhiteBg = Color.paper(251, 248, 241, elevated: true)

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

    /// National lines beyond the emergency numbers. Embassies and consulates are in the
    /// app's consulate page (verified data), not repeated here.
    private var extras: [YPEntry] {
        func row(_ icon: String, _ color: Color, _ key: String, _ number: String) -> YPEntry {
            YPEntry(icon: icon, iconColor: color, title: lang.localized("yp.\(key)"), subtitle: "", number: number)
        }
        switch selectedCountry {
        case "CA", "US": return [row("heart.fill", pro, "crisisLine", "988")]
        case "CN": return [row("globe", cobalt, "consularHotline", "12308"),
                           row("heart.fill", pro, "crisisLine", "010-82951332")]
        case "JP": return [row("globe", lamp, "touristHelpline", "050-3816-2787")]
        case "AU": return [row("cross.vial.fill", safe, "poisons", "13 11 26")]
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
