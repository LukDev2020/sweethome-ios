import SwiftUI

struct WeatherCardView: View {
    @ObservedObject private var lang = LanguageManager.shared

    // Static demo data matching prototype
    private let temp = "12"
    private let desc: String = "Partly Cloudy"
    private let wind = "15 km/h NW"
    private let humidity = "65%"
    private let uv = "3 (Moderate)"
    private let forecast: [(day: String, icon: String, hi: String, lo: String)] = [
        ("Mon", "sun.max.fill", "15", "8"),
        ("Tue", "cloud.rain.fill", "11", "6"),
        ("Wed", "cloud.fill", "9", "4"),
        ("Thu", "cloud.sun.fill", "13", "7"),
        ("Fri", "sun.max.fill", "16", "9")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(temp)\u{00B0}C")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(.white)
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white, .yellow)
            }
            .padding(.bottom, 10)

            // Details
            HStack(spacing: 12) {
                detailItem(lang.localized("weather_wind", fallback: "Wind"), value: wind)
                detailItem(lang.localized("weather_humidity", fallback: "Humidity"), value: humidity)
                detailItem("UV", value: uv)
            }
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.7))
            .padding(.bottom, 10)

            // Forecast
            Divider().background(Color.white.opacity(0.15))
                .padding(.bottom, 8)

            HStack(spacing: 0) {
                ForEach(forecast, id: \.day) { item in
                    VStack(spacing: 3) {
                        Text(item.day)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        Image(systemName: item.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                        Text("\(item.hi)\u{00B0}")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                        Text("\(item.lo)\u{00B0}")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(red: 74/255, green: 144/255, blue: 217/255), Color(red: 54/255, green: 114/255, blue: 181/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }

    private func detailItem(_ label: String, value: String) -> some View {
        Text("\(label): \(value)")
    }
}
