import SwiftUI

// MARK: - BLE Tracker Settings
//
// Pair and manage Bluetooth tracker tags:
// - Scan for nearby BLE devices
// - Pair as panic button (SOS trigger) or proximity beacon (separation alert)
// - View paired tags with last-seen status
// - Configure iBeacon UUID/Major/Minor for proximity monitoring

struct BLETrackerSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = BLETrackerService.shared

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    @State private var showPairSheet = false
    @State private var selectedDevice: BLETrackerService.DiscoveredDevice?
    @State private var pairName = ""
    @State private var pairType: BLETrackerService.TrackerTag.TagType = .panicButton
    @State private var pairBeaconUUID = ""
    @State private var showUnpairConfirm = false
    @State private var unpairTagId: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Info banner
                    HStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.scaled(size: 22))
                            .foregroundStyle(safe)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(langManager.localized("ble.title"))
                                .font(.scaled(size: 14, weight: .semibold))
                                .foregroundStyle(ink)
                            Text(langManager.localized("ble.subtitle"))
                                .font(.scaled(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(safe.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(safe.opacity(0.15), lineWidth: 1)
                            )
                    )

                    // Paired tags
                    if !service.pairedTags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(langManager.localized("ble.pairedDevices"))
                                .font(.scaled(size: 13, weight: .semibold))
                                .foregroundStyle(ink)

                            ForEach(service.pairedTags) { tag in
                                pairedTagRow(tag)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                        )
                    }

                    // Scan button
                    Button {
                        service.startDiscovery()
                        showPairSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text(langManager.localized("ble.scanAndPair"))
                                .font(.scaled(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12).fill(safe)
                        )
                    }

                    // How it works
                    VStack(alignment: .leading, spacing: 8) {
                        Text(langManager.localized("ble.howToUse"))
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(ink)

                        howRow("1", icon: "button.programmable", text: langManager.localized("ble.how1"))
                        howRow("2", icon: "dot.radiowaves.right", text: langManager.localized("ble.how2"))
                        howRow("3", icon: "mappin.and.ellipse", text: langManager.localized("ble.how3"))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                    )

                    // Recommended devices
                    VStack(alignment: .leading, spacing: 6) {
                        Label(langManager.localized("ble.recommended"), systemImage: "cart.fill")
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(lamp)

                        Text(langManager.localized("ble.recommendedList"))
                            .font(.scaled(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(lamp.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(lamp.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle(langManager.localized("ble.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(langManager.localized("ble.close")) { dismiss() }
                }
            }
            .sheet(isPresented: $showPairSheet) {
                scanSheet
            }
            .alert(langManager.localized("ble.unpairConfirmTitle"), isPresented: $showUnpairConfirm) {
                Button(langManager.localized("ble.cancel"), role: .cancel) {}
                Button(langManager.localized("ble.unpair"), role: .destructive) {
                    if let id = unpairTagId { service.unpairTag(id) }
                }
            } message: {
                Text(langManager.localized("ble.unpairMessage"))
            }
        }
    }

    // MARK: - Paired Tag Row

    private func pairedTagRow(_ tag: BLETrackerService.TrackerTag) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tag.type == .panicButton ? "button.programmable" : tag.type == .beacon ? "dot.radiowaves.right" : "button.programmable.square.fill")
                .font(.scaled(size: 18))
                .foregroundStyle(safe)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundStyle(ink)

                HStack(spacing: 6) {
                    Text(typeLabel(tag.type))
                        .font(.scaled(size: 10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(safe.opacity(0.7)))

                    if let sighting = service.lastSeenLocations[tag.id] {
                        let ago = Int(Date().timeIntervalSince(sighting.timestamp) / 60)
                        Text(ago < 1 ? langManager.localized("ble.justOnline") : String(format: langManager.localized("ble.minutesAgo"), ago))
                            .font(.scaled(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(langManager.localized("ble.notDetected"))
                            .font(.scaled(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                unpairTagId = tag.id
                showUnpairConfirm = true
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(alert.opacity(0.6))
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Scan Sheet

    private var scanSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if service.isScanning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(langManager.localized("ble.scanning"))
                            .font(.scaled(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                }

                if service.discoveredDevices.isEmpty && !service.isScanning {
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.scaled(size: 36))
                            .foregroundStyle(.secondary)
                        Text(langManager.localized("ble.noDevices"))
                            .font(.scaled(size: 14))
                            .foregroundStyle(.secondary)
                        Text(langManager.localized("ble.noDevicesHint"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .padding(.top, 40)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(service.discoveredDevices) { device in
                            Button {
                                selectedDevice = device
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "wave.3.right.circle.fill")
                                        .foregroundStyle(safe)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name ?? langManager.localized("ble.unknownDevice"))
                                            .font(.scaled(size: 13, weight: .medium))
                                            .foregroundStyle(ink)
                                        Text("信号: \(device.rssi) dBm")
                                            .font(.scaled(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.scaled(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if !service.isScanning {
                    Button {
                        service.startDiscovery()
                    } label: {
                        Text(langManager.localized("ble.rescan"))
                            .font(.scaled(size: 14, weight: .medium))
                            .foregroundStyle(safe)
                    }
                }

                Spacer()
            }
            .navigationTitle(langManager.localized("ble.scanTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(langManager.localized("ble.cancel")) {
                        service.stopDiscovery()
                        showPairSheet = false
                    }
                }
            }
            .sheet(item: $selectedDevice) { device in
                pairConfigSheet(device: device)
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Pair Config Sheet

    private func pairConfigSheet(device: BLETrackerService.DiscoveredDevice) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField(langManager.localized("ble.deviceName"), text: $pairName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text(langManager.localized("ble.deviceType"))
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(ink)
                    Picker("", selection: $pairType) {
                        Text(langManager.localized("ble.typePanic")).tag(BLETrackerService.TrackerTag.TagType.panicButton)
                        Text(langManager.localized("ble.typeBeacon")).tag(BLETrackerService.TrackerTag.TagType.beacon)
                        Text(langManager.localized("ble.typeDual")).tag(BLETrackerService.TrackerTag.TagType.dual)
                    }
                    .pickerStyle(.segmented)
                }

                if pairType == .beacon || pairType == .dual {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(langManager.localized("ble.beaconUUID"))
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(ink)
                        TextField("E2C56DB5-DFFB-48D2-B060-D0F5A71096E0", text: $pairBeaconUUID)
                            .textFieldStyle(.roundedBorder)
                            .font(.scaled(size: 11))
                            .autocapitalization(.allCharacters)
                    }
                }

                Button {
                    let beaconUUID = pairBeaconUUID.isEmpty ? BLETrackerService.defaultBeaconUUID : pairBeaconUUID
                    service.pairTag(
                        device,
                        name: pairName.isEmpty ? (device.name ?? langManager.localized("ble.defaultTag")) : pairName,
                        type: pairType,
                        beaconUUID: (pairType == .beacon || pairType == .dual) ? beaconUUID : nil
                    )
                    ConsentLogger.shared.log(
                        userId: coordinator.authManager.currentUserId ?? "unknown",
                        item: "ble_tracker",
                        copyVersion: "v1.0",
                        action: "paired_\(pairType.rawValue)"
                    )
                    selectedDevice = nil
                    showPairSheet = false
                } label: {
                    Text(langManager.localized("ble.pair"))
                        .font(.scaled(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(safe))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .navigationTitle(langManager.localized("ble.pairTitle"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func typeLabel(_ type: BLETrackerService.TrackerTag.TagType) -> String {
        switch type {
        case .panicButton: return langManager.localized("ble.typePanic")
        case .beacon: return langManager.localized("ble.typeBeacon")
        case .dual: return langManager.localized("ble.typeDual")
        }
    }

    private func howRow(_ num: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.scaled(size: 13))
                .foregroundStyle(safe)
                .frame(width: 20)
            Text(text)
                .font(.scaled(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }
}
