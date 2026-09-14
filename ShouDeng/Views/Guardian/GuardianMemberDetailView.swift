import SwiftUI
import MapKit

// MARK: - Screen B3: Member Detail
//
// Shows real data for a specific protected person.
// Guardian navigates here by tapping a person card on the home screen.

struct GuardianMemberDetailView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let personId: String

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    private var person: ProtectedPerson? {
        coordinator.protectedPersons.first { $0.id == personId }
    }

    var body: some View {
        ScrollView {
            if let person {
                VStack(spacing: 12) {
                    // Header
                    VStack(spacing: 2) {
                        Text(person.user.displayName)
                            .font(.system(size: 20, weight: .bold))
                        Text(headerSubtitle(person))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Map with real location
                    locationMapSection(person)

                    // Status panel
                    statusPanel(person)

                    // Timeline
                    timelineSection

                    // Emergency contacts
                    NavigationLink {
                        EmergencyContactsView(
                            personName: person.user.displayName,
                            countryCode: person.user.countryCode.isEmpty ? "CN" : person.user.countryCode
                        )
                        .environmentObject(coordinator)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.arrow.up.right.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                            Text("紧急救援电话")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.15), lineWidth: 1)
                        )
                    }

                    // Action buttons
                    HStack(spacing: 8) {
                        actionButton("发消息", icon: "message.fill") {
                            // Open SMS to this person's phone (if available via guardian link)
                        }
                        actionButton("拨号", icon: "phone.fill") {
                            // Open phone dialer
                        }
                    }
                }
                .padding(.horizontal, 16)
            } else {
                ContentUnavailableView(
                    "找不到此人",
                    systemImage: "person.slash",
                    description: Text("该被守护者可能已被移除")
                )
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("成员详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("你正在值班")
                    .font(.system(size: 11))
                    .foregroundStyle(safe)
            }
        }
    }

    // MARK: - Header

    private func headerSubtitle(_ person: ProtectedPerson) -> String {
        var parts: [String] = []
        if !person.user.cityName.isEmpty {
            parts.append(person.user.cityName)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = person.user.timeZone
        parts.append("当地 \(formatter.string(from: Date()))")
        parts.append("\(person.protectionLayers) 层保护")
        return parts.joined(separator: " · ")
    }

    // MARK: - Location Map

    private func locationMapSection(_ person: ProtectedPerson) -> some View {
        Group {
            if let loc = person.lastKnownLocation {
                let coord = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    Annotation(person.user.displayName, coordinate: coord) {
                        ZStack {
                            Circle().fill(lamp.opacity(0.25)).frame(width: 28, height: 28)
                            Circle().fill(lamp).frame(width: 14, height: 14)
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    if let addr = loc.address, !addr.isEmpty {
                        Text(addr)
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ink.opacity(0.7))
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .frame(height: 160)
                    VStack(spacing: 4) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("暂无位置信息")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Status Panel

    private func statusPanel(_ person: ProtectedPerson) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("此刻")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            statusRow("状态", value: statusText(person.status), isOk: person.status == .normal)
            if let battery = person.batteryLevel {
                statusRow("电量", value: "\(Int(battery * 100))%", isOk: battery > 0.2)
            } else {
                statusRow("电量", value: "未知", isOk: false)
            }
            if let lastActivity = person.lastPhoneActivity {
                let minutes = Int(Date().timeIntervalSince(lastActivity) / 60)
                statusRow("手机", value: minutes < 5 ? "在线 · \(minutes) 分钟前使用过" : "\(minutes) 分钟前活跃", isOk: minutes < 30)
            } else {
                statusRow("手机", value: "未知", isOk: false)
            }
            if let checkIn = person.lastCheckIn {
                let minutes = Int(Date().timeIntervalSince(checkIn) / 60)
                let text = minutes < 60 ? "\(minutes) 分钟前" : "\(minutes / 60) 小时前"
                statusRow("上次报平安", value: text, isOk: !person.isOverdue)
            } else {
                statusRow("上次报平安", value: "从未", isOk: false)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func statusText(_ status: SafetyStatus) -> String {
        switch status {
        case .normal: return "正常"
        case .pendingCheckIn: return "待打卡"
        case .overdue: return "超时未打卡"
        case .alert: return "求助中"
        case .unreachable: return "无法联系"
        }
    }

    private func statusRow(_ label: String, value: String, isOk: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(isOk ? safe : .primary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        let personEntries = coordinator.timeline.prefix(10)

        return Group {
            if personEntries.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(personEntries)) { entry in
                        timelineRow(time: formatTime(entry.timestamp), event: entry.description)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func timelineRow(time: String, event: String) -> some View {
        HStack {
            Text(time)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Text(event)
                .font(.system(size: 12.5))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ink.opacity(0.2), lineWidth: 1)
            )
        }
    }
}
