import SwiftUI

// MARK: - Consulate & Emergency Contacts View
//
// Pre-loaded embassy phone numbers, insurance claim numbers,
// emergency numbers by country. Offline-capable lookup.

struct ConsulateView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color.appInk
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var searchText = ""
    @State private var selectedCountry: ConsulateEntry?

    // Embedded consulate data — works offline
    // Source: Chinese MFA official websites (cs.mfa.gov.cn, embassy/consulate sites), re-checked 2026-10-31.
    // Same data as backend routes/consulate.ts.
    // Numbers are consular protection hotlines (领事保护电话), not general switchboards
    private let countries: [ConsulateEntry] = [
        ConsulateEntry(code: "US", flag: "🇺🇸", embassy: "+1-202-495-2216", consulates: ["+1-212-695-3125", "+1-415-929-6998", "+1-213-807-8052", "+1-312-397-3015"]),
        ConsulateEntry(code: "CA", flag: "🇨🇦", embassy: "+1-613-562-1616", consulates: ["+1-416-594-2308", "+1-604-336-9926"]),
        ConsulateEntry(code: "GB", flag: "🇬🇧", embassy: "+44-20-7299-8439", consulates: ["+44-161-224-8986", "+44-131-337-4449"]),
        ConsulateEntry(code: "AU", flag: "🇦🇺", embassy: "+61-2-6228-3948", consulates: ["+61-2-9550-5519", "+61-3-9824-8810"]),
        ConsulateEntry(code: "JP", flag: "🇯🇵", embassy: "+81-3-6450-2195", consulates: []),
        ConsulateEntry(code: "KR", flag: "🇰🇷", embassy: "+82-2-755-0572", consulates: []),
        ConsulateEntry(code: "DE", flag: "🇩🇪", embassy: "+49-30-27588-551", consulates: ["+49-69-6953-8633", "+49-89-7244-98146"]),
        ConsulateEntry(code: "FR", flag: "🇫🇷", embassy: "+33-1-5375-8921", consulates: ["+33-7-8562-0931"]),
        ConsulateEntry(code: "NZ", flag: "🇳🇿", embassy: "+64-4-499-5022", consulates: ["+64-9-525-1200"]),
        ConsulateEntry(code: "SG", flag: "🇸🇬", embassy: "+65-6475-0165", consulates: []),
        ConsulateEntry(code: "TH", flag: "🇹🇭", embassy: "+66-2-245-7010", consulates: ["+66-81-882-3283"]),
        ConsulateEntry(code: "PH", flag: "🇵🇭", embassy: "+63-2-8231-1033", consulates: []),
        ConsulateEntry(code: "MY", flag: "🇲🇾", embassy: "+60-3-2164-5301", consulates: []),
        ConsulateEntry(code: "UA", flag: "🇺🇦", embassy: "+380-50-355-0734", consulates: []),
    ]

    private var filteredCountries: [ConsulateEntry] {
        if searchText.isEmpty { return countries }
        return countries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var isPinned: Bool {
        coordinator.selectedHotline != nil
    }

    var body: some View {
        NavigationStack {
            List {
                // Currently pinned country indicator
                if let hotline = coordinator.selectedHotline,
                   let pinned = countries.first(where: { $0.code == hotline.countryCode }) {
                    Section {
                        HStack(spacing: 12) {
                            Text(pinned.flag)
                                .font(.scaled(size: 24))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pinned.name)
                                    .font(.scaled(size: 15, weight: .medium))
                                    .foregroundStyle(ink)
                                Text(langManager.localized("consulate.pinned"))
                                    .font(.scaled(size: 12))
                                    .foregroundStyle(safe)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(safe)
                        }
                    } header: {
                        Text(langManager.localized("consulate.currentPinned"))
                    }
                }

                Section {
                    ForEach(filteredCountries) { country in
                        Button { selectedCountry = country } label: {
                            HStack(spacing: 12) {
                                Text(country.flag)
                                    .font(.scaled(size: 24))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(country.name)
                                        .font(.scaled(size: 15, weight: .medium))
                                        .foregroundStyle(ink)
                                    Text(String(format: langManager.localized("consulate.emergencyPhone"), country.emergency))
                                        .font(.scaled(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if coordinator.selectedHotline?.countryCode == country.code {
                                    Image(systemName: "pin.fill")
                                        .font(.scaled(size: 11))
                                        .foregroundStyle(safe)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.scaled(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(langManager.localized("consulate.allCountries"))
                } footer: {
                    Text(LanguageManager.shared.localized("disclaimer.reference.only"))
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .searchable(text: $searchText, prompt: langManager.localized("consulate.search"))
            .navigationTitle(langManager.localized("consulate.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label(langManager.localized("consulate.close"), systemImage: "xmark") }
                }
            }
            .sheet(item: $selectedCountry) { country in
                ConsulateDetailSheet(country: country, onPin: { pinCountry(country) })
                    .environmentObject(coordinator)
            }
        }
    }

    private func pinCountry(_ country: ConsulateEntry) {
        let hotline = SelectedHotline(
            countryCode: country.code,
            countryName: country.name,
            flag: country.flag,
            emergency: country.emergency,
            embassy: country.embassy,
            selectedPhone: nil,
            selectedLabel: nil
        )
        coordinator.saveSelectedHotline(hotline)
    }
}

// MARK: - Data Model

struct ConsulateEntry: Identifiable {
    var id: String { code }
    let code: String
    let flag: String
    let embassy: String
    let consulates: [String]

    /// Emergency numbers and country name come from the single source so the
    /// pinned hotline card never shows a police-only number as "emergency".
    var name: String { RegionalEmergencyInfo.regionName(code) }
    var emergencyNumbers: [EmergencyNumber] { RegionalEmergencyInfo.forCountry(code).numbers }
    var emergency: String { RegionalEmergencyInfo.forCountry(code).primaryNumber }
}

// MARK: - Detail Sheet

struct ConsulateDetailSheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let country: ConsulateEntry
    var onPin: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color.appInk

    private var isPinned: Bool {
        coordinator.selectedHotline?.countryCode == country.code
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Country header
                    HStack {
                        Text(country.flag)
                            .font(.scaled(size: 40))
                        Text(country.name)
                            .font(.scaled(size: 24, weight: .bold))
                        Spacer()
                    }
                    .padding(.bottom, 8)

                    // Pin button
                    Button {
                        if isPinned {
                            coordinator.removeSelectedHotline()
                        } else {
                            onPin?()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                                .font(.scaled(size: 13))
                            Text(isPinned ? LanguageManager.shared.localized("consulate.unpin") : LanguageManager.shared.localized("consulate.pin"))
                                .font(.scaled(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(isPinned ? Color.secondary : safe)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Emergency numbers
                    sectionCard(title: LanguageManager.shared.localized("consulate.emergencyNumbers"), icon: "phone.fill", color: alert) {
                        ForEach(country.emergencyNumbers, id: \.number) { number in
                            phoneRow(number.label, number: number.number)
                        }
                    }

                    // Chinese Embassy — consular protection numbers
                    sectionCard(title: LanguageManager.shared.localized("consulate.embassySection"), icon: "building.columns.fill", color: safe) {
                        phoneRow(LanguageManager.shared.localized("consulate.embassy"), number: country.embassy)
                        ForEach(Array(country.consulates.enumerated()), id: \.offset) { _, number in
                            phoneRow(LanguageManager.shared.localized("consulate.consulate"), number: number)
                        }
                    }

                    // Global consular protection hotline
                    sectionCard(title: LanguageManager.shared.localized("consulate.globalHotline"), icon: "globe", color: .blue) {
                        phoneRow(LanguageManager.shared.localized("consulate.hotline12308"), number: "+86-10-12308")
                        phoneRow(LanguageManager.shared.localized("consulate.backupNumber"), number: "+86-10-59913991")
                    }

                    Text(LanguageManager.shared.localized("consulate.footer"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .navigationTitle(country.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Label(LanguageManager.shared.localized("consulate.close"), systemImage: "xmark") }
                }
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String, icon: String, color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.scaled(size: 14, weight: .semibold))
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func phoneRow(_ label: String, number: String) -> some View {
        HStack {
            Text(label)
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Link(number, destination: URL(string: "tel:\(number.replacingOccurrences(of: "-", with: ""))")!)
                .font(.scaled(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(ink)
        }
    }
}
