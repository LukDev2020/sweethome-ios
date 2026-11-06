import SwiftUI

// MARK: - Settings → Lock screen card → Customize
//
// Live preview of the real card (same view the widget draws) with the 160 pt line the
// lock screen cuts at; text size, background, accent colour and — for the protected
// person — which rows to show. Rows that would not fit at the chosen size are greyed.

struct LockScreenCardSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var style = LockScreenCardStyle.stored

    private var isGuardian: Bool { coordinator.userRole == .guardian }
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        VStack(spacing: 0) {
            // Pinned, so every change below can be seen on the card
            preview
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(lang.localized("lsc.textSize")) {
                    Picker("", selection: $style.textSize) {
                        ForEach(LockScreenCardStyle.TextSize.allCases, id: \.self) { size in
                            Text(lang.localized("lsc.textSize.\(size.rawValue)")).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    if !isGuardian {
                        Text(lang.localized("lsc.textSize.hint"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    } else if style.guardianPersonRows < 3 {
                        Text(String(format: lang.localized("lsc.guardianRows"), style.guardianPersonRows))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                section(lang.localized("lsc.background")) {
                    swatches(LockScreenCardStyle.Theme.allCases, selected: style.theme,
                             color: { $0.background }, label: { lang.localized("lsc.theme.\($0.rawValue)") }) {
                        style.theme = $0
                    }
                }

                section(lang.localized("lsc.accent")) {
                    swatches(LockScreenCardStyle.Accent.allCases, selected: style.accent,
                             color: { $0.color }, label: { lang.localized("lsc.accent.\($0.rawValue)") }) {
                        style.accent = $0
                    }
                }

                if !isGuardian {
                    section(lang.localized("lsc.rows")) {
                        ForEach(LockScreenCardStyle.Section.allCases, id: \.self) { row in
                            rowToggle(row)
                        }
                    }
                }

                Button(lang.localized("lsc.reset")) { style = .standard }
                    .font(.scaled(size: 14))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(16)
            .padding(.bottom, 80) // clear of the floating SOS button
        }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(lang.localized("lsc.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: style) { _, new in
            // A row that no longer fits at a bigger text size is switched off
            var fitted = new
            fitted.sections = new.visibleSections
            if fitted != new { style = fitted; return }
            new.save()
            coordinator.liveActivityManager.restyle()
        }
    }

    // MARK: Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lang.localized("lsc.preview"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                let width = geo.size.width - 20
                ZStack(alignment: .top) {
                    Group {
                        if isGuardian {
                            GuardianLockScreenCard(state: guardianSample, style: style)
                        } else {
                            ProtectedLockScreenCard(state: protectedSample, style: style)
                        }
                    }
                    .frame(width: width)
                    .background(style.theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    // Where the lock screen cuts the card off
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: width, height: LockScreenCardStyle.heightLimit)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Color(white: 0.3), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .frame(height: LockScreenCardStyle.heightLimit + 28)
            .allowsHitTesting(false)
            Text(lang.localized("lsc.preview.hint"))
                .font(.scaled(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    /// The person's own card data where there is some, sample text where there isn't
    private var protectedSample: ProtectedActivityAttributes.ContentState {
        var state = ProtectedActivityAttributes.ContentState(
            status: .normal,
            statusText: WidgetDataStore.localized("la.normal"),
            guardians: coordinator.myGuardians.prefix(3).map {
                .init(name: $0.user.displayName, initial: $0.user.avatarInitial, isOnDuty: $0.isOnDuty, isOnline: $0.isOnDuty)
            },
            lastCheckIn: WidgetDataStore.read().lastCheckInDate ?? Date().addingTimeInterval(-25 * 60),
            homeTimerDeadline: nil,
            homeTimerLabel: nil,
            emergencyPhone: coordinator.localEmergencyNumber,
            emergencyLabel: coordinator.localEmergencyNumber,
            bloodType: MedicalCardCache.load()?.bloodType,
            allergies: MedicalCardCache.load()?.allergies ?? [],
            conditions: [],
            emergencyNote: nil,
            emergencyMedications: []
        )
        state.latestUpdate = lang.localized("lsc.sample.latest")
        state.latestUpdateAt = Date().addingTimeInterval(-6 * 60)
        return state
    }

    private var guardianSample: GuardianActivityAttributes.ContentState {
        let persons = coordinator.protectedPersons.prefix(3).map { pp in
            GuardianActivityAttributes.PersonInfo(
                id: pp.id, displayName: pp.user.displayName, initial: pp.user.avatarInitial,
                status: .normal, cityName: pp.user.cityName,
                lastCheckIn: pp.lastCheckIn, batteryLevel: pp.batteryLevel)
        }
        return GuardianActivityAttributes.ContentState(
            overallStatus: .allSafe,
            overallStatusText: WidgetDataStore.localized("la.all.safe"),
            persons: Array(persons),
            priorityPersonName: persons.first?.displayName ?? "",
            priorityPersonPhone: persons.isEmpty ? "" : "+1",
            updatedAt: Date())
    }

    // MARK: Controls

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func swatches<T: Hashable>(_ items: [T], selected: T, color: @escaping (T) -> Color,
                                       label: @escaping (T) -> String, pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                Button { pick(item) } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(color(item))
                            .overlay(Circle().stroke(Color(.separator), lineWidth: 1))
                            .overlay(Circle().stroke(safe, lineWidth: item == selected ? 3 : 0).padding(-4))
                            .frame(width: 34, height: 34)
                        Text(label(item))
                            .font(.scaled(size: 11))
                            .foregroundStyle(item == selected ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == selected ? .isSelected : [])
            }
        }
    }

    private func rowToggle(_ row: LockScreenCardStyle.Section) -> some View {
        let on = style.sections.contains(row)
        var with = style.sections
        if !on { with.append(row) }
        let fits = on || style.fits(Array(Set(with)))
        return Toggle(isOn: Binding(
            get: { on },
            set: { newValue in
                if newValue { style.sections.append(row) } else { style.sections.removeAll { $0 == row } }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.localized("lsc.row.\(row.rawValue)"))
                    .font(.scaled(size: 15))
                if !fits {
                    Text(lang.localized("lsc.row.noRoom"))
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(safe)
        .disabled(!fits)
    }
}
