import SwiftUI

// MARK: - Screen A5: Coverage
//
// Design from shoudeng-full-design.html:
//   - Current country detection (Ukraine · Kyiv)
//   - Local resources panel (emergency number, embassy, rescue partners)
//   - Weak network degradation toggles

struct ProtectedCoverageView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let creamBg = Color.paper(254, 252, 247)
    private let offWhiteBg = Color.paper(251, 248, 241, elevated: true)
    private let paneBorder = Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.13)

    @ObservedObject private var explore = ExploreModeController.shared
    /// Explore Mode: the explanation before the weather may use the real location
    @State private var locationPrompt: DemoLocationPrompt?
    @State private var smsDowngrade = true
    @State private var lowPowerSaving = true

    /// Real per-country numbers (the same table the SOS screens use)
    private var emergencyInfo: RegionalEmergencyInfo {
        RegionalEmergencyInfo.forCountry(coordinator.emergencyCountryCode)
    }

    private var countryName: String { emergencyInfo.regionName }

    /// Weather, air quality, the safety advisory, the hospital list and local info were
    /// fixed sample content (Toronto hospitals for someone in Chengdu, English weather).
    /// Not shown anywhere until they come from real data; "find hospitals" opens Maps.
    private var showsSampleCards: Bool { false }

    private var cityName: String {
        coordinator.currentUser?.cityName ?? ""
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                duoPaneLayout
            } else {
                compactLayout
            }
        }
        .navigationTitle(langManager.localized("protected.coverage.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Explore Mode weather ("Use my location")

    private var usesRealLocationInDemo: Bool {
        coordinator.isDemo && (explore.weatherLocation != nil || explore.realLocation != nil)
    }

    private var demoWeatherKey: String {
        guard coordinator.isDemo else { return "real" }
        let fix = explore.weatherLocation ?? explore.realLocation
        return fix.map { String(format: "%.3f,%.3f", $0.coordinate.latitude, $0.coordinate.longitude) } ?? "sample"
    }

    private var demoWeatherAction: WeatherCardView.CornerAction? {
        guard coordinator.isDemo, explore.isActive, explore.realLocation == nil else { return nil }
        if explore.weatherLocation != nil {
            let city = DemoText(language: langManager.current).chengdu
            return .init(title: String(format: langManager.localized("explore.weather.backTo"), city),
                         systemImage: "arrow.uturn.backward") { explore.stopWeatherLocation() }
        }
        return .init(title: langManager.localized("explore.weather.useMine"), systemImage: "location") {
            locationPrompt = .weather
        }
    }

    private var sampleDataBanner: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle.fill")
                .font(.caption2)
            Text(langManager.localized("protected.coverage.sampleData"))
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(langManager.localized("protected.coverage.title"))
                        .font(.scaled(size: 20, weight: .bold))
                    Text(langManager.localized("protected.coverage.subtitle"))
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                if showsSampleCards { sampleDataBanner }
                localResourcesPanel

                medicalAndWeatherSection

                if showsSampleCards {
                    AQICardView(value: 32, label: "Good")
                    sectionHeader(langManager.localized("coverage_advisory", fallback: "Safety Advisory"))
                    safetyAdvisoryCard
                    sectionHeader(langManager.localized("coverage_local_info", fallback: "Local Info"))
                    localInfoGrid
                }

                if showsSampleCards {
                    weakNetworkPanel
                    sampleDataFooter
                }
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
    }

    private var duoPaneLayout: some View {
        FoldSplitView(dividerColor: paneBorder) {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text(langManager.localized("protected.coverage.title"))
                            .font(.scaled(size: 20, weight: .bold))
                        Text(langManager.localized("protected.coverage.subtitle"))
                            .font(.scaled(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    if showsSampleCards { sampleDataBanner }
                    localResourcesPanel
                }
                .padding(.horizontal, 16)
            }
            .background(creamBg)
        } trailing: {
            ScrollView {
                VStack(spacing: 12) {
                    medicalAndWeatherSection
                    if showsSampleCards {
                        weakNetworkPanel
                        sampleDataFooter
                    }
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(offWhiteBg)
        }
    }

    // MARK: - Local Resources

    private var localResourcesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: langManager.localized("protected.coverage.detected"),
                        countryName + (cityName.isEmpty ? "" : " · \(cityName)")))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            Text(langManager.localized("protected.coverage.localNumber"))
                .font(.scaled(size: 13, weight: .semibold))
            // This country's real numbers; tap to call
            ForEach(emergencyInfo.numbers, id: \.number) { item in
                Button {
                    let digits = item.number.filter { $0.isNumber }
                    if let url = URL(string: "tel:\(digits)") { ExternalURL.open(url) }
                } label: {
                    HStack {
                        Image(systemName: item.icon)
                            .font(.scaled(size: 13))
                            .foregroundStyle(item.color)
                            .frame(width: 22)
                        Text(item.label).font(.scaled(size: 13))
                        Spacer()
                        Text(item.number)
                            .font(.scaled(size: 15, weight: .semibold).monospacedDigit())
                            .foregroundStyle(safe)
                        Image(systemName: "phone.fill")
                            .font(.scaled(size: 11))
                            .foregroundStyle(safe)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.label) \(item.number)")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    /// Opens Apple Maps searching for hospitals near the person (real results, any country)
    private var findHospitalsButton: some View {
        Button {
            let query = langManager.localized("coverage.findHospitals.query")
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "hospital"
            if let url = URL(string: "maps://?q=\(query)") { ExternalURL.open(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(alert)
                Text(langManager.localized("coverage.findHospitals"))
                    .font(.scaled(size: 14, weight: .medium))
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nearby Medical & Weather

    @ViewBuilder
    private var medicalAndWeatherSection: some View {
        // Nearby Medical: a real Maps search; the sample list only in the demo
        sectionHeader(langManager.localized("coverage_medical", fallback: "Nearby Medical"))
        findHospitalsButton

        // Live weather where the person is (Apple WeatherKit)
        sectionHeader(langManager.localized("coverage_weather", fallback: "Weather"))
        WeatherCardView(locate: { [coordinator, explore] in
                            (coordinator.isDemo ? explore.weatherLocation : nil)
                                ?? coordinator.locationManager.bestAvailableLocation
                        },
                        placeName: usesRealLocationInDemo ? "" : (cityName.isEmpty ? countryName : cityName),
                        cornerAction: demoWeatherAction)
            // A new place (the person's own, or back to the sample city) reloads the card
            .id(demoWeatherKey)
            .onAppear { coordinator.locationManager.requestSingleLocation() }
            .demoLocationConsent($locationPrompt)
    }

    /// Only with the sample cards: says the content above is sample data
    private var sampleDataFooter: some View {
        Text(langManager.localized("protected.coverage.footer"))
            .font(.scaled(size: 12))
            .foregroundStyle(.secondary.opacity(0.7))
            .padding(.top, 8)
    }

    // MARK: - Weak Network

    private var weakNetworkPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("protected.coverage.weakNetwork"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            toggleRow(langManager.localized("protected.coverage.smsFallback"), isOn: $smsDowngrade)
            toggleRow(langManager.localized("protected.coverage.lowPowerSaving"), isOn: $lowPowerSaving)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.scaled(size: 13))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(safe)
        }
        .padding(.vertical, 2)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundColor(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.55))
            Rectangle().fill(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.06)).frame(height: 1)
        }
        .padding(.top, 12)
    }

    private var safetyAdvisoryCard: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(safe)
                .frame(width: 36, height: 36)
                .overlay(
                    Text("1").font(.system(size: 16, weight: .heavy)).foregroundColor(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Level 1 \u{2014} Exercise Normal Precautions")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(countryName) is generally safe. Standard safety measures apply.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(safe.opacity(0.06))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(safe.opacity(0.2), lineWidth: 1))
    }

    private var localInfoGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            localInfoCard(icon: "dollarsign.circle", label: "Currency", value: "CAD $")
            localInfoCard(icon: "globe", label: "Language", value: "EN / FR")
            localInfoCard(icon: "powerplug", label: "Power", value: "120V / Type A")
            localInfoCard(icon: "phone", label: "Country Code", value: "+1")
        }
    }

    private func localInfoCard(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.secondary)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold))
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.3), lineWidth: 1))
    }
}
