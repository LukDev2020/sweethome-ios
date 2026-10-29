import SwiftUI

// MARK: - Disguise Weather View
//
// A functional weather app shell that hides the real safety app.
// Triple-tap on the temperature display reveals the real app.

struct DisguiseWeatherView: View {
    @ObservedObject private var disguiseService = DisguiseModeService.shared

    @State private var temperature = Int.random(in: 15...30)
    @State private var humidity = Int.random(in: 40...80)
    @State private var windSpeed = Double.random(in: 2...15)
    @State private var tapCount = 0
    @State private var lastTapTime = Date.distantPast
    @State private var showingForecast = false

    private let conditions = ["sun.max.fill", "cloud.sun.fill", "cloud.fill", "cloud.rain.fill", "cloud.bolt.fill"]
    @State private var conditionIndex = Int.random(in: 0...4)
    @State private var hourlyOffsets: [Int] = (0..<12).map { _ in Int.random(in: -3...3) }
    @State private var uvIndex = Int.random(in: 1...8)

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 60)

                // City name
                Text(cityName)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.white)

                // Temperature — triple-tap to reveal
                Text("\(temperature)\u{00B0}")
                    .font(.system(size: 96, weight: .thin))
                    .foregroundStyle(.white)
                    .onTapGesture {
                        handleTemperatureTap()
                    }

                // Condition
                HStack(spacing: 6) {
                    Image(systemName: conditions[conditionIndex])
                        .font(.system(size: 18))
                    Text(conditionText)
                        .font(.system(size: 18))
                }
                .foregroundStyle(.white.opacity(0.8))

                // High/Low
                Text("H:\(temperature + 3)\u{00B0}  L:\(temperature - 5)\u{00B0}")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)

                Spacer().frame(height: 40)

                // Hourly forecast
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(0..<12, id: \.self) { hour in
                            VStack(spacing: 8) {
                                Text(hourLabel(hour))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                                Image(systemName: conditions[(conditionIndex + hour) % conditions.count])
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                Text("\(temperature + hourlyOffsets[hour])\u{00B0}")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Divider()
                    .background(.white.opacity(0.3))
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)

                // Weekly forecast
                VStack(spacing: 12) {
                    ForEach(0..<7, id: \.self) { day in
                        HStack {
                            Text(weekdays[day])
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 40, alignment: .leading)
                            Image(systemName: conditions[(conditionIndex + day) % conditions.count])
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .frame(width: 30)
                            Spacer()
                            Text("\(temperature - 5 + day)\u{00B0}")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: 35)
                            // Progress bar
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .yellow, .orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 100, height: 6)
                            Text("\(temperature + day)\u{00B0}")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 35)
                        }
                        .padding(.horizontal, 20)
                    }
                }

                Spacer()

                // Bottom details
                HStack(spacing: 30) {
                    VStack(spacing: 4) {
                        Text("Humidity")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(humidity)%")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    VStack(spacing: 4) {
                        Text("Wind")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(String(format: "%.0f km/h", windSpeed))
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    VStack(spacing: 4) {
                        Text("UV Index")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(uvIndex)")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - Secret Gesture

    private func handleTemperatureTap() {
        let now = Date()
        if now.timeIntervalSince(lastTapTime) > 1.0 {
            tapCount = 1
        } else {
            tapCount += 1
        }
        lastTapTime = now

        if tapCount >= 3 {
            tapCount = 0
            disguiseService.handleSecretGestureDetected()
        }
    }

    // MARK: - Helpers

    private var cityName: String {
        let cities = ["San Francisco", "New York", "London", "Tokyo", "Paris", "Beijing", "Toronto"]
        let index = Calendar.current.component(.day, from: Date()) % cities.count
        return cities[index]
    }

    private var conditionText: String {
        let texts = ["Sunny", "Partly Cloudy", "Cloudy", "Rainy", "Thunderstorm"]
        return texts[conditionIndex]
    }

    private var gradientColors: [Color] {
        switch conditionIndex {
        case 0: return [Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.4, green: 0.7, blue: 1.0)]
        case 1: return [Color(red: 0.3, green: 0.5, blue: 0.8), Color(red: 0.5, green: 0.7, blue: 0.9)]
        case 2: return [Color(red: 0.4, green: 0.45, blue: 0.5), Color(red: 0.55, green: 0.6, blue: 0.65)]
        case 3: return [Color(red: 0.3, green: 0.35, blue: 0.45), Color(red: 0.4, green: 0.5, blue: 0.6)]
        default: return [Color(red: 0.2, green: 0.2, blue: 0.35), Color(red: 0.3, green: 0.3, blue: 0.5)]
        }
    }

    private func hourLabel(_ offset: Int) -> String {
        let hour = (Calendar.current.component(.hour, from: Date()) + offset) % 24
        return offset == 0 ? "Now" : "\(hour):00"
    }
}
