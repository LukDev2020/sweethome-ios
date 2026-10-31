import SwiftUI
import UIKit

// MARK: - Trip Preflight Checklist
//
// Shown before a trip starts. The app can't download maps or send over Apple's
// satellite features itself, so it prepares the person to use what iPhone
// already offers when there's no signal:
//   - offline maps downloaded in Apple Maps (opened via "Open in Apple Maps")
//   - Find My location sharing with guardians (Find My via satellite)
//   - Emergency SOS via satellite
//   - carrier satellite data (iOS 26.1+), which this app uses for SOS/check-ins

struct TripPreflightView: View {
    static let skipKey = "trip.preflight.skip"

    enum Item: String, CaseIterable, Identifiable {
        case offlineMaps, findMy, satelliteSOS, carrierSatellite
        var id: String { rawValue }

        /// Carrier satellite data needs iOS 26.1 (ultra-constrained networking).
        static var available: [Item] {
            if #available(iOS 26.1, *) { return allCases }
            return allCases.filter { $0 != .carrierSatellite }
        }
    }

    let onStart: () -> Void

    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TripPreflightView.skipKey) private var skipNextTime = false
    @State private var done: Set<Item> = []
    @State private var batteryLevel: Float = -1

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 62/255, green: 142/255, blue: 99/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(lang.localized("preflight.subtitle"))
                        .font(.scaled(size: 14))
                        .foregroundStyle(.secondary)
                    batteryRow
                }
                Section {
                    ForEach(Item.available) { item in
                        itemRow(item)
                    }
                }
                Section {
                    Toggle(lang.localized("preflight.skip"), isOn: $skipNextTime)
                        .font(.scaled(size: 14))
                }
            }
            .navigationTitle(lang.localized("preflight.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.localized("settings.action.cancel")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    onStart()
                } label: {
                    Text(lang.localized("preflight.start"))
                        .font(.scaled(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(ink)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .onAppear {
                UIDevice.current.isBatteryMonitoringEnabled = true
                batteryLevel = UIDevice.current.batteryLevel
            }
        }
    }

    // MARK: Rows

    private var batteryRow: some View {
        HStack(spacing: 12) {
            Image(systemName: batteryLevel >= 0 && batteryLevel < 0.5 ? "battery.25" : "battery.100")
                .foregroundStyle(batteryLevel >= 0 && batteryLevel < 0.5 ? lamp : safe)
                .font(.scaled(size: 18))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(batteryLevel >= 0
                     ? String(format: lang.localized("preflight.battery.level"), Int(batteryLevel * 100))
                     : lang.localized("preflight.battery.unknown"))
                    .font(.scaled(size: 15, weight: .medium))
                if batteryLevel >= 0 && batteryLevel < 0.5 {
                    Text(lang.localized("preflight.battery.low"))
                        .font(.scaled(size: 13))
                        .foregroundStyle(lamp)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func itemRow(_ item: Item) -> some View {
        let isDone = done.contains(item)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isDone { done.remove(item) } else { done.insert(item) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isDone ? safe : .secondary)
                        .font(.scaled(size: 20))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.localized("preflight.\(item.rawValue).title"))
                            .font(.scaled(size: 15, weight: .semibold))
                            .foregroundStyle(ink)
                        Text(lang.localized("preflight.\(item.rawValue).detail"))
                            .font(.scaled(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isDone ? .isSelected : [])

            if item == .offlineMaps {
                Button {
                    AppleMapsLink.openAtCurrentLocation()
                } label: {
                    Label(lang.localized("preflight.offlineMaps.action"), systemImage: "map")
                        .font(.scaled(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
    }
}
