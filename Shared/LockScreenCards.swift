import SwiftUI

// MARK: - Lock-screen cards (Live Activity)
//
// The lock-screen layouts of both Live Activities. They live here, compiled into the
// widget *and* the app, so the app can show them in a Debug preview gallery
// (`-la-gallery`) exactly as the widget draws them.
//
// Fixed layout: every row is always there, with "—" when there is no data yet, so a
// card keeps the same size whether or not the family is set up.

/// The app's logo on a small white disc (readable on every card background). The
/// widget has its own small copy of "AppLogo" in its asset catalog.
struct CardLogo: View {
    let size: CGFloat
    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .padding(size * 0.08)
            .frame(width: size, height: size)
            .background(Circle().fill(.white))
            .accessibilityHidden(true)
    }
}

/// Protected person. Four layouts, all within the lock screen's 160 pt:
/// - everyday: who guards me, last check-in, latest family activity, medical line,
///   and SOS · Silent SOS · Fake call · OK (the rows chosen in Settings → Lock screen card)
/// - countdown (safety timer / home timer): time left, who gets alerted, +15 min · I'm here · SOS
/// - SOS (for the person): how far the alert has got — guardians reached, who is
///   handling it, the next automatic step — and Call 911 · I'm safe
/// - SOS (for a bystander): name, medical info, address, Call 911 · call the family
/// Colours are calm: dimmed tones on tinted backgrounds, no solid red.
struct ProtectedLockScreenCard: View {
    let state: ProtectedActivityAttributes.ContentState
    /// Settings preview passes the style being edited; the widget uses the card's own
    var style: LockScreenCardStyle? = nil
    /// The person's name (the activity's attributes), for the bystander card
    var userName: String = ""

    enum Mode: Equatable { case everyday, countdown, sos, bystander }

    static func mode(for state: ProtectedActivityAttributes.ContentState) -> Mode {
        if state.status == .sosActive { return state.sos?.bystander == true ? .bystander : .sos }
        if state.homeTimerDeadline != nil { return .countdown }
        return .everyday
    }

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }
    private let dash = "—"
    private var st: LockScreenCardStyle { style ?? state.cardStyle ?? .stored }
    private var s: CGFloat { st.s }
    private var primary: Color { st.theme.primary }
    private var secondary: Color { st.theme.secondary }
    private var accent: Color { st.accent.color }

    var body: some View {
        if let rider = state.rider {
            // The SOS version has four rows: it keeps the standard size to fit 160 pt
            RiderLockScreenCard(state: state, rider: rider,
                                style: state.status == .sosActive ? st.with(textSize: .standard) : st)
        } else {
            switch Self.mode(for: state) {
            case .everyday: everydayBody
            case .countdown: countdownBody
            case .sos: sosBody
            case .bystander: BystanderCard(state: state, st: st.with(textSize: .standard), name: userName)
            }
        }
    }

    // MARK: - Everyday

    private var everydayBody: some View {
        VStack(alignment: .leading, spacing: LockScreenCardStyle.rowSpacing) {
            header
            ForEach(st.visibleSections, id: \.self) { section in
                switch section {
                case .checkIn: checkInRow
                case .latest: latestRow
                case .medical: medicalRow
                case .actions: actionsRow
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, LockScreenCardStyle.verticalPadding)
    }

    // Logo · app · who is guarding me · status
    private var header: some View {
        HStack(spacing: 7 * s) {
            CardLogo(size: 22 * s)
            Text(WidgetDataStore.appName)
                .font(.system(size: 15 * s, weight: .bold))
                .foregroundStyle(primary)
                .lineLimit(1)
                .layoutPriority(1)
            HStack(spacing: -5 * s) {
                ForEach(0..<3, id: \.self) { i in
                    guardianSlot(i < state.guardians.count ? state.guardians[i] : nil)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Circle()
                    .fill(st.ink(statusTone))
                    .frame(width: 7 * s, height: 7 * s)
                Text(state.statusText)
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(st.ink(statusTone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(height: st.headerHeight)
    }

    // Last check-in · who is on duty
    private var checkInRow: some View {
        HStack(spacing: 12) {
            field(icon: "checkmark.circle", label: L("la.last.checkin")) {
                if let ci = state.lastCheckIn {
                    Text(ci, style: .time)
                } else {
                    Text(dash)
                }
            }
            if let onDuty = state.guardians.first(where: \.isOnDuty) {
                field(icon: "person.badge.shield.checkmark", label: onDuty.name) {
                    Text(L("la.on.duty"))
                }
            }
        }
        .frame(height: st.height(of: .checkIn))
    }

    // Latest family activity (or the location just sent)
    private var latestRow: some View {
        field(icon: "bubble.left", label: L("la.latest")) {
            if let shared = state.lastLocationShare,
               shared > (state.latestUpdateAt ?? .distantPast) {
                Text("\(L("la.location.sent")) · ") + Text(shared, style: .time)
            } else if let latest = state.latestUpdate, !latest.isEmpty {
                Text(latest)
            } else {
                Text(dash)
            }
        }
        .frame(height: st.height(of: .latest))
    }

    // Emergency medical info — for first responders
    private var medicalRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "staroflife.fill")
                .font(.system(size: 11 * s))
                .foregroundStyle(st.ink(.warn))
            Text(Self.medicalLine(state, L: L))
                .font(.system(size: 13 * s, weight: .medium))
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: st.height(of: .medical))
        .background(st.fill(.warn))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    // SOS opens the app to confirm and count down. Silent SOS (two taps), Fake call
    // and OK act right here, without unlocking.
    private var actionsRow: some View {
        HStack(spacing: 5) {
            Link(destination: URL(string: "shoudeng://sos")!) {
                CardButton(icon: "sos", title: L("la.sos.button"), tone: .sos, st: st, stacked: true)
            }
            Button(intent: LockScreenSilentSOSIntent()) { silentSOSButton }
                .buttonStyle(.plain)
            Button(intent: LockScreenFakeCallIntent()) {
                CardButton(icon: "phone.arrow.down.left", title: L("la.fake.call"), tone: .info, st: st, stacked: true)
            }
            .buttonStyle(.plain)
            Button(intent: LockScreenCheckInIntent()) {
                CardButton(icon: "checkmark", title: L("la.checkin.button"), tone: .safe, st: st, stacked: true)
            }
            .buttonStyle(.plain)
        }
        .frame(height: st.height(of: .actions))
    }

    @ViewBuilder
    private var silentSOSButton: some View {
        if let armed = state.silentSOSArmedUntil, armed > Date() {
            // First tap: the second one has to come within the countdown
            CardButton(icon: "hand.tap", title: L("la.silent.again"), tone: .warn, st: st, stacked: true,
                       countdown: armed)
        } else if state.silentSOSSentAt != nil {
            CardButton(icon: "checkmark.circle", title: L("la.silent.sent"), tone: .warn, st: st, stacked: true)
        } else {
            CardButton(icon: "speaker.slash", title: L("la.silent.sos"), tone: .warn, st: st, stacked: true)
        }
    }

    // MARK: - Countdown

    private var countdownBody: some View {
        VStack(alignment: .leading, spacing: LockScreenCardStyle.rowSpacing) {
            HStack(spacing: 7 * s) {
                Image(systemName: state.timerKind == "safety" ? "timer" : "figure.walk")
                    .font(.system(size: 15 * s, weight: .semibold))
                    .foregroundStyle(st.ink(.info))
                Text(countdownTitle)
                    .font(.system(size: 15 * s, weight: .bold))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if let deadline = state.homeTimerDeadline {
                    Text(timerInterval: Date()...max(deadline, Date()), countsDown: true)
                        .font(.system(size: 22 * s, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(primary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110 * s, alignment: .trailing)
                }
            }
            .frame(height: st.headerHeight)

            if let start = state.timerStartedAt, let deadline = state.homeTimerDeadline, start < deadline {
                ProgressView(timerInterval: start...deadline, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(st.ink(.info))
                .frame(height: 4)
            }

            line(icon: "bell", text: notifyLine)
            if s <= 1 {
                line(icon: "server.rack", text: L("la.timer.server"))
            }

            HStack(spacing: 5) {
                Button(intent: LockScreenExtendTimerIntent()) {
                    CardButton(icon: "clock.arrow.circlepath", title: L("la.plus.fifteen"), tone: .info, st: st)
                }
                .buttonStyle(.plain)
                Button(intent: LockScreenArrivedIntent()) {
                    CardButton(icon: "house", title: L("la.arrived"), tone: .safe, st: st)
                }
                .buttonStyle(.plain)
                Link(destination: URL(string: "shoudeng://sos")!) {
                    CardButton(icon: "sos", title: L("la.sos.button"), tone: .sos, st: st)
                }
            }
            .frame(height: st.height(of: .actions))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, LockScreenCardStyle.verticalPadding)
    }

    private var countdownTitle: String {
        if let label = state.homeTimerLabel, !label.isEmpty { return label }
        return L(state.timerKind == "safety" ? "la.timer.safety" : "la.home.countdown")
    }

    /// "If you don't check in: alerts Sarah, Mom"
    private var notifyLine: String {
        let names = state.guardians.prefix(3).map(\.name)
        return names.isEmpty ? L("la.timer.notify.sos") : L("la.timer.notify") + names.joined(separator: ", ")
    }

    // MARK: - SOS (for the person)

    private var sosBody: some View {
        let sos = state.sos
        return VStack(alignment: .leading, spacing: LockScreenCardStyle.rowSpacing) {
            HStack(spacing: 7 * s) {
                Circle().fill(st.ink(.sos)).frame(width: 8 * s, height: 8 * s)
                Text(L("la.sos.sent"))
                    .font(.system(size: 15 * s, weight: .bold))
                    .foregroundStyle(st.ink(.sos))
                    .lineLimit(1)
                if let started = sos?.startedAt {
                    Text(started, style: .timer)
                        .font(.system(size: 14 * s, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 64 * s, alignment: .leading)
                }
                Spacer(minLength: 4)
                Label(L("la.live.location"), systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(height: st.headerHeight)

            // Who has it
            if let name = sos?.acknowledgedByName, !name.isEmpty {
                line(icon: "checkmark.shield", text: String(format: L("la.sos.handling"), name), tone: .safe)
            } else if let n = sos?.guardiansNotified, n > 0 {
                line(icon: "person.2", text: String(format: L("la.sos.notified"), n))
            } else {
                line(icon: "person.2", text: L("la.sos.notifying"))
            }

            // What happens next
            line(icon: "phone.arrow.up.right") {
                if let sos, sos.acknowledgedByName == nil, let step = Self.nextStepKey(sos.nextStep), let at = sos.nextStepAt {
                    Text(L(step)) + Text(at, style: .time)
                } else if let calls = sos?.callsPlaced, calls > 0 {
                    Text(String(format: L("la.sos.calls"), calls))
                } else {
                    Text(L("la.family.alerted"))
                }
            }

            HStack(spacing: 5) {
                Link(destination: URL(string: "shoudeng://call-emergency")!) {
                    CardButton(icon: "phone.fill", title: L("la.rider.call") + state.emergencyPhone, tone: .sos, st: st)
                }
                // Ending an SOS asks for Face ID / the passcode in the app
                Link(destination: URL(string: "shoudeng://open")!) {
                    CardButton(icon: "checkmark.shield", title: L("la.rider.safe"), tone: .safe, st: st)
                }
            }
            .frame(height: st.height(of: .actions))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, LockScreenCardStyle.verticalPadding)
    }

    /// Key of "Auto call at" etc. for the server's next escalation step
    static func nextStepKey(_ step: String?) -> String? {
        guard let step else { return nil }
        if step.hasPrefix("voice") { return "la.sos.next.call" }
        if step.hasPrefix("hop") { return "la.sos.next.sms" }
        if step.hasPrefix("share") { return "la.sos.next.share" }
        return nil
    }

    // MARK: - Pieces

    private func line(icon: String, text: String, tone: LockScreenCardStyle.Tone? = nil) -> some View {
        line(icon: icon, tone: tone) { Text(text) }
    }

    private func line<V: View>(icon: String, tone: LockScreenCardStyle.Tone? = nil, @ViewBuilder text: () -> V) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12 * s))
                .foregroundStyle(tone.map(st.ink) ?? accent)
                .frame(width: 16 * s)
            text()
                .font(.system(size: 13 * s, weight: .medium))
                .foregroundStyle(tone.map(st.ink) ?? secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .frame(height: st.height(of: .latest))
    }

    private func guardianSlot(_ guardian: ProtectedActivityAttributes.GuardianInfo?) -> some View {
        ZStack {
            if let guardian {
                Circle()
                    .fill(guardian.isOnline ? st.ink(.safe).opacity(0.45) : SharedColors.offline.opacity(0.5))
                Text(guardian.initial)
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .font(.system(size: 11 * s, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .strokeBorder(secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .background(Circle().fill(st.theme.background))
            }
        }
        .frame(width: 22 * s, height: 22 * s)
    }

    private func field<V: View>(icon: String, label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12 * s))
                .foregroundStyle(accent)
            // The label gives way first; the value (time, countdown) is what matters
            Text(label)
                .font(.system(size: 13 * s))
                .foregroundStyle(secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            value()
                .font(.system(size: 15 * s, weight: .semibold))
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Blood A+ · Allergies: Penicillin · Meds Nitroglycerin (bag)", "—" for anything missing.
    static func medicalLine(_ state: ProtectedActivityAttributes.ContentState, L: (String) -> String) -> String {
        let dash = "—"
        let blood = state.bloodType.flatMap { $0.isEmpty ? nil : $0 } ?? dash
        let allergies = state.allergies.isEmpty ? dash : state.allergies.prefix(2).joined(separator: ", ")
        let meds: String = state.emergencyMedications.first.map { med in
            med.location.isEmpty ? med.name : "\(med.name) (\(med.location))"
        } ?? dash
        return "\(L("la.blood"))\(blood) · \(L("la.allergy"))\(allergies) · \(L("la.meds"))\(meds)"
    }

    private var statusTone: LockScreenCardStyle.Tone {
        switch state.status {
        case .normal: return .safe
        case .sosActive: return .sos
        case .timerRunning: return .info
        case .pendingCheckIn: return .warn
        }
    }
}

/// The SOS written for whoever finds the phone: who this is, medical info (only if
/// the person put the medical row on their card), the address, and calls.
struct BystanderCard: View {
    let state: ProtectedActivityAttributes.ContentState
    let st: LockScreenCardStyle
    let name: String

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }
    private var primary: Color { st.theme.primary }
    private var secondary: Color { st.theme.secondary }
    /// Medical details are private: shown only if the person chose the medical row
    private var showsMedical: Bool { st.sections.contains(.medical) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "cross.case")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(st.ink(.sos))
                Text(name.isEmpty ? L("la.sos.active") : name + L("la.needs.help"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(L("la.please.call") + state.emergencyPhone)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(st.ink(.sos))
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(height: 24)

            if showsMedical, !chips.isEmpty {
                HStack(spacing: 5) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(primary)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(st.fill(.warn), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 22)
                if let med = state.emergencyMedications.first {
                    row("pills", med.location.isEmpty ? med.name : "\(med.name) · \(med.location)")
                }
            } else {
                row("person.2", L("la.family.alerted"))
            }
            row("mappin.and.ellipse", state.sos?.address ?? "—")

            HStack(spacing: 5) {
                Link(destination: URL(string: "shoudeng://call-emergency")!) {
                    CardButton(icon: "phone.fill", title: L("la.rider.call") + state.emergencyPhone, tone: .sos, st: st)
                }
                if let phone = state.familyContactPhone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Link(destination: url) {
                        CardButton(icon: "person.crop.circle.badge.checkmark",
                                   title: L("la.contact") + (state.familyContactName ?? ""), tone: .info, st: st)
                    }
                } else {
                    Link(destination: URL(string: "shoudeng://open")!) {
                        CardButton(icon: "checkmark.shield", title: L("la.rider.safe"), tone: .safe, st: st)
                    }
                }
            }
            .frame(height: 36)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, LockScreenCardStyle.verticalPadding)
    }

    private var chips: [String] {
        var out: [String] = []
        if let blood = state.bloodType, !blood.isEmpty { out.append(L("la.blood") + blood) }
        if !state.allergies.isEmpty { out.append(L("la.allergy") + state.allergies.prefix(2).joined(separator: ", ")) }
        out += state.conditions.prefix(1).map { $0 }
        return Array(out.prefix(4))
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(st.accent.color)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .frame(height: 18)
    }
}

/// One card button: a tinted capsule with the icon and title in the tone's colour.
/// `stacked`: icon above a small title (four buttons in a row).
struct CardButton: View {
    let icon: String
    let title: String
    let tone: LockScreenCardStyle.Tone
    let st: LockScreenCardStyle
    var stacked = false
    /// Counts down under the title (the silent SOS waiting for its second tap)
    var countdown: Date? = nil

    var body: some View {
        let s = st.s
        Group {
            if stacked {
                VStack(spacing: 1) {
                    Image(systemName: icon).font(.system(size: 13 * s, weight: .semibold))
                    if let countdown {
                        Text(timerInterval: Date()...max(countdown, Date()), countsDown: true, showsHours: false)
                            .font(.system(size: 11 * s, weight: .semibold)).monospacedDigit()
                            .multilineTextAlignment(.center)
                    } else {
                        Text(title).font(.system(size: 11 * s, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.system(size: 13 * s, weight: .semibold))
                    Text(title).font(.system(size: 14 * s, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
        .foregroundStyle(st.ink(tone))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(st.fill(tone), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// Rider mode. On shift: shift time, crew nearby, planned end; SOS · OK · Report.
/// During an SOS it is written for whoever picks up the phone: the street, who is
/// coming, "press hard on the wound", and Call 000 / I'm safe (both open the app —
/// ending an SOS asks for Face ID or the passcode).
struct RiderLockScreenCard: View {
    let state: ProtectedActivityAttributes.ContentState
    let rider: RiderCardInfo
    let style: LockScreenCardStyle

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }
    private var s: CGFloat { style.s }
    private var primary: Color { style.theme.primary }
    private var secondary: Color { style.theme.secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: LockScreenCardStyle.rowSpacing) {
            if state.status == .sosActive { sosBody } else { shiftBody }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, LockScreenCardStyle.verticalPadding)
    }

    // MARK: On / off shift

    @ViewBuilder
    private var shiftBody: some View {
        HStack(spacing: 7 * s) {
            CardLogo(size: 22 * s)
            Image(systemName: rider.vehicleSymbol ?? "bicycle").font(.system(size: 14 * s, weight: .semibold)).foregroundStyle(style.accent.color)
            if let started = rider.shiftStartedAt {
                Text(L("la.rider.onShift")).font(.system(size: 15 * s, weight: .bold)).foregroundStyle(primary)
                if rider.showTimer ?? true {
                    Text(started, style: .timer).font(.system(size: 15 * s, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(primary).lineLimit(1).frame(maxWidth: 70 * s, alignment: .leading)
                }
            } else {
                Text(L("la.rider.offShift")).font(.system(size: 15 * s, weight: .bold)).foregroundStyle(primary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Circle().fill(rider.crewOnShiftNearby > 0 ? SharedColors.safe : SharedColors.offline).frame(width: 8 * s, height: 8 * s)
                Text(rider.crewOnShiftNearby > 0 ? "\(rider.crewOnShiftNearby)\(L("la.rider.crewNearby"))" : L("la.rider.noCrew"))
                    .font(.system(size: 13 * s, weight: .semibold)).foregroundStyle(secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(height: style.headerHeight)

        HStack(spacing: 12) {
            row(icon: "clock.badge.checkmark") {
                if let end = rider.checkDueAt { Text(L("la.rider.checkAt")) + Text(end, style: .time) } else { Text("—") }
            }
            if let names = rider.watcherNames, !names.isEmpty {
                row(icon: "eye.fill") { Text(names.joined(separator: ", ")) }
            } else {
                row(icon: "checkmark.circle") {
                    if let ci = state.lastCheckIn { Text(L("la.last.checkin") + " ") + Text(ci, style: .time) } else { Text("—") }
                }
            }
        }
        .frame(height: style.height(of: .checkIn))

        // SOS always first; the other two are the rider's choice (Settings → Rider)
        HStack(spacing: 6) {
            Link(destination: URL(string: "shoudeng://sos")!) {
                button("exclamationmark.triangle.fill", L("la.sos.button"), SharedColors.alert)
            }
            ForEach(Self.chosenButtons(rider.buttons), id: \.self) { choice in actionButton(choice) }
        }
        .frame(height: style.height(of: .actions))
    }

    // MARK: SOS — for the rider or a bystander

    @ViewBuilder
    private var sosBody: some View {
        HStack(spacing: 7 * s) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15 * s)).foregroundStyle(.white)
            Text(L("la.sos.active")).font(.system(size: 15 * s, weight: .bold)).foregroundStyle(.white)
            Spacer(minLength: 4)
            Group {
                if let helper = rider.helperName {
                    Text(helper + L("la.rider.onTheWay")) + Text(rider.helperDistanceM.map { " · \(Self.distance($0))" } ?? "")
                } else {
                    Text(L("la.rider.crewAlerted"))
                }
            }
            .font(.system(size: 13 * s, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .frame(height: style.headerHeight)
        .background(RoundedRectangle(cornerRadius: 8).fill(SharedColors.alert))

        Label(rider.sosAddress ?? "—", systemImage: "mappin.and.ellipse")
            .font(.system(size: 17 * s, weight: .bold)).foregroundStyle(primary)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(height: style.height(of: .medical))

        Text(L("la.rider.helping") + state.emergencyPhone)
            .font(.system(size: 13 * s, weight: .semibold)).foregroundStyle(SharedColors.alert)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(height: style.height(of: .latest))

        HStack(spacing: 6) {
            Link(destination: URL(string: "shoudeng://call-emergency")!) {
                button("phone.fill", L("la.rider.call") + state.emergencyPhone, SharedColors.alert)
            }
            Link(destination: URL(string: "shoudeng://open")!) {
                button("checkmark.shield.fill", L("la.rider.safe"), SharedColors.safe.opacity(0.9))
            }
        }
        .frame(height: style.height(of: .actions))
    }

    /// Two of ok | report | crash | location; anything else falls back to OK + Report
    static func chosenButtons(_ raw: [String]?) -> [String] {
        let known = ["ok", "report", "crash", "location"]
        var out: [String] = []
        for b in raw ?? [] where known.contains(b) && !out.contains(b) { out.append(b) }
        for b in ["ok", "report"] where out.count < 2 && !out.contains(b) { out.append(b) }
        return Array(out.prefix(2))
    }

    @ViewBuilder
    private func actionButton(_ choice: String) -> some View {
        switch choice {
        case "ok":
            Button(intent: LockScreenCheckInIntent()) {
                button("checkmark.circle.fill", L("la.checkin.button"), SharedColors.safe.opacity(0.9))
            }
            .buttonStyle(.plain)
        case "crash":
            Link(destination: URL(string: "shoudeng://rider-crash")!) {
                button("car.side.rear.and.collision.and.car.side.front", L("la.rider.crash"), SharedColors.warning)
            }
        case "location":
            Link(destination: URL(string: "shoudeng://share-location")!) {
                button("location.fill", L("la.location.button"), style.accent.color)
            }
        default:
            Link(destination: URL(string: "shoudeng://rider-report")!) {
                button("exclamationmark.shield.fill", L("la.rider.report"), style.accent.color)
            }
        }
    }

    private func row<V: View>(icon: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12 * s)).foregroundStyle(style.accent.color)
            value().font(.system(size: 14 * s, weight: .semibold)).foregroundStyle(primary).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func button(_ icon: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 13 * s, weight: .semibold))
            Text(title).font(.system(size: 14 * s, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: style.height(of: .actions))
        .background(color)
        .clipShape(Capsule())
    }

    static func distance(_ meters: Int) -> String {
        meters >= 1000 ? String(format: "%.1f km", Double(meters) / 1000) : "\(max(10, (meters / 10) * 10)) m"
    }
}

/// Guardian: family rows (status, city, last check-in, battery) — as many as fit at
/// the chosen text size — and a call button.
struct GuardianLockScreenCard: View {
    let state: GuardianActivityAttributes.ContentState
    var style: LockScreenCardStyle? = nil

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }
    private let dash = "—"
    private var st: LockScreenCardStyle { style ?? state.cardStyle ?? .stored }
    private var s: CGFloat { st.s }
    private var primary: Color { st.theme.primary }
    private var secondary: Color { st.theme.secondary }

    var body: some View {
        if let sos = state.sos {
            GuardianSOSCard(sos: sos, st: st.with(textSize: .standard))
        } else {
            familyBody
        }
    }

    private var familyBody: some View {
        let sorted = prioritySorted(state.persons)
        let rows = st.guardianPersonRows

        return VStack(spacing: LockScreenCardStyle.rowSpacing) {
            // Header
            HStack(spacing: 7 * s) {
                CardLogo(size: 20 * s)
                Text(sorted.isEmpty
                     ? "\(WidgetDataStore.appName) · \(L("la.persons.none"))"
                     : "\(WidgetDataStore.appName) · \(sorted.count)\(L("la.persons.count"))")
                    .font(.system(size: 15 * s, weight: .bold))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if sorted.count > rows {
                    // More people than rows at this text size
                    Text("+\(sorted.count - rows)")
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundStyle(secondary)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(sorted.isEmpty ? SharedColors.offline : overallStatusColor(state.overallStatus))
                        .frame(width: 8 * s, height: 8 * s)
                    Text(sorted.isEmpty ? dash : state.overallStatusText)
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundStyle(sorted.isEmpty ? secondary : overallStatusColor(state.overallStatus))
                        .lineLimit(1)
                }
            }
            .frame(height: st.guardianHeaderHeight)

            // Person rows, empty slots included
            ForEach(0..<rows, id: \.self) { i in
                personRow(i < sorted.count ? sorted[i] : nil)
            }

            // Bottom button: call whoever needs attention most, else open the app
            if !state.priorityPersonPhone.isEmpty,
               let url = URL(string: "tel:\(state.priorityPersonPhone)") {
                Link(destination: url) {
                    CardButton(icon: "phone.fill", title: L("la.call") + state.priorityPersonName,
                               tone: state.overallStatus == .sosAlert ? .sos : .info, st: st)
                        .frame(height: st.guardianButtonHeight)
                }
            } else {
                Link(destination: URL(string: "shoudeng://open")!) {
                    CardButton(icon: "arrow.up.forward.app", title: L("la.open.app"), tone: .info, st: st)
                        .frame(height: st.guardianButtonHeight)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, LockScreenCardStyle.verticalPadding)
    }

    @ViewBuilder
    private func personRow(_ person: GuardianActivityAttributes.PersonInfo?) -> some View {
        HStack(spacing: 7) {
            ZStack {
                if let person {
                    Circle().fill(personStatusColor(person.status).opacity(0.45))
                    Text(person.initial)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .font(.system(size: 10 * s, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            .frame(width: 20 * s, height: 20 * s)

            if let person {
                Text(person.displayName)
                    .font(.system(size: 15 * s, weight: .semibold))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                Text(personStatusLabel(person))
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(personStatusColor(person.status))
                    .lineLimit(1)
                if s < 1.2 {
                    Text(person.cityName.isEmpty ? dash : person.cityName)
                        .font(.system(size: 13 * s))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            } else {
                Text(L("la.slot.empty"))
                    .font(.system(size: 13 * s))
                    .foregroundStyle(secondary)
            }

            Spacer(minLength: 4)

            // Last check-in time
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 11 * s))
                if let ci = person?.lastCheckIn {
                    Text(ci, style: .time)
                } else {
                    Text(dash)
                }
            }
            .font(.system(size: 13 * s))
            .foregroundStyle(secondary)
            .lineLimit(1)
            .fixedSize()

            // Battery
            HStack(spacing: 2) {
                let battery = person?.batteryLevel
                Image(systemName: battery.map(batteryIcon) ?? "battery.0")
                    .font(.system(size: 11 * s))
                Text(battery.map { "\(Int($0 * 100))%" } ?? dash)
            }
            .font(.system(size: 13 * s))
            .foregroundStyle((person?.batteryLevel ?? 1) < 0.2 ? st.ink(.warn) : secondary)
            .lineLimit(1)
            .fixedSize()
        }
        .frame(height: st.guardianRowHeight)
    }

    // MARK: - Helpers

    private func overallStatusColor(_ status: GuardianActivityAttributes.OverallStatus) -> Color {
        switch status {
        case .allSafe: return st.ink(.safe)
        case .needsAttention: return st.ink(.warn)
        case .sosAlert: return st.ink(.sos)
        }
    }

    private func personStatusColor(_ status: GuardianActivityAttributes.PersonStatus) -> Color {
        switch status {
        case .normal: return st.ink(.safe)
        case .overdue: return st.ink(.warn)
        case .alert: return st.ink(.sos)
        case .unreachable: return SharedColors.offline
        }
    }

    private func personStatusLabel(_ person: GuardianActivityAttributes.PersonInfo) -> String {
        switch person.status {
        case .normal: return L("la.safe")
        case .overdue: return L("la.overdue")
        case .alert: return L("la.alert")
        case .unreachable: return L("la.offline")
        }
    }

    private func batteryIcon(_ level: Double) -> String {
        if level > 0.75 { return "battery.100" }
        if level > 0.50 { return "battery.75" }
        if level > 0.25 { return "battery.50" }
        return "battery.25"
    }

    private func prioritySorted(_ persons: [GuardianActivityAttributes.PersonInfo]) -> [GuardianActivityAttributes.PersonInfo] {
        persons.sorted { a, b in
            statusPriority(a.status) > statusPriority(b.status)
        }
    }

    private func statusPriority(_ status: GuardianActivityAttributes.PersonStatus) -> Int {
        switch status {
        case .alert: return 3
        case .overdue: return 2
        case .unreachable: return 1
        case .normal: return 0
        }
    }
}


/// Guardian card when someone they look after raised an SOS: where (and how far),
/// battery, how fresh the location is, who is handling it; Call · On my way · Directions.
struct GuardianSOSCard: View {
    let sos: GuardianActivityAttributes.SOSCardInfo
    let st: LockScreenCardStyle

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }
    private var primary: Color { st.theme.primary }
    private var secondary: Color { st.theme.secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: LockScreenCardStyle.rowSpacing) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(st.fill(.sos))
                    Text(sos.initial)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(st.ink(.sos))
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
                .frame(width: 22, height: 22)
                Text(sos.personName + L("la.g.sos"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(st.ink(.sos))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(sos.startedAt, style: .timer)
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 64, alignment: .leading)
                Spacer(minLength: 4)
                if let battery = sos.batteryLevel {
                    Label("\(Int((battery * 100).rounded()))%", systemImage: battery < 0.2 ? "battery.25" : "battery.50")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(battery < 0.2 ? st.ink(.warn) : secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(height: 26)

            row(icon: "mappin.and.ellipse", tone: .sos) {
                Text(sos.address ?? L("la.g.noloc"))
                    + Text(sos.distanceMeters.map { " · " + String(format: L("la.g.away"), RiderLockScreenCard.distance($0)) } ?? "")
                        .foregroundColor(secondary)
            }

            if sos.acknowledgedByMe {
                row(icon: "checkmark.shield", tone: .safe) { Text(L("la.g.you.handling")) }
            } else if let name = sos.acknowledgedByName, !name.isEmpty {
                row(icon: "checkmark.shield", tone: .safe) { Text(String(format: L("la.sos.handling"), name)) }
            } else if let at = sos.locationAt {
                row(icon: "clock") { Text(L("la.g.located")) + Text(at, style: .time) + Text(" · " + L("la.g.unanswered")) }
            } else {
                row(icon: "clock") { Text(L("la.g.unanswered")) }
            }

            HStack(spacing: 5) {
                if let phone = sos.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Link(destination: url) {
                        CardButton(icon: "phone.fill", title: L("la.g.call"), tone: .sos, st: st)
                    }
                }
                Button(intent: LockScreenAcknowledgeSOSIntent()) {
                    CardButton(icon: sos.acknowledgedByMe ? "checkmark" : "figure.run",
                               title: L(sos.acknowledgedByMe ? "la.g.told" : "la.g.onway"), tone: .safe, st: st)
                }
                .buttonStyle(.plain)
                .disabled(sos.acknowledgedByMe)
                if let lat = sos.latitude, let lng = sos.longitude,
                   let url = URL(string: "https://maps.apple.com/?daddr=\(lat),\(lng)") {
                    Link(destination: url) {
                        CardButton(icon: "arrow.triangle.turn.up.right.diamond", title: L("la.g.navigate"), tone: .info, st: st)
                    }
                }
            }
            .frame(height: 36)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, LockScreenCardStyle.verticalPadding)
    }

    private func row<V: View>(icon: String, tone: LockScreenCardStyle.Tone? = nil, @ViewBuilder text: () -> V) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tone.map(st.ink) ?? st.accent.color)
                .frame(width: 16)
            text()
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tone == .sos ? primary : (tone.map(st.ink) ?? secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .frame(height: 20)
    }
}

#if DEBUG
// MARK: - Preview gallery (Debug only)
//
// Launch with `-la-gallery` (optionally `-app_language zh-Hans`) to see all four states
// at lock-screen size: full / empty, for each role.

extension ProtectedActivityAttributes.ContentState {
    static func sample(full: Bool, timer: Bool = true, armed: Bool = false, now: Date = Date()) -> Self {
        var state = base(full: full, timer: full && timer, now: now)
        if armed { state.silentSOSArmedUntil = now.addingTimeInterval(4) }
        if full && timer { state.timerStartedAt = now.addingTimeInterval(-12 * 60); state.timerKind = "safety" }
        return state
    }

    static func sampleSOS(bystander: Bool, now: Date = Date()) -> Self {
        var state = base(full: true, timer: false, now: now)
        state.status = .sosActive
        state.statusText = WidgetDataStore.localized("la.sos.active")
        state.conditions = ["糖尿病"]
        state.cardStyle = LockScreenCardStyle.stored
        state.cardStyle?.sections = [.checkIn, .medical, .actions]
        state.familyContactName = "Sarah"
        state.familyContactPhone = "+15145550100"
        state.sos = .init(startedAt: now.addingTimeInterval(-134), guardiansNotified: 2, callsPlaced: 0,
                          acknowledgedByName: bystander ? nil : "Sarah", nextStep: "voice1",
                          nextStepAt: now.addingTimeInterval(60), address: "1250 Rue Sainte-Catherine, Ville-Marie",
                          bystander: bystander)
        return state
    }

    private static func base(full: Bool, timer: Bool, now: Date) -> Self {
        .init(
            status: timer ? .timerRunning : .normal,
            statusText: WidgetDataStore.localized(timer ? "la.home.timer" : "la.normal"),
            guardians: full ? [
                .init(name: "Sarah", initial: "S", isOnDuty: true, isOnline: true),
                .init(name: "Kevin", initial: "K", isOnDuty: false, isOnline: false),
            ] : [],
            lastCheckIn: full ? now.addingTimeInterval(-25 * 60) : nil,
            homeTimerDeadline: timer ? now.addingTimeInterval(18 * 60) : nil,
            homeTimerLabel: nil,
            emergencyPhone: "120",
            emergencyLabel: "120",
            bloodType: full ? "A+" : nil,
            allergies: full ? ["青霉素"] : [],
            conditions: [],
            emergencyNote: nil,
            emergencyMedications: full ? [.init(name: "硝酸甘油", location: "包里", dosage: "")] : [],
            latestUpdate: full ? "Sarah：妈，到家了吗？" : nil,
            latestUpdateAt: full ? now.addingTimeInterval(-6 * 60) : nil
        )
    }
}

extension GuardianActivityAttributes.ContentState {
    static func sampleSOS(now: Date = Date()) -> Self {
        var state = sample(full: true, now: now)
        state.overallStatus = .sosAlert
        state.sos = .init(sosEventId: "sample", personName: "妈妈", initial: "妈", startedAt: now.addingTimeInterval(-134),
                          batteryLevel: 0.23, address: "1250 Rue Sainte-Catherine", distanceMeters: 3400,
                          locationAt: now.addingTimeInterval(-15), latitude: 45.5, longitude: -73.57,
                          phone: "+15145550100")
        return state
    }

    static func sample(full: Bool, now: Date = Date()) -> Self {
        .init(
            overallStatus: full ? .needsAttention : .allSafe,
            overallStatusText: WidgetDataStore.localized(full ? "la.needs.attention" : "la.all.safe"),
            persons: full ? [
                .init(id: "1", displayName: "妈妈", initial: "妈", status: .normal, cityName: "成都",
                      lastCheckIn: now.addingTimeInterval(-25 * 60), batteryLevel: 0.82),
                .init(id: "2", displayName: "爸爸", initial: "爸", status: .overdue, cityName: "成都",
                      lastCheckIn: now.addingTimeInterval(-9 * 3600), batteryLevel: 0.15),
            ] : [],
            priorityPersonName: full ? "爸爸" : "",
            priorityPersonPhone: full ? "+8613800138000" : "",
            updatedAt: now
        )
    }
}

/// The four cards on a lock-screen-like background, at the system's card width
/// (screen − 2 × 14 pt) and within its 160 pt height limit (red outline = limit).
struct LockScreenCardGallery: View {
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let w = geo.size.width - 28
                    item("被守护者 · 日常", ProtectedLockScreenCard(state: .sample(full: true, timer: false)), width: w)
                    item("被守护者 · 静默求救待确认", ProtectedLockScreenCard(state: .sample(full: true, timer: false, armed: true)), width: w)
                    item("被守护者 · 倒计时", ProtectedLockScreenCard(state: .sample(full: true)), width: w)
                    item("被守护者 · 求救中", ProtectedLockScreenCard(state: .sampleSOS(bystander: false), userName: "陈美玲"), width: w, alert: true)
                    item("被守护者 · 求救中（旁人）", ProtectedLockScreenCard(state: .sampleSOS(bystander: true), userName: "陈美玲"), width: w, alert: true)
                    item("被守护者 · 空白", ProtectedLockScreenCard(state: .sample(full: false)), width: w)
                    item("守护者 · 有数据", GuardianLockScreenCard(state: .sample(full: true)), width: w)
                    item("守护者 · 收到求救", GuardianLockScreenCard(state: .sampleSOS()), width: w, alert: true)
                    item("守护者 · 空白", GuardianLockScreenCard(state: .sample(full: false)), width: w)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 20)
            }
            .background(
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
        }
    }

    private func item<V: View>(_ title: String, _ card: V, width: CGFloat, alert: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            card
                .frame(width: width)
                .background(LockScreenCardStyle.stored.theme.background(alert: alert))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .top) {
                    // The lock screen cuts a card off at 160 pt
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.red.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: width, height: 160)
                }
        }
    }
}

/// `-lockscreen-shot protected|guardian`: one card on an iPhone-style lock screen
/// (clock, date, wallpaper) with English sample data, for App Store screenshots.
struct LockScreenShot: View {
    let guardian: Bool

    private static var now: Date {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 18; c.hour = 9; c.minute = 41
        return Calendar.current.date(from: c) ?? Date()
    }

    private var protectedState: ProtectedActivityAttributes.ContentState {
        let now = Self.now
        return .init(
            status: .timerRunning,
            statusText: WidgetDataStore.localized("la.home.timer"),
            guardians: [
                .init(name: "Sarah", initial: "S", isOnDuty: true, isOnline: true),
                .init(name: "Kevin", initial: "K", isOnDuty: false, isOnline: true),
            ],
            lastCheckIn: now.addingTimeInterval(-25 * 60),
            // The countdown runs against the real clock
            homeTimerDeadline: Date().addingTimeInterval(18 * 60 + 20),
            homeTimerLabel: nil,
            emergencyPhone: "911",
            emergencyLabel: "911",
            bloodType: "A+",
            allergies: ["Penicillin"],
            conditions: [],
            emergencyNote: nil,
            emergencyMedications: [.init(name: "Nitroglycerin", location: "Handbag", dosage: "")],
            latestUpdate: "Sarah: Mom, are you home yet?",
            latestUpdateAt: now.addingTimeInterval(-6 * 60)
        )
    }

    private var guardianState: GuardianActivityAttributes.ContentState {
        let now = Self.now
        return .init(
            overallStatus: .needsAttention,
            overallStatusText: WidgetDataStore.localized("la.needs.attention"),
            persons: [
                .init(id: "1", displayName: "Mom", initial: "M", status: .normal, cityName: "Chengdu",
                      lastCheckIn: now.addingTimeInterval(-25 * 60), batteryLevel: 0.82),
                .init(id: "2", displayName: "Dad", initial: "D", status: .overdue, cityName: "Chengdu",
                      lastCheckIn: now.addingTimeInterval(-9 * 3600), batteryLevel: 0.15),
            ],
            priorityPersonName: "Dad",
            priorityPersonPhone: "+15555550123",
            updatedAt: now
        )
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width - 28, 520)
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.09, blue: 0.17),
                                        Color(red: 0.13, green: 0.20, blue: 0.36),
                                        Color(red: 0.62, green: 0.40, blue: 0.20)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.top, geo.safeAreaInsets.top > 30 ? 6 : 20)
                    Text("Wednesday, November 18")
                        .font(.system(size: 21, weight: .semibold))
                        .padding(.top, 10)
                    Text("9:41")
                        .font(.system(size: 104, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Group {
                        if guardian {
                            GuardianLockScreenCard(state: guardianState)
                        } else {
                            ProtectedLockScreenCard(state: protectedState)
                        }
                    }
                    .frame(width: cardWidth)
                    .background(LockScreenCardStyle.stored.theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.bottom, 36)
                    HStack {
                        circle("flashlight.off.fill")
                        Spacer()
                        circle("camera.fill")
                    }
                    .padding(.horizontal, 46)
                    .padding(.bottom, 26)
                }
                .foregroundStyle(.white)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func circle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .medium))
            .frame(width: 50, height: 50)
            .background(.ultraThinMaterial, in: Circle())
    }
}
#endif
