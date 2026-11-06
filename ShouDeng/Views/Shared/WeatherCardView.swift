import SwiftUI
import CoreLocation
import WeatherKit

// MARK: - Weather (Apple WeatherKit)
//
// Live weather where the person is: now, wind / humidity / UV, and five days. Text
// follows the app's language (not the phone's) and units follow that language's
// region conventions. Apple's attribution (logo + legal link) is required wherever
// WeatherKit data is shown. Results are cached for 30 minutes per ~1 km.
// Air quality is not in WeatherKit, so there is no AQI here.

@MainActor
final class LiveWeatherStore: ObservableObject {
    /// `unavailable` keeps Apple's error text (shown on BETA builds to diagnose setup)
    enum State { case idle, loading, loaded(Weather), unavailable(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var attribution: WeatherAttribution?
    /// City / district of the location the weather is for ("锦江区", "Toronto")
    @Published private(set) var place: String?

    private static var cache: [String: (weather: Weather, at: Date)] = [:]
    private struct TimedOut: Error {}

    /// `locate` is asked again while there is no fix yet (first launch, permission
    /// just granted): the card used to give up, or wait forever, without one.
    func load(locate: () -> CLLocation?, language: String) async {
        var location = locate()
        if location == nil {
            state = .loading
            for _ in 0..<15 where location == nil {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                location = locate()
            }
        }
        guard let location else { state = .unavailable("no location"); return }

        async let placeName = Self.placeName(for: location, language: language)
        let key = String(format: "%.2f,%.2f", location.coordinate.latitude, location.coordinate.longitude)
        if let hit = Self.cache[key], Date().timeIntervalSince(hit.at) < 30 * 60 {
            state = .loaded(hit.weather)
        } else {
            if case .loaded = state {} else { state = .loading }
            // Two tries, 10 s each: right after launch (or just after WeatherKit is
            // switched on for the app) the token request can fail — or never answer,
            // which left the card on "loading" for good.
            var lastError: Error?
            for attempt in 0..<2 {
                do {
                    let weather = try await Self.fetch(location)
                    Self.cache[key] = (weather, Date())
                    state = .loaded(weather)
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    if Task.isCancelled { return }
                    if attempt == 0 { try? await Task.sleep(for: .seconds(2)) }
                }
            }
            if let lastError {
                #if DEBUG
                print("[Weather] unavailable: \(lastError)")
                #endif
                if lastError is TimedOut {
                    state = .unavailable("timeout")
                } else {
                    // e.g. "WDSJWTAuthenticatorServiceListener.Errors 2" = WeatherKit sign-in refused
                    let ns = lastError as NSError
                    let domain = ns.domain.split(separator: ".").suffix(2).joined(separator: ".")
                    state = .unavailable("\(domain) \(ns.code)")
                }
            }
        }
        place = await placeName
        if attribution == nil { attribution = try? await WeatherService.shared.attribution }
    }

    private static func fetch(_ location: CLLocation) async throws -> Weather {
        try await withThrowingTaskGroup(of: Weather.self) { group in
            group.addTask { try await WeatherService.shared.weather(for: location) }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }

    /// District or city in the app's language, nil if the lookup fails
    private static func placeName(for location: CLLocation, language: String) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: language))
        guard let mark = marks?.first else { return nil }
        return mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea
    }
}

struct WeatherCardView: View {
    /// Asked on load and again while there is no fix yet
    let locate: () -> CLLocation?
    /// Fallback place name ("成都") when the location can't be looked up
    var placeName: String = ""
    /// Rounded location when the card appeared; a move of ~1 km reloads
    @State private var locationKey = "none"
    @ObservedObject private var lang = LanguageManager.shared
    @StateObject private var store = LiveWeatherStore()

    private var locale: Locale { Locale(identifier: lang.current.rawValue) }

    var body: some View {
        Group {
            switch store.state {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text(lang.localized("weather.loading"))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, minHeight: 90)
            case .unavailable(let reason):
                VStack(spacing: 8) {
                    if !shownPlace.isEmpty {
                        Label(shownPlace, systemImage: "location.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(lang.localized("weather.unavailable"))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.9))
                    if reason == "no location" {
                        Text(lang.localized("weather.noLocation"))
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        Task { await store.load(locate: locate, language: lang.current.rawValue) }
                    } label: {
                        Label(lang.localized("weather.retry"), systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    #if BETA || DEBUG
                    // Tester builds: Apple's error, to tell setup problems from outages
                    Text(reason).font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                    #endif
                }
                .frame(maxWidth: .infinity, minHeight: 70)
            case .loaded(let weather):
                content(weather)
            }
        }
        .padding(14)
        .background(
            LinearGradient(colors: [Color(red: 0.29, green: 0.56, blue: 0.85), Color(red: 0.21, green: 0.42, blue: 0.72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottomTrailing) { attributionMark }
        .task(id: locationKey) {
            await store.load(locate: locate, language: lang.current.rawValue)
        }
        .onAppear { locationKey = Self.key(locate()) }
    }

    private static func key(_ location: CLLocation?) -> String {
        guard let c = location?.coordinate else { return "none" }
        return String(format: "%.2f,%.2f", c.latitude, c.longitude)
    }

    private var shownPlace: String { store.place ?? placeName }

    // MARK: Loaded

    @ViewBuilder
    private func content(_ weather: Weather) -> some View {
        let now = weather.currentWeather
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if !shownPlace.isEmpty {
                        Label(shownPlace, systemImage: "location.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Text(temperature(now.temperature))
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(.white)
                    Text(lang.localized("weather.condition.\(Self.group(now.condition))"))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: now.symbolName + ".fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 10)

            HStack(spacing: 12) {
                detail(lang.localized("weather.wind"),
                       now.wind.speed.formatted(.measurement(width: .abbreviated, usage: .general).locale(locale)))
                detail(lang.localized("weather.humidity"),
                       now.humidity.formatted(.percent.precision(.fractionLength(0)).locale(locale)))
                detail("UV", "\(now.uvIndex.value)")
            }
            .padding(.bottom, 10)

            Divider().background(Color.white.opacity(0.15)).padding(.bottom, 8)

            HStack(spacing: 0) {
                ForEach(Array(weather.dailyForecast.forecast.prefix(5)), id: \.date) { day in
                    VStack(spacing: 3) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.75))
                        Image(systemName: day.symbolName + ".fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 16))
                            .frame(height: 20)
                        Text(temperature(day.highTemperature, unit: false))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                        Text(temperature(day.lowTemperature, unit: false))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 16) // room for the attribution mark
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        Text("\(label): \(value)")
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.8))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// "12°C" / "54°F" by the app language's region; forecast cells drop the unit.
    private func temperature(_ value: Measurement<UnitTemperature>, unit: Bool = true) -> String {
        let style = Measurement<UnitTemperature>.FormatStyle(width: unit ? .abbreviated : .narrow, locale: locale,
                                                             usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
        return value.formatted(style)
    }

    // MARK: Attribution (required by Apple)

    @ViewBuilder
    private var attributionMark: some View {
        if case .loaded = store.state, let attribution = store.attribution {
            Link(destination: attribution.legalPageURL) {
                AsyncImage(url: attribution.combinedMarkDarkURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(attribution.serviceName).font(.system(size: 9)).foregroundColor(.white.opacity(0.7))
                }
                .frame(height: 11)
            }
            .padding(8)
            .accessibilityLabel(attribution.serviceName)
        }
    }

    // MARK: Condition → short text in the app's language

    static func group(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear: return "clear"
        case .partlyCloudy: return "partlyCloudy"
        case .mostlyCloudy, .cloudy: return "cloudy"
        case .foggy, .haze, .smoky, .blowingDust: return "fog"
        case .breezy, .windy: return "wind"
        case .drizzle, .rain, .sunShowers: return "rain"
        case .heavyRain: return "heavyRain"
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms: return "storm"
        case .flurries, .snow, .sunFlurries, .blowingSnow: return "snow"
        case .heavySnow, .blizzard: return "heavySnow"
        case .sleet, .freezingDrizzle, .freezingRain, .hail, .wintryMix: return "sleet"
        case .hot: return "hot"
        case .frigid: return "cold"
        case .hurricane, .tropicalStorm: return "hurricane"
        @unknown default: return "unknown"
        }
    }
}
