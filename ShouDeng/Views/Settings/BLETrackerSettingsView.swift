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
                            Text("蓝牙追踪器")
                                .font(.scaled(size: 14, weight: .semibold))
                                .foregroundStyle(ink)
                            Text("配对 BLE 按钮或标签，用于紧急求助触发和分离提醒。")
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
                            Text("已配对设备")
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
                            Text("扫描并配对新设备")
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
                        Text("使用方法")
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(ink)

                        howRow("1", icon: "button.programmable", text: "紧急按钮模式：按下按钮立即触发 SOS，通知所有守护者")
                        howRow("2", icon: "dot.radiowaves.right", text: "分离提醒模式：标签超出蓝牙范围时自动通知守护者")
                        howRow("3", icon: "mappin.and.ellipse", text: "最后位置：自动记录标签最后出现的位置和时间")
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                    )

                    // Recommended devices
                    VStack(alignment: .leading, spacing: 6) {
                        Label("推荐设备", systemImage: "cart.fill")
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(lamp)

                        Text("Blue Charm BC011 (~$12) — 按钮 + iBeacon\nKKM B2 (~$15) — 单/双/长按，nRF52\nLansitec i5 (~$20) — 手环式，IP67 防水\n任何 BLE 4.0+ iBeacon 兼容标签均可使用")
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
            .navigationTitle("蓝牙追踪器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showPairSheet) {
                scanSheet
            }
            .alert("取消配对？", isPresented: $showUnpairConfirm) {
                Button("取消", role: .cancel) {}
                Button("取消配对", role: .destructive) {
                    if let id = unpairTagId { service.unpairTag(id) }
                }
            } message: {
                Text("取消配对后将停止监控此设备。")
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
                        Text(ago < 1 ? "刚刚在线" : "\(ago) 分钟前")
                            .font(.scaled(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未检测到")
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
                        Text("正在扫描附近的蓝牙设备...")
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
                        Text("未发现设备")
                            .font(.scaled(size: 14))
                            .foregroundStyle(.secondary)
                        Text("请确保蓝牙设备已开启且在附近")
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
                                        Text(device.name ?? "未知设备")
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
                        Text("重新扫描")
                            .font(.scaled(size: 14, weight: .medium))
                            .foregroundStyle(safe)
                    }
                }

                Spacer()
            }
            .navigationTitle("扫描设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
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
                TextField("设备名称（如：妈妈的手环）", text: $pairName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text("设备类型")
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(ink)
                    Picker("", selection: $pairType) {
                        Text("紧急按钮").tag(BLETrackerService.TrackerTag.TagType.panicButton)
                        Text("分离提醒").tag(BLETrackerService.TrackerTag.TagType.beacon)
                        Text("双模式").tag(BLETrackerService.TrackerTag.TagType.dual)
                    }
                    .pickerStyle(.segmented)
                }

                if pairType == .beacon || pairType == .dual {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("iBeacon UUID（可选）")
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
                        name: pairName.isEmpty ? (device.name ?? "蓝牙标签") : pairName,
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
                    Text("配对")
                        .font(.scaled(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(safe))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .navigationTitle("配对设备")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func typeLabel(_ type: BLETrackerService.TrackerTag.TagType) -> String {
        switch type {
        case .panicButton: return "紧急按钮"
        case .beacon: return "分离提醒"
        case .dual: return "双模式"
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
