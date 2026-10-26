import SwiftUI

struct AQICardView: View {
    @ObservedObject private var lang = LanguageManager.shared

    let value: Int
    let label: String

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    private var color: Color {
        if value <= 50 { return safe }
        if value <= 100 { return Color(red: 232/255, green: 163/255, blue: 61/255) }
        if value <= 150 { return Color.orange }
        return Color(red: 196/255, green: 69/255, blue: 60/255)
    }

    private var markerPosition: CGFloat {
        min(1.0, CGFloat(value) / 300.0)
    }

    private var advice: String {
        if value <= 50 { return lang.localized("aqi_good_advice", fallback: "Safe for outdoor activities. No health concerns.") }
        if value <= 100 { return lang.localized("aqi_moderate_advice", fallback: "Acceptable. Sensitive groups should limit prolonged outdoor exertion.") }
        return lang.localized("aqi_unhealthy_advice", fallback: "Reduce outdoor activities. Wear a mask if necessary.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lang.localized("aqi_title", fallback: "Air Quality Index"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ink)
                Spacer()
                Text("\(value) \(label)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
            }

            // Gradient bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Gradient track
                    LinearGradient(
                        colors: [.green, .yellow, .orange, .red, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 6)
                    .cornerRadius(3)

                    // Marker
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: color.opacity(0.3), radius: 2)
                        .offset(x: geo.size.width * markerPosition - 6)
                }
            }
            .frame(height: 12)

            Text(advice)
                .font(.system(size: 10))
                .foregroundColor(ink.opacity(0.4))
        }
        .padding(12)
        .background(Color(red: 251/255, green: 248/255, blue: 241/255))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ink.opacity(0.06), lineWidth: 1)
        )
    }
}
