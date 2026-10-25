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
    @ObservedObject private var langManager = LanguageManager.shared

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    @State private var routeToCenter = true
    @State private var handoffReminder = true

    private var firstProtectedName: String {
        coordinator.protectedPersons.first?.user.displayName ?? langManager.localized("guardian.duty.protected.person")
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
                    featureName: langManager.localized("guardian.duty.schedule"),
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
                    Text(langManager.localized("guardian.duty.schedule"))
                        .font(.scaled(size: 20, weight: .bold))
                    Text({
                        let dayText = String(format: langManager.localized("guardian.duty.person.day"), firstProtectedName)
                        return firstProtectedCity.isEmpty ? dayText : "\(dayText) · \(String(format: langManager.localized("guardian.duty.city.time"), firstProtectedCity))"
                    }())
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
        .navigationTitle(langManager.localized("guardian.duty.schedule"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(String(format: langManager.localized("guardian.duty.team.count"), max(1, coordinator.protectedPersons.count + 1)))
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
                    Text(langManager.localized("guardian.duty.no.schedule"))
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
            Text(langManager.localized("guardian.duty.today.shifts"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Text(langManager.localized("guardian.duty.no.shifts"))
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
            Text(langManager.localized("guardian.duty.gap.handling"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            toggleRow(langManager.localized("guardian.duty.route.to.center"), isOn: $routeToCenter)
            toggleRow(langManager.localized("guardian.duty.handoff.reminder"), isOn: $handoffReminder)
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
            Text(langManager.localized("guardian.duty.upsell.text"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
            NavigationLink {
                GuardianPlanBillingView()
                    .environmentObject(coordinator)
            } label: {
                Text(langManager.localized("guardian.duty.view.center.log"))
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
