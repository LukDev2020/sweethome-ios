import SwiftUI

// MARK: - Hotline Card View
//
// Persistent card shown on both home screens when the user has
// selected a country's emergency hotline. Shows the flag, country name,
// emergency number, and embassy number — always one tap away.

struct HotlineCardView: View {
    let hotline: SelectedHotline
    var onTapChange: (() -> Void)?
    var onRemove: (() -> Void)?
    @ObservedObject private var lang = LanguageManager.shared

    /// Read live from the single number table: hotlines saved by older builds
    /// stored the police number (e.g. Japan 110) as "emergency".
    private var emergencyNumber: String {
        RegionalEmergencyInfo.forCountry(hotline.countryCode).primaryNumber
    }

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Flag + country
                Text(hotline.flag)
                    .font(.scaled(size: 22))

                VStack(alignment: .leading, spacing: 1) {
                    Text(RegionalEmergencyInfo.regionName(hotline.countryCode))
                        .font(.scaled(size: 12, weight: .semibold))
                        .foregroundStyle(ink)
                    Text(lang.localized("hotline.emergency"))
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Emergency call button
                Link(destination: URL(string: "tel:\(emergencyNumber.filter(\.isNumber))")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.scaled(size: 11))
                        Text(emergencyNumber)
                            .font(.scaled(size: 14, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(alert)
                    .clipShape(Capsule())
                }
            }

            // Embassy row
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill")
                    .font(.scaled(size: 9))
                    .foregroundStyle(safe)
                Text(lang.localized("hotline.embassy"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                if let phone = hotline.selectedPhone, let label = hotline.selectedLabel {
                    // User-selected specific number
                    Link(destination: URL(string: "tel:\(phone.replacingOccurrences(of: "-", with: ""))")!) {
                        HStack(spacing: 3) {
                            Text(label)
                                .font(.scaled(size: 12))
                                .foregroundStyle(.secondary)
                            Text(phone)
                                .font(.scaled(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(ink)
                        }
                    }
                } else {
                    // Default embassy number
                    Link(destination: URL(string: "tel:\(hotline.embassy.replacingOccurrences(of: "-", with: ""))")!) {
                        Text(hotline.embassy)
                            .font(.scaled(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(ink)
                    }
                }
            }
            .padding(.top, 6)

            // 12308 global hotline
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.scaled(size: 9))
                    .foregroundStyle(.blue)
                Text(lang.localized("hotline.12308"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: URL(string: "tel:+861012308")!) {
                    Text("+86-10-12308")
                        .font(.scaled(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ink)
                }
            }
            .padding(.top, 4)

            // Change / Remove
            HStack(spacing: 16) {
                Spacer()
                if let onTapChange {
                    Button {
                        onTapChange()
                    } label: {
                        Text(lang.localized("hotline.change"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                if let onRemove {
                    Button {
                        onRemove()
                    } label: {
                        Text(lang.localized("hotline.remove"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(alert.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(alert.opacity(0.2), lineWidth: 1)
        )
    }
}
