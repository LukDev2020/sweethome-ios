import SwiftUI

// MARK: - Settings → Rider
//
// Vehicle · crew alerts · what the crew sees · shifts (late alert, night "Still OK?",
// saved shifts) · SOS countdowns · lock-screen card · quick reports · caution spots.
// Every row says what it changes; guardrails are in RiderSettings.

struct RiderSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editingTemplate: ShiftTemplate?
    @State private var newReport = ""

    private var s: RiderSettings { coordinator.riderSettings }
    private func set(_ change: @escaping (inout RiderSettings) -> Void) { coordinator.updateRiderSettings(change) }
    private func L(_ key: String) -> String { lang.localized(key) }

    var body: some View {
        NavigationStack {
            Form {
                vehicleSection
                crewSection
                shiftSection
                templatesSection
                sosSection
                lockCardSection
                reportsSection
                cautionSection
            }
            .navigationTitle(L("rider.settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() } } }
            .sheet(item: $editingTemplate) { t in
                ShiftTemplateEditor(template: t).environmentObject(coordinator)
            }
        }
    }

    // MARK: Vehicle

    private var vehicleSection: some View {
        Section {
            Picker(L("rider.settings.vehicle"), selection: Binding(get: { s.vehicle }, set: { v in set { $0.vehicle = v } })) {
                ForEach(RiderVehicle.allCases) { v in
                    Label(L("rider.vehicle.\(v.rawValue)"), systemImage: v.symbol).tag(v)
                }
            }
        } footer: { Text(L("rider.settings.vehicle.footer")) }
    }

    // MARK: Crew

    private var crewSection: some View {
        Section {
            Picker(L("rider.settings.offShift"), selection: Binding(get: { s.offShiftAlerts }, set: { v in set { $0.offShiftAlerts = v } })) {
                ForEach(RiderSettings.offShiftChoices, id: \.self) { c in Text(L("rider.settings.offShift.\(c)")).tag(c) }
            }
            if s.offShiftAlerts == "nearby" {
                Picker(L("rider.settings.radius"), selection: Binding(get: { s.alertRadiusKm }, set: { v in set { $0.alertRadiusKm = v } })) {
                    ForEach(RiderSettings.radiusChoices, id: \.self) { km in Text("\(km) km").tag(km) }
                }
            }
            Picker(L("rider.settings.precision"), selection: Binding(get: { s.crewPrecision }, set: { v in set { $0.crewPrecision = v } })) {
                Text(L("rider.settings.precision.exact")).tag("exact")
                Text(L("rider.settings.precision.approx")).tag("approx")
            }
        } header: {
            Text(L("rider.settings.crew"))
        } footer: {
            Text(L("rider.settings.crew.footer"))
        }
    }

    // MARK: Shifts

    private var shiftSection: some View {
        Section {
            Picker(L("rider.settings.grace"), selection: Binding(get: { s.graceMinutes }, set: { v in set { $0.graceMinutes = v } })) {
                ForEach(RiderSettings.graceChoices, id: \.self) { m in Text(String(format: L("rider.settings.minutes"), m)).tag(m) }
            }
            Picker(L("rider.settings.stillOk"), selection: Binding(get: { s.stillOkEveryMin }, set: { v in set { $0.stillOkEveryMin = v } })) {
                Text(L("rider.settings.stillOk.off")).tag(0)
                Text(L("rider.settings.stillOk.60")).tag(60)
                Text(L("rider.settings.stillOk.120")).tag(120)
            }
            if s.stillOkEveryMin > 0 {
                Picker(L("rider.settings.stillOk.from"), selection: Binding(get: { s.stillOkFromHour }, set: { v in set { $0.stillOkFromHour = v } })) {
                    ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
                }
                Picker(L("rider.settings.stillOk.to"), selection: Binding(get: { s.stillOkToHour }, set: { v in set { $0.stillOkToHour = v } })) {
                    ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
                }
            }
        } header: {
            Text(L("rider.settings.shifts"))
        } footer: {
            Text(L(s.stillOkEveryMin > 0 ? "rider.settings.stillOk.footer" : "rider.settings.grace.footer"))
        }
    }

    private var templatesSection: some View {
        Section {
            ForEach(s.templates) { t in
                Button { editingTemplate = t } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).foregroundStyle(.primary)
                            Text(t.timeRange + (t.remind && !t.weekdays.isEmpty ? " · " + weekdayList(t.weekdays) : ""))
                                .font(.scaled(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if t.remind { Image(systemName: "bell.fill").foregroundStyle(.secondary) }
                    }
                }
            }
            .onDelete { idx in set { $0.templates.remove(atOffsets: idx) } }
            if s.templates.count < RiderSettings.maxTemplates {
                Button {
                    editingTemplate = ShiftTemplate(name: "", startHour: 17, startMinute: 0, endHour: 22, endMinute: 0,
                                                    weekdays: [], watcherIds: coordinator.crew?.myWatcherIds ?? [], remind: false)
                } label: { Label(L("rider.template.add"), systemImage: "plus") }
            }
        } header: {
            Text(L("rider.template.title"))
        } footer: {
            Text(L("rider.template.footer"))
        }
    }

    private func weekdayList(_ days: Set<Int>) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().map { symbols[($0 - 1) % 7] }.joined(separator: " ")
    }

    // MARK: SOS

    private var sosSection: some View {
        Section {
            Stepper(value: Binding(get: { s.handlebarCountdown }, set: { v in set { $0.handlebarCountdown = v } }), in: 0...5) {
                HStack {
                    Text(L("rider.settings.countdown.handlebar"))
                    Spacer()
                    Text(s.handlebarCountdown == 0 ? L("rider.settings.countdown.now") : "\(s.handlebarCountdown) s")
                        .foregroundStyle(.secondary)
                }
            }
            Picker(L("rider.settings.countdown.screen"), selection: Binding(get: { s.screenCountdown }, set: { v in set { $0.screenCountdown = v } })) {
                ForEach(RiderSettings.screenCountdownChoices, id: \.self) { n in Text("\(n) s").tag(n) }
            }
        } header: {
            Text(L("rider.settings.countdown"))
        } footer: {
            Text(L(s.handlebarCountdown == 0 ? "rider.settings.countdown.nowWarning" : "rider.settings.countdown.footer"))
                .foregroundStyle(s.handlebarCountdown == 0 ? .orange : .secondary)
        }
    }

    // MARK: Lock-screen card

    private var lockCardSection: some View {
        Section {
            HStack {
                Label(L("rider.settings.card.sos"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(RC.alert)
                Spacer()
                Text(L("rider.settings.card.always")).font(.scaled(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(RiderLockButton.allCases) { b in
                let on = s.lockButtons.contains(b)
                Button {
                    set { st in
                        if on { st.lockButtons.removeAll { $0 == b } } else {
                            // Keep two: the newest choice replaces the oldest
                            st.lockButtons.append(b)
                            if st.lockButtons.count > 2 { st.lockButtons.removeFirst() }
                        }
                    }
                } label: {
                    HStack {
                        Label(L("rider.settings.card.\(b.rawValue)"), systemImage: b.symbol).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? RC.safe : Color(.tertiaryLabel))
                    }
                }
            }
            Toggle(L("rider.settings.card.timer"), isOn: Binding(get: { s.showShiftTimer }, set: { v in set { $0.showShiftTimer = v } })).tint(RC.safe)
            Toggle(L("rider.settings.card.watchers"), isOn: Binding(get: { s.showWatchers }, set: { v in set { $0.showWatchers = v } })).tint(RC.safe)
        } header: {
            Text(L("rider.settings.card"))
        } footer: {
            Text(L("rider.settings.card.footer"))
        }
    }

    // MARK: Quick reports

    private var reportsSection: some View {
        Section {
            Label(L("rider.bike.title"), systemImage: "exclamationmark.shield").foregroundStyle(.secondary)
            ForEach(s.customReports, id: \.self) { r in Label(r, systemImage: "exclamationmark.bubble") }
                .onDelete { idx in set { $0.customReports.remove(atOffsets: idx) } }
            if s.customReports.count < RiderSettings.maxCustomReports {
                HStack {
                    TextField(L("rider.settings.reports.placeholder"), text: $newReport)
                    Button(L("rider.settings.reports.add")) {
                        let r = newReport
                        set { $0.customReports.append(r) }
                        newReport = ""
                    }
                    .disabled(newReport.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } header: {
            Text(L("rider.settings.reports"))
        } footer: {
            Text(L("rider.settings.reports.footer"))
        }
    }

    private var cautionSection: some View {
        Section {
            Picker(L("rider.settings.caution"), selection: Binding(get: { s.cautionHours }, set: { v in set { $0.cautionHours = v } })) {
                ForEach(RiderSettings.cautionChoices, id: \.self) { h in Text(String(format: L("rider.settings.hours"), h)).tag(h) }
            }
        } footer: {
            Text(L("rider.settings.caution.footer"))
        }
    }
}

// MARK: - Saved shift

struct ShiftTemplateEditor: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State var template: ShiftTemplate

    private var isNew: Bool { !coordinator.riderSettings.templates.contains { $0.id == template.id } }
    private func L(_ key: String) -> String { lang.localized(key) }

    private func time(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("rider.template.name"), text: $template.name)
                DatePicker(L("rider.template.start"), selection: Binding(get: { time(template.startHour, template.startMinute) }, set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    template.startHour = c.hour ?? 0; template.startMinute = c.minute ?? 0
                }), displayedComponents: .hourAndMinute)
                DatePicker(L("rider.template.end"), selection: Binding(get: { time(template.endHour, template.endMinute) }, set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    template.endHour = c.hour ?? 0; template.endMinute = c.minute ?? 0
                }), displayedComponents: .hourAndMinute)
                Section {
                    Toggle(L("rider.template.remind"), isOn: $template.remind).tint(RC.safe)
                    if template.remind {
                        HStack(spacing: 6) {
                            ForEach(1...7, id: \.self) { day in
                                let on = template.weekdays.contains(day)
                                Button {
                                    if on { template.weekdays.remove(day) } else { template.weekdays.insert(day) }
                                } label: {
                                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                        .font(.scaled(size: 14, weight: .semibold))
                                        .frame(width: 34, height: 34)
                                        .foregroundStyle(on ? .white : .primary)
                                        .background(Circle().fill(on ? RC.safe : Color(.tertiarySystemFill)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } footer: {
                    Text(L("rider.template.remindFooter"))
                }
            }
            .navigationTitle(L(isNew ? "rider.template.add" : "rider.template.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.save")) {
                        var t = template
                        t.name = t.name.trimmingCharacters(in: .whitespaces)
                        coordinator.updateRiderSettings { s in
                            if let i = s.templates.firstIndex(where: { $0.id == t.id }) { s.templates[i] = t } else { s.templates.append(t) }
                        }
                        if t.remind { coordinator.pushService.registerForPushNotifications() }
                        dismiss()
                    }
                    .bold()
                    .disabled(template.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - "I've crashed"

/// Hurt → SOS at once (no countdown — they just told us). Not hurt → the people
/// watching the shift (and the crew on shift, if chosen) are told where; a short
/// checklist for the scene. Reported by the rider, never detected.
struct CrashReportView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var notHurt = false
    @State private var note = ""
    @State private var notifyCrew = true
    @State private var sending = false
    @State private var sent: Int?? = nil

    private func L(_ key: String) -> String { lang.localized(key) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !notHurt { question } else if sent == nil { notHurtForm } else { done }
                }
                .padding(20)
            }
            .navigationTitle(L("rider.crash.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L(sent == nil ? "common.cancel" : "common.done")) { dismiss() } } }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("rider.crash.question")).font(.scaled(size: 26, weight: .bold)).foregroundStyle(RC.ink)
            Button {
                dismiss()
                Task { await coordinator.reportCrash(hurt: true, note: nil, notifyCrew: true) }
            } label: {
                Label(L("rider.crash.hurt"), systemImage: "cross.case.fill")
                    .font(.scaled(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(RoundedRectangle(cornerRadius: 16).fill(RC.alert))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rider.crash.hurt")
            Text(L("rider.crash.hurtNote")).font(.scaled(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { withAnimation { notHurt = true } } label: {
                Label(L("rider.crash.ok"), systemImage: "checkmark.shield")
                    .font(.scaled(size: 17, weight: .semibold)).foregroundStyle(RC.safe)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: 16).stroke(RC.safe, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rider.crash.notHurt")
            Button {
                if let url = URL(string: "tel:\(coordinator.localEmergencyNumber)") { ExternalURL.open(url) }
            } label: {
                Label(String(format: L("rider.crash.call"), coordinator.localEmergencyNumber), systemImage: "phone.fill")
                    .font(.scaled(size: 15, weight: .semibold))
            }
            .padding(.top, 4)
        }
    }

    private var notHurtForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("rider.crash.checklist")).font(.scaled(size: 18, weight: .bold))
            ForEach(["safe", "photos", "details", "police"], id: \.self) { k in
                Label(L("rider.crash.step.\(k)"), systemImage: "checkmark.circle")
                    .font(.scaled(size: 15)).fixedSize(horizontal: false, vertical: true)
            }
            TextField(L("rider.crash.note"), text: $note, axis: .vertical)
                .lineLimit(2...5)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))
            if coordinator.crew != nil {
                Toggle(L("rider.crash.notifyCrew"), isOn: $notifyCrew).tint(RC.safe)
            }
            Button {
                sending = true
                Task {
                    let n = await coordinator.reportCrash(hurt: false, note: note, notifyCrew: notifyCrew && coordinator.crew != nil)
                    sending = false
                    sent = .some(n)
                }
            } label: {
                HStack { if sending { ProgressView().tint(.white) }; Text(L("rider.crash.send")) }
                    .font(.scaled(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 14).fill(RC.safe))
            }
            .buttonStyle(.plain)
            .disabled(sending)
            .accessibilityIdentifier("rider.crash.send")
            Text(L("rider.crash.sendNote")).font(.scaled(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("rider.crash.sent"), systemImage: "checkmark.seal.fill")
                .font(.scaled(size: 20, weight: .bold)).foregroundStyle(RC.safe)
            if case .some(.some(let n)) = sent {
                Text(String(format: L("rider.crash.sentCount"), n)).font(.scaled(size: 15))
            } else {
                Text(L("rider.crash.queued")).font(.scaled(size: 15)).foregroundStyle(.secondary)
            }
            Text(L("rider.crash.later")).font(.scaled(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
