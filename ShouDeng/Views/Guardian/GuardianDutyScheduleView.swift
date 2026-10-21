import SwiftUI

// MARK: - Screen B4: Duty Schedule
//
// Design from shoudeng-full-design.html:
//   - 24-hour coverage track (visual bar with guardian segments + gaps)
//   - Hour labels 00-24
//   - Today's shifts panel
//   - Gap handling panel (toggle: route to response center, handoff reminders)
//   - Upsell for response center coverage

struct GuardianDutyScheduleView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    @State private var routeToCenter = true
    @State private var handoffReminder = true

    private var firstProtectedName: String {
        coordinator.protectedPersons.first?.user.displayName ?? "被守护者"
    }

    private var firstProtectedCity: String {
        coordinator.protectedPersons.first?.user.cityName ?? ""
    }

    var body: some View {
        Group {
            if coordinator.storeKitManager.canAccessFeature("duty_schedule") {
                dutyScheduleContent
            } else {
                SubscriptionGateView(
                    feature: "duty_schedule",
                    featureName: "值班排程",
                    onDismiss: {}
                )
            }
        }
    }

    private var dutyScheduleContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 2) {
                    Text("值班排程")
                        .font(.scaled(size: 20, weight: .bold))
                    Text("\(firstProtectedName)的一天\(firstProtectedCity.isEmpty ? "" : " · \(firstProtectedCity)时间")")
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // 24-hour track
                coverageTrack

                // Today's shifts
                todayShiftsPanel

                // Gap handling
                gapHandlingPanel

                // Upsell
                upsellCard
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("值班排程")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("守护团队 \(max(1, coordinator.protectedPersons.count + 1)) 人")
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 24h Coverage Track

    private var coverageTrack: some View {
        VStack(spacing: 5) {
            // Segmented bar — empty state when no duty assignments
            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    Rectangle().fill(pro.opacity(0.15))
                    Text("尚未设置排班")
                        .font(.scaled(size: 12, weight: .medium))
                        .foregroundStyle(pro)
                }
                .frame(width: w)
            }
            .frame(height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.13), lineWidth: 1)
            )

            // Hour labels
            HStack {
                ForEach(["00", "04", "08", "12", "16", "20", "24"], id: \.self) { hour in
                    Text(hour)
                        .font(.scaled(size: 11))
                        .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.45))
                    if hour != "24" { Spacer() }
                }
            }
        }
    }

    // MARK: - Today's Shifts Panel

    private var todayShiftsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日班次")
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Text("暂无班次安排")
                    .font(.scaled(size: 13))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.13), lineWidth: 1)
        )
    }

    // MARK: - Gap Handling Panel

    private var gapHandlingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("缺口处理")
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            toggleRow("无人时段转响应中心", isOn: $routeToCenter)
            toggleRow("交接前提醒", isOn: $handoffReminder)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.13), lineWidth: 1)
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

    // MARK: - Upsell

    private var upsellCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("凌晨两点到六点三地家人都在睡。这四小时目前由专员补上——订阅的价值就是这块空缺。")
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
            NavigationLink {
                GuardianPlanBillingView()
                    .environmentObject(coordinator)
            } label: {
                Text("查看响应中心记录")
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundStyle(pro)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(pro.opacity(0.06))
        )
    }
}
