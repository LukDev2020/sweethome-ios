import SwiftUI

// MARK: - Consulate & Emergency Contacts View
//
// Pre-loaded embassy phone numbers, insurance claim numbers,
// emergency numbers by country. Offline-capable lookup.

struct ConsulateView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var searchText = ""
    @State private var selectedCountry: ConsulateEntry?

    // Embedded consulate data — works offline
    // Source: Chinese MFA official websites (cs.mfa.gov.cn, embassy/consulate sites)
    // Numbers are consular protection hotlines (领事保护电话), not general switchboards
    private let countries: [ConsulateEntry] = [
        ConsulateEntry(code: "US", name: "美国", flag: "🇺🇸", emergency: "911", police: "911", ambulance: "911", embassy: "+1-202-495-2216", consulates: ["+1-212-695-3125", "+1-415-929-6998", "+1-213-807-8052", "+1-312-397-3015"]),
        ConsulateEntry(code: "CA", name: "加拿大", flag: "🇨🇦", emergency: "911", police: "911", ambulance: "911", embassy: "+1-613-562-1616", consulates: ["+1-416-594-2308", "+1-604-336-9926"]),
        ConsulateEntry(code: "GB", name: "英国", flag: "🇬🇧", emergency: "999", police: "999", ambulance: "999", embassy: "+44-20-7299-8439", consulates: ["+44-161-224-8986", "+44-131-337-4449"]),
        ConsulateEntry(code: "AU", name: "澳大利亚", flag: "🇦🇺", emergency: "000", police: "000", ambulance: "000", embassy: "+61-2-6228-3948", consulates: ["+61-2-8595-8029", "+61-3-9804-3271"]),
        ConsulateEntry(code: "JP", name: "日本", flag: "🇯🇵", emergency: "110", police: "110", ambulance: "119", embassy: "+81-3-3403-3065", consulates: []),
        ConsulateEntry(code: "KR", name: "韩国", flag: "🇰🇷", emergency: "112", police: "112", ambulance: "119", embassy: "+82-2-755-0572", consulates: []),
        ConsulateEntry(code: "DE", name: "德国", flag: "🇩🇪", emergency: "112", police: "110", ambulance: "112", embassy: "+49-30-27588-551", consulates: ["+49-69-6953-8633", "+49-89-7244-98146"]),
        ConsulateEntry(code: "FR", name: "法国", flag: "🇫🇷", emergency: "112", police: "17", ambulance: "15", embassy: "+33-1-5375-8921", consulates: ["+33-7-8562-0931"]),
        ConsulateEntry(code: "NZ", name: "新西兰", flag: "🇳🇿", emergency: "111", police: "111", ambulance: "111", embassy: "+64-4-499-5022", consulates: ["+64-9-525-1200"]),
        ConsulateEntry(code: "SG", name: "新加坡", flag: "🇸🇬", emergency: "999", police: "999", ambulance: "995", embassy: "+65-6471-2117", consulates: []),
        ConsulateEntry(code: "TH", name: "泰国", flag: "🇹🇭", emergency: "191", police: "191", ambulance: "1669", embassy: "+66-2-245-7010", consulates: ["+66-53-280618"]),
        ConsulateEntry(code: "MY", name: "马来西亚", flag: "🇲🇾", emergency: "999", police: "999", ambulance: "999", embassy: "+60-3-2164-5301", consulates: []),
        ConsulateEntry(code: "UA", name: "乌克兰", flag: "🇺🇦", emergency: "112", police: "102", ambulance: "103", embassy: "+380-50-355-0734", consulates: []),
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
                                .font(.system(size: 24))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pinned.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(ink)
                                Text("已设为常用")
                                    .font(.system(size: 12))
                                    .foregroundStyle(safe)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(safe)
                        }
                    } header: {
                        Text("当前常用")
                    }
                }

                Section {
                    ForEach(filteredCountries) { country in
                        Button { selectedCountry = country } label: {
                            HStack(spacing: 12) {
                                Text(country.flag)
                                    .font(.system(size: 24))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(country.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(ink)
                                    Text("紧急电话: \(country.emergency)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if coordinator.selectedHotline?.countryCode == country.code {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(safe)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("所有国家")
                }
            }
            .searchable(text: $searchText, prompt: "搜索国家")
            .navigationTitle("领事与紧急电话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
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
    let name: String
    let flag: String
    let emergency: String
    let police: String
    let ambulance: String
    let embassy: String
    let consulates: [String]
}

// MARK: - Detail Sheet

struct ConsulateDetailSheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let country: ConsulateEntry
    var onPin: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

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
                            .font(.system(size: 40))
                        Text(country.name)
                            .font(.system(size: 24, weight: .bold))
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
                                .font(.system(size: 13))
                            Text(isPinned ? "取消常用" : "设为常用 — 显示在首页")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(isPinned ? Color.secondary : safe)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Emergency numbers
                    sectionCard(title: "紧急电话", icon: "phone.fill", color: alert) {
                        phoneRow("综合紧急", number: country.emergency)
                        if country.police != country.emergency {
                            phoneRow("警察", number: country.police)
                        }
                        if country.ambulance != country.emergency {
                            phoneRow("急救", number: country.ambulance)
                        }
                    }

                    // Chinese Embassy — consular protection numbers
                    sectionCard(title: "中国使领馆领事保护", icon: "building.columns.fill", color: safe) {
                        phoneRow("大使馆", number: country.embassy)
                        ForEach(Array(country.consulates.enumerated()), id: \.offset) { _, number in
                            phoneRow("总领馆", number: number)
                        }
                    }

                    // Global consular protection hotline
                    sectionCard(title: "外交部全球领保热线 (24小时)", icon: "globe", color: .blue) {
                        phoneRow("12308热线", number: "+86-10-12308")
                        phoneRow("备用号码", number: "+86-10-59913991")
                    }

                    Text("电话号码可直接拨打。数据离线可用。\n号码来源：中国外交部及各使领馆官网。")
                        .font(.system(size: 11))
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
                    Button("关闭") { dismiss() }
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
                    .font(.system(size: 14, weight: .semibold))
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
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Link(number, destination: URL(string: "tel:\(number.replacingOccurrences(of: "-", with: ""))")!)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(ink)
        }
    }
}
