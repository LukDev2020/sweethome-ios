import SwiftUI

struct NearbyMedicalView: View {
    @ObservedObject private var lang = LanguageManager.shared

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let offWhiteBg = Color(red: 251/255, green: 248/255, blue: 241/255)

    struct MedicalPlace: Identifiable {
        let id = UUID()
        let icon: String
        let iconColor: Color
        let name: String
        let detail: String
        let tag: String
        let tagColor: Color
        let isOpen: Bool
    }

    let places: [MedicalPlace]

    init() {
        self.places = [
            MedicalPlace(icon: "cross.case.fill", iconColor: Color(red: 196/255, green: 69/255, blue: 60/255),
                         name: "Toronto General Hospital",
                         detail: "200 Elizabeth St \u{00B7} 1.2 km \u{00B7} 24/7 ER",
                         tag: "Open Now", tagColor: Color(red: 63/255, green: 143/255, blue: 110/255), isOpen: true),
            MedicalPlace(icon: "stethoscope", iconColor: Color(red: 27/255, green: 94/255, blue: 189/255),
                         name: "U of T Health & Wellness",
                         detail: "214 College St \u{00B7} 0.4 km \u{00B7} Walk-in clinic",
                         tag: "Open until 5 PM", tagColor: Color(red: 63/255, green: 143/255, blue: 110/255), isOpen: true),
            MedicalPlace(icon: "pills.fill", iconColor: Color(red: 107/255, green: 92/255, blue: 165/255),
                         name: "Shoppers Drug Mart Pharmacy",
                         detail: "326 Bloor St W \u{00B7} 0.8 km \u{00B7} 24h pharmacy",
                         tag: "24 Hours", tagColor: Color(red: 107/255, green: 92/255, blue: 165/255), isOpen: true)
        ]
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(places) { place in
                medicalCard(place)
            }
        }
    }

    private func medicalCard(_ place: MedicalPlace) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            RoundedRectangle(cornerRadius: 10)
                .fill(place.iconColor.opacity(0.1))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: place.icon)
                        .font(.system(size: 16))
                        .foregroundColor(place.iconColor)
                )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ink)
                Text(place.detail)
                    .font(.system(size: 10))
                    .foregroundColor(ink.opacity(0.55))

                Text(place.tag)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(place.tagColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(place.tagColor.opacity(0.12))
                    .cornerRadius(4)
                    .padding(.top, 2)
            }

            Spacer()
        }
        .padding(12)
        .background(offWhiteBg)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ink.opacity(0.06), lineWidth: 1)
        )
    }
}
