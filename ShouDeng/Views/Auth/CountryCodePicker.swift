import SwiftUI

// MARK: - Country Code Picker
//
// Searchable sheet for selecting international dialing codes.
// Supports search by name (English/Chinese), dial code, or ISO code.

struct CountryCodePicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lang = LanguageManager.shared
    @Binding var selected: CountryCode
    @State private var searchText = ""

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    private var filtered: [CountryCode] {
        if searchText.isEmpty { return CountryCode.all }
        let query = searchText.lowercased()
        return CountryCode.all.filter {
            $0.name.lowercased().contains(query)
            || $0.localName.contains(query)
            || $0.dialCode.contains(query)
            || $0.isoCode.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { country in
                Button {
                    selected = country
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flag)
                            .font(.system(size: 24))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(country.localName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(ink)
                            Text(country.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(country.dialCode)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if country == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: lang.localized("picker.search"))
            .navigationTitle(lang.localized("picker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang.localized("picker.cancel")) { dismiss() }
                }
            }
        }
    }
}
