import SwiftUI
import CoreLocation

// MARK: - Nearby alerts card
//
// Simple home (.compact): one calm line per category — disaster, traffic, crime —
// showing the most important item, "nothing reported", or "no public information
// here, take care". Full home (.full): distance chips and up to five items. Either
// opens NearbyAlertsSheet with everything and the distance choice.

struct NearbyAlertsCard: View {
    enum Style { case compact, full }
    let style: Style
    let coordinate: CLLocationCoordinate2D?
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var store = NearbyAlertsStore.shared
    @ObservedObject private var lang = LanguageManager.shared
    @State private var showAll = false

    private let ink = Color.appInk

    var body: some View {
        Button { showAll = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                header
                if style == .full { radiusChips }
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(.separator).opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.nearbyAlerts")
        .task(id: taskKey) {
            await store.load(near: coordinate, api: coordinator.apiClient)
        }
        .sheet(isPresented: $showAll) {
            NearbyAlertsSheet(coordinate: coordinate).environmentObject(coordinator)
        }
    }

    /// Reload when the place (~1 km) or the distance changes
    private var taskKey: String {
        guard let c = coordinate else { return "none-\(store.radiusKm)" }
        return String(format: "%.2f,%.2f,%d", c.latitude, c.longitude, store.radiusKm)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.scaled(size: style == .compact ? 18 : 16, weight: .semibold))
                .foregroundStyle(Color(red: 47/255, green: 111/255, blue: 143/255))
            Text(lang.localized("nearby.title"))
                .font(.scaled(size: style == .compact ? 20 : 17, weight: .bold))
                .foregroundStyle(ink)
            Spacer(minLength: 6)
            Text(String(format: lang.localized("nearby.radius"), store.radiusKm))
                .font(.scaled(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.scaled(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
        }
    }

    private var radiusChips: some View {
        HStack(spacing: 6) {
            ForEach(NearbyAlertsStore.radii, id: \.self) { r in
                Button { store.radiusKm = r } label: {
                    Text(String(format: lang.localized("nearby.km"), r))
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(store.radiusKm == r ? .white : ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(store.radiusKm == r ? Color(red: 47/255, green: 111/255, blue: 143/255) : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nearby.radius.\(r)")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let result = store.result {
            let rows = NearbyRows.rows(for: result, style: style)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { row in NearbyRowView(row: row, large: style == .compact) }
            }
            if result.alerts.contains(where: { $0.severity >= 2 }) {
                Label(lang.localized("nearby.tip.serious"), systemImage: "hand.raised.fill")
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 196/255, green: 110/255, blue: 40/255))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if store.loading || coordinate == nil {
            HStack(spacing: 8) {
                ProgressView()
                Text(lang.localized(coordinate == nil ? "nearby.waitingLocation" : "nearby.loading"))
                    .font(.scaled(size: 15)).foregroundStyle(.secondary)
            }
        } else if store.failed {
            Text(lang.localized("nearby.failed"))
                .font(.scaled(size: 15)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Rows: an alert, or a category's state

struct NearbyRow: Identifiable {
    enum Kind { case alert(NearbyAlert), state(NearbyCategory, NearbyCoverage.Status, radiusKm: Int) }
    let id: String
    let kind: Kind
}

enum NearbyRows {
    /// Compact: exactly one line per category. Full: up to five items, then a line for
    /// each category that has nothing to show.
    static func rows(for result: NearbyAlertsResponse, style: NearbyAlertsCard.Style) -> [NearbyRow] {
        func state(_ c: NearbyCategory) -> NearbyRow {
            NearbyRow(id: "state-\(c.rawValue)", kind: .state(c, result.status(c), radiusKm: result.radiusKm))
        }
        switch style {
        case .compact:
            return NearbyCategory.allCases.map { c in
                if let first = result.alerts(in: c).first { return NearbyRow(id: first.id, kind: .alert(first)) }
                return state(c)
            }
        case .full:
            let items = result.alerts.sorted(by: NearbyAlert.moreImportant).prefix(5).map { NearbyRow(id: $0.id, kind: .alert($0)) }
            let empty = NearbyCategory.allCases.filter { result.alerts(in: $0).isEmpty }.map(state)
            return items + empty
        }
    }
}

struct NearbyRowView: View {
    let row: NearbyRow
    var large = false
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        switch row.kind {
        case .alert(let a): alertRow(a)
        case .state(let c, let status, let radius): stateRow(c, status, radius)
        }
    }

    static func color(_ severity: Int) -> Color {
        switch severity {
        case 3: return Color(red: 196/255, green: 69/255, blue: 60/255)
        case 2: return Color(red: 214/255, green: 128/255, blue: 40/255)
        default: return Color(red: 90/255, green: 110/255, blue: 140/255)
        }
    }

    private func alertRow(_ a: NearbyAlert) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: a.icon)
                .font(.system(size: large ? 18 : 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: large ? 34 : 30, height: large ? 34 : 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(Self.color(a.severity)))
            VStack(alignment: .leading, spacing: 2) {
                Text(NearbyText.title(a))
                    .font(.scaled(size: large ? 17 : 15, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(NearbyText.detail(a))
                    .font(.scaled(size: large ? 14 : 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func stateRow(_ c: NearbyCategory, _ status: NearbyCoverage.Status, _ radius: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status == .noData ? "info.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: large ? 18 : 16, weight: .semibold))
                .foregroundStyle(status == .noData ? Color(.systemGray) : Color(red: 63/255, green: 143/255, blue: 110/255))
                .frame(width: large ? 34 : 30, height: large ? 34 : 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color(.tertiarySystemFill)))
            Text(NearbyText.state(c, status, radiusKm: radius))
                .font(.scaled(size: large ? 15 : 14))
                .foregroundStyle(status == .noData ? .secondary : Color.appInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Wording

enum NearbyText {
    private static var lang: LanguageManager { LanguageManager.shared }
    private static var locale: Locale { Locale(identifier: lang.current.rawValue) }

    static func kind(_ kind: String) -> String {
        lang.localized("nearby.kind.\(kind)", fallback: lang.localized("nearby.kind.hazard"))
    }

    static func title(_ a: NearbyAlert) -> String {
        if a.kind == "crimeSummary" {
            return lang.localized("nearby.crime.summary", count: a.total ?? 0)
        }
        if a.kind == "earthquake", let m = a.magnitude {
            return String(format: lang.localized("nearby.quake"), String(format: "%.1f", m))
        }
        // Weather alerts: the official name says more ("High Wind Warning")
        if a.kind == "weather", let place = a.place, !place.isEmpty {
            return "\(kind(a.kind)) · \(place)"
        }
        return kind(a.kind)
    }

    static func detail(_ a: NearbyAlert) -> String {
        if a.kind == "crimeSummary" {
            var parts: [String] = []
            if let top = a.top, !top.isEmpty {
                parts.append(top.map { prettyLabel($0.label) }.joined(separator: ", "))
            }
            if let until = a.dataUntilDate {
                parts.append(String(format: lang.localized("nearby.dataUntil"),
                                    until.formatted(.dateTime.month().day().locale(locale))))
            }
            return parts.joined(separator: " · ")
        }
        var parts: [String] = []
        parts.append(a.distanceKm < 1 ? lang.localized("nearby.here")
                     : String(format: lang.localized("nearby.away"), Int(a.distanceKm.rounded())))
        if let date = a.occurredDate { parts.append(relative(date)) }
        if let place = a.place, !place.isEmpty, a.kind != "weather" { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    static func state(_ c: NearbyCategory, _ status: NearbyCoverage.Status, radiusKm: Int) -> String {
        switch status {
        case .clear:
            return c == .crime ? lang.localized("nearby.clear.crime")
                : String(format: lang.localized("nearby.clear.\(c.rawValue)"), radiusKm)
        case .noData, .found:
            return lang.localized("nearby.noData.\(c.rawValue)")
        }
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// "PETIT LARCENY" → "Petit larceny"
    static func prettyLabel(_ s: String) -> String {
        guard s == s.uppercased() else { return s }
        let lower = s.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}

// MARK: - All nearby: distance, every item, where the information comes from

struct NearbyAlertsSheet: View {
    let coordinate: CLLocationCoordinate2D?
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var store = NearbyAlertsStore.shared
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(lang.localized("nearby.radius.title"), selection: $store.radiusKm) {
                        ForEach(NearbyAlertsStore.radii, id: \.self) { r in
                            Text(String(format: lang.localized("nearby.km"), r)).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("nearby.radiusPicker")
                } header: {
                    Text(lang.localized("nearby.radius.title"))
                } footer: {
                    Text(lang.localized("nearby.radius.footer"))
                }

                if let result = store.result {
                    ForEach(NearbyCategory.allCases) { c in
                        Section {
                            let items = result.alerts(in: c)
                            if items.isEmpty {
                                NearbyRowView(row: NearbyRow(id: c.rawValue, kind: .state(c, result.status(c), radiusKm: result.radiusKm)))
                            } else {
                                ForEach(items) { a in
                                    Button {
                                        if let s = a.url, let url = URL(string: s) { openURL(url) }
                                    } label: {
                                        NearbyRowView(row: NearbyRow(id: a.id, kind: .alert(a)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            Label(lang.localized("nearby.cat.\(c.rawValue)"), systemImage: c.icon)
                        } footer: {
                            let sources = result.coverage[c.rawValue]?.sources ?? []
                            if !sources.isEmpty {
                                Text(String(format: lang.localized("nearby.source"), sources.joined(separator: ", ")))
                            }
                        }
                    }
                } else if store.loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    Text(lang.localized("nearby.failed")).foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        ExternalURL.open(URL(string: "tel:\(coordinator.localEmergencyNumber)")!)
                    } label: {
                        Label(String(format: lang.localized("nearby.callEmergency"), coordinator.localEmergencyNumber),
                              systemImage: "phone.fill")
                            .foregroundStyle(Color(red: 196/255, green: 69/255, blue: 60/255))
                    }
                } footer: {
                    Text(lang.localized("nearby.disclaimer"))
                }
            }
            .navigationTitle(lang.localized("nearby.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.localized("common.done")) { dismiss() }
                }
            }
            .refreshable { await store.load(near: coordinate, api: coordinator.apiClient, force: true) }
            .task(id: store.radiusKm) { await store.load(near: coordinate, api: coordinator.apiClient) }
        }
    }
}
