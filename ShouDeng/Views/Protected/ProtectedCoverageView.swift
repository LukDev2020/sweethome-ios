import SwiftUI

// MARK: - Screen A5: Coverage & Offline Pack
//
// Design from shoudeng-full-design.html:
//   - Current country detection (Ukraine · Kyiv)
//   - Local resources panel (emergency number, embassy, rescue partners)
//   - Offline pack panel (emergency numbers, SMS templates, offline map)
//   - Weak network degradation toggles

struct ProtectedCoverageView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let creamBg = Color(red: 254/255, green: 252/255, blue: 247/255)
    private let offWhiteBg = Color(red: 251/255, green: 248/255, blue: 241/255)
    private let paneBorder = Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.13)

    @State private var smsDowngrade = true
    @State private var lowPowerSaving = true

    private var countryName: String {
        let code = coordinator.currentUser?.countryCode ?? "CN"
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }

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
                sampleDataBanner
                localResourcesPanel

                // Weather
                sectionHeader(langManager.localized("coverage_weather", fallback: "Weather"))
                WeatherCardView()

                // Air Quality
                AQICardView(value: 32, label: "Good")

                // Safety Advisory
                sectionHeader(langManager.localized("coverage_advisory", fallback: "Safety Advisory"))
                safetyAdvisoryCard

                // Nearby Medical
                sectionHeader(langManager.localized("coverage_medical", fallback: "Nearby Medical"))
                NearbyMedicalView()

                // Emergency Numbers
                sectionHeader(langManager.localized("coverage_emergency", fallback: "Emergency Numbers"))
                emergencyNumbersCard

                // Local Info
                sectionHeader(langManager.localized("coverage_local_info", fallback: "Local Info"))
                localInfoGrid

                offlinePackPanel
                weakNetworkPanel
                Text(langManager.localized("protected.coverage.footer"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
    }

    private var duoPaneLayout: some View {
        HStack(spacing: 0) {
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
                    sampleDataBanner
                    localResourcesPanel
                }
                .padding(.horizontal, 16)
            }
            .frame(width: 445)
            .background(creamBg)

            Rectangle().fill(paneBorder).frame(width: 1)

            ScrollView {
                VStack(spacing: 12) {
                    offlinePackPanel
                    weakNetworkPanel
                    Text(langManager.localized("protected.coverage.footer"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .background(offWhiteBg)
        }
    }

    // MARK: - Local Resources

    private var localResourcesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(countryName)\(cityName.isEmpty ? "" : " · \(cityName)")（已自动识别）")
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            resourceRow(langManager.localized("protected.coverage.localNumber"), value: langManager.localized("protected.coverage.localNumberValue"), isOk: true)
            resourceRow(langManager.localized("protected.coverage.responseLanguage"), value: langManager.localized("protected.coverage.responseLanguageValue"), isOk: true)
            resourceRow(langManager.localized("protected.coverage.embassyLine"), value: langManager.localized("protected.coverage.embassyLineValue"), isOk: true)
            resourceRow(langManager.localized("protected.coverage.rescuePartner"), value: langManager.localized("protected.coverage.rescuePartnerValue"), isOk: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Offline Pack

    private var offlinePackPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("protected.coverage.offlinePack"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            resourceRow(langManager.localized("protected.coverage.offlineEmergency"), value: langManager.localized("protected.coverage.downloaded"), isOk: true)
            resourceRow(langManager.localized("protected.coverage.offlineSMS"), value: langManager.localized("protected.coverage.downloaded"), isOk: true)
            resourceRow(langManager.localized("protected.coverage.offlineMap") + (cityName.isEmpty ? "" : " · \(cityName)"), value: langManager.localized("protected.coverage.notDownloaded"), isOk: false)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
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

    private func resourceRow(_ label: String, value: String, isOk: Bool) -> some View {
        HStack {
            Text(label).font(.scaled(size: 13))
            Spacer()
            Text(value)
                .font(.scaled(size: 11.5))
                .foregroundStyle(isOk ? safe : alert)
        }
        .padding(.vertical, 2)
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

    private var emergencyNumbersCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(langManager.localized("coverage_local_emergency", fallback: "Local Emergency Services"))
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 6) {
                Text("Police: 911").font(.system(size: 10)).padding(.horizontal, 8).padding(.vertical, 4).background(Color(.secondarySystemBackground)).cornerRadius(6)
                Text("Fire: 911").font(.system(size: 10)).padding(.horizontal, 8).padding(.vertical, 4).background(Color(.secondarySystemBackground)).cornerRadius(6)
                Text("Ambulance: 911").font(.system(size: 10)).padding(.horizontal, 8).padding(.vertical, 4).background(Color(.secondarySystemBackground)).cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.3), lineWidth: 1))
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
