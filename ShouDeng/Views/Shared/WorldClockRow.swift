import SwiftUI
import MapKit

// MARK: - World clocks (home screen, both roles)
//
// The row under the map is the person's own choice of cities. Until they change
// it, it shows their own city and their family's (from where each person is).
// The first change makes it their list: any cities, in any order (up to 8), with
// or without their own clock and the family's. "Back to family clocks" undoes it.
//
// Apple has no world-clock API an app can use (the Clock app's list is private),
// so cities come from the time-zone database (instant, offline) and Maps search
// (any city; MKMapItem gives its time zone). Choices stay on this phone; the demo
// keeps its own in memory.

struct WorldClockCity: Codable, Hashable, Identifiable {
    var name: String
    var timeZoneId: String
    /// My own clock: follows where I am (name and time zone come from my profile)
    var isMe: Bool? = nil
    /// Whose city it was when the family row was taken over (shown in the sheet)
    var person: String? = nil
    var id: String { isMe == true ? "me" : "\(timeZoneId)|\(name)" }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneId) ?? .current }
}

/// One clock in the row
struct WorldClockEntry: Identifiable {
    let id: String
    let title: String
    let timeZone: TimeZone
    let isMe: Bool
    /// Whose clock it is (family), shown in the settings sheet
    var person: String? = nil
}

@MainActor
final class WorldClockSettings: ObservableObject {
    static let shared = WorldClockSettings()
    static let maxClocks = 8
    private static let storageKey = "world_clock_settings_v2"

    private struct Stored: Codable {
        /// false: the automatic row (me + family)
        var customized = false
        var clocks: [WorldClockCity] = []
    }

    @Published private(set) var isCustomized = false
    @Published private(set) var clocks: [WorldClockCity] = []

    // The demo's choices live here and vanish when it ends
    private var demoStore: Stored?
    private var defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private var stored: Stored {
        get {
            if ExploreMode.isActive { return demoStore ?? Stored() }
            guard let data = defaults.data(forKey: Self.storageKey),
                  let s = try? JSONDecoder().decode(Stored.self, from: data) else { return Stored() }
            return s
        }
        set {
            if ExploreMode.isActive {
                demoStore = newValue
            } else if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.storageKey)
            }
            isCustomized = newValue.customized
            clocks = newValue.clocks
        }
    }

    /// Re-read (the demo started or ended)
    func load() {
        if !ExploreMode.isActive { demoStore = nil }
        let s = stored
        isCustomized = s.customized
        clocks = s.clocks
    }

    /// The automatic row as a list the person can change
    static func automatic(me: WorldClockEntry?, family: [WorldClockEntry]) -> [WorldClockCity] {
        var list: [WorldClockCity] = me.map { [WorldClockCity(name: $0.title, timeZoneId: $0.timeZone.identifier, isMe: true)] } ?? []
        for f in family {
            let city = WorldClockCity(name: f.title, timeZoneId: f.timeZone.identifier, person: f.person)
            if !list.contains(where: { $0.id == city.id }) { list.append(city) }
        }
        return list
    }

    /// The list as it is now: the person's own, or the automatic one
    func current(me: WorldClockEntry?, family: [WorldClockEntry]) -> [WorldClockCity] {
        isCustomized ? clocks : Self.automatic(me: me, family: family)
    }

    /// Every change starts from what the row shows and makes it the person's own list
    private func change(me: WorldClockEntry?, family: [WorldClockEntry], _ edit: (inout [WorldClockCity]) -> Void) {
        var list = current(me: me, family: family)
        edit(&list)
        stored = Stored(customized: true, clocks: Array(list.prefix(Self.maxClocks)))
    }

    /// false when full, already there, or not a real time zone
    @discardableResult
    func add(_ city: WorldClockCity, me: WorldClockEntry?, family: [WorldClockEntry]) -> Bool {
        let list = current(me: me, family: family)
        guard list.count < Self.maxClocks, !list.contains(where: { $0.id == city.id }),
              TimeZone(identifier: city.timeZoneId) != nil else { return false }
        change(me: me, family: family) { $0.append(city) }
        return true
    }

    /// My own clock back, first in the row
    func addMe(_ me: WorldClockEntry, family: [WorldClockEntry]) {
        guard !current(me: me, family: family).contains(where: { $0.isMe == true }) else { return }
        change(me: me, family: family) { $0.insert(WorldClockCity(name: me.title, timeZoneId: me.timeZone.identifier, isMe: true), at: 0) }
    }

    func remove(atOffsets offsets: IndexSet, me: WorldClockEntry?, family: [WorldClockEntry]) {
        change(me: me, family: family) { $0.remove(atOffsets: offsets) }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int, me: WorldClockEntry?, family: [WorldClockEntry]) {
        change(me: me, family: family) { $0.move(fromOffsets: source, toOffset: destination) }
    }

    /// Back to the automatic row (me + family)
    func reset() {
        stored = Stored()
    }

    /// The row. My clock always shows where I am now.
    func entries(me: WorldClockEntry?, family: [WorldClockEntry]) -> [WorldClockEntry] {
        current(me: me, family: family).compactMap { city in
            if city.isMe == true { return me }
            return WorldClockEntry(id: "city:\(city.id)", title: city.name, timeZone: city.timeZone, isMe: false, person: city.person)
        }
    }

    // MARK: City search (offline part)

    /// Cities named in the time-zone database ("Asia/Shanghai" → Shanghai), matched
    /// against the English name and the time zone's localized name.
    static func timeZoneMatches(_ query: String, limit: Int = 8) -> [WorldClockCity] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        let locale = Locale(identifier: LanguageManager.shared.current.rawValue)
        var result: [WorldClockCity] = []
        for id in TimeZone.knownTimeZoneIdentifiers where id.contains("/") && !id.hasPrefix("Etc/") {
            let city = id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id
            let zone = TimeZone(identifier: id)?.localizedName(for: .generic, locale: locale) ?? ""
            if city.lowercased().contains(q) || zone.lowercased().contains(q) {
                result.append(WorldClockCity(name: city, timeZoneId: id))
                if result.count >= limit { break }
            }
        }
        return result
    }
}

// MARK: - Time text

enum WorldClockFormat {
    static func time(_ tz: TimeZone, at date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = tz
        return f.string(from: date)
    }

    /// Dawn / Morning / Noon … (the same words the homes used before)
    static func partOfDay(_ tz: TimeZone, at date: Date) -> String {
        var cal = Calendar.current
        cal.timeZone = tz
        let hour = cal.component(.hour, from: date)
        let lang = LanguageManager.shared
        if hour >= 6 && hour < 9 { return lang.localized("protected.home.earlyMorning") }
        if hour >= 9 && hour < 12 { return lang.localized("protected.home.morning") }
        if hour >= 12 && hour < 14 { return lang.localized("protected.home.noon") }
        if hour >= 14 && hour < 18 { return lang.localized("protected.home.afternoon") }
        if hour >= 18 && hour < 22 { return lang.localized("protected.home.evening") }
        return lang.localized("protected.home.lateNight")
    }

    /// "+13 h" / "−2 h" / "+5.5 h" relative to this phone
    static func offset(_ tz: TimeZone, at date: Date) -> String {
        let diff = Double(tz.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
        if diff == 0 { return "±0 h" }
        let text = diff == diff.rounded() ? String(Int(abs(diff))) : String(format: "%.1f", abs(diff))
        return "\(diff > 0 ? "+" : "−")\(text) h"
    }
}

// MARK: - The row

struct WorldClockRow: View {
    let me: WorldClockEntry?
    let family: [WorldClockEntry]
    /// Text under my own time ("I'm here" / "You're here")
    let meNote: String
    var ink: Color
    var lamp: Color

    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var settings = WorldClockSettings.shared
    @ObservedObject private var lang = LanguageManager.shared
    @State private var showSettings = false

    var body: some View {
        let entries = settings.entries(me: me, family: family)
        // Times move on by themselves (they used to stay at the minute the page opened)
        TimelineView(.everyMinute) { context in
            Button { showSettings = true } label: {
                Group {
                    if entries.count <= 4 {
                        HStack(spacing: 6) { cells(entries, at: context.date, fixedWidth: nil) }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) { cells(entries, at: context.date, fixedWidth: 84) }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .accessibilityHint(lang.localized("worldClock.hint"))
        .accessibilityIdentifier("home.worldClocks")
        .sheet(isPresented: $showSettings) {
            WorldClockSettingsView(me: me, family: family).environmentObject(coordinator)
        }
        .onAppear { settings.load() }
    }

    @ViewBuilder
    private func cells(_ entries: [WorldClockEntry], at date: Date, fixedWidth: CGFloat?) -> some View {
        ForEach(entries) { clock in
            VStack(spacing: 2) {
                Text(clock.title)
                    .font(.scaled(size: 11))
                    .foregroundStyle(ink.opacity(0.55))
                    .lineLimit(1)
                Text(WorldClockFormat.time(clock.timeZone, at: date))
                    .font(.scaled(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(clock.isMe ? lamp : ink)
                Text(clock.isMe ? meNote : WorldClockFormat.partOfDay(clock.timeZone, at: date))
                    .font(.scaled(size: 11))
                    .foregroundStyle(clock.isMe ? lamp : ink.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: fixedWidth == nil ? .infinity : nil)
            .frame(width: fixedWidth)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(clock.isMe ? lamp.opacity(0.11) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(clock.isMe ? lamp.opacity(0.4) : ink.opacity(0.13), lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Settings sheet

struct WorldClockSettingsView: View {
    let me: WorldClockEntry?
    let family: [WorldClockEntry]
    @ObservedObject private var settings = WorldClockSettings.shared
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showSearch = false

    private var list: [WorldClockCity] { settings.current(me: me, family: family) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(list) { city in
                        let tz = city.isMe == true ? (me?.timeZone ?? city.timeZone) : city.timeZone
                        WorldClockEditRow(title: title(city), timeZone: tz,
                                          removeLabel: String(format: lang.localized("worldClock.remove"), title(city))) {
                            if let i = list.firstIndex(where: { $0.id == city.id }) {
                                withAnimation { settings.remove(atOffsets: IndexSet(integer: i), me: me, family: family) }
                            }
                        }
                    }
                    .onDelete { settings.remove(atOffsets: $0, me: me, family: family) }
                    .onMove { settings.move(fromOffsets: $0, toOffset: $1, me: me, family: family) }

                    if list.count < WorldClockSettings.maxClocks {
                        Button {
                            showSearch = true
                        } label: {
                            Label(lang.localized("worldClock.add"), systemImage: "plus.circle.fill")
                        }
                        .accessibilityIdentifier("worldClock.add")
                        if let me, !list.contains(where: { $0.isMe == true }) {
                            Button {
                                settings.addMe(me, family: family)
                            } label: {
                                Label(lang.localized("worldClock.addMe"), systemImage: "location.circle.fill")
                            }
                        }
                    }
                } header: {
                    Text(lang.localized("worldClock.onHome"))
                } footer: {
                    Text(String(format: lang.localized(settings.isCustomized ? "worldClock.footer.custom" : "worldClock.footer.auto"),
                                WorldClockSettings.maxClocks))
                }

                if settings.isCustomized && !(me == nil && family.isEmpty) {
                    Section {
                        Button(lang.localized("worldClock.reset")) { settings.reset() }
                    }
                }
            }
            .navigationTitle(lang.localized("worldClock.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !list.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.localized("common.done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showSearch) {
                WorldClockCitySearch { city in
                    settings.add(city, me: me, family: family)
                    showSearch = false
                }
            }
        }
    }

    private func title(_ city: WorldClockCity) -> String {
        if city.isMe == true {
            return "\(lang.localized("protected.home.me")) · \(me?.title ?? city.name)"
        }
        if let person = city.person, person != city.name { return "\(person) · \(city.name)" }
        return city.name
    }
}

/// One clock in the sheet: a one-tap remove button (swiping or Edit → − also work;
/// they were easy to miss), the name, the offset and the time.
private struct WorldClockEditRow: View {
    let title: String
    let timeZone: TimeZone
    let removeLabel: String
    let onRemove: () -> Void
    @Environment(\.editMode) private var editMode

    var body: some View {
        HStack(spacing: 12) {
            // In Edit mode the list draws its own red − button
            if editMode?.wrappedValue.isEditing != true {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(removeLabel)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(WorldClockFormat.offset(timeZone, at: Date()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(WorldClockFormat.time(timeZone, at: Date()))
                .font(.title3.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

// MARK: - City search

struct WorldClockCitySearch: View {
    let onPick: (WorldClockCity) -> Void
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var mapResults: [WorldClockCity] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    /// Keyboard up as soon as the search opens
    @State private var searchShown = true

    private var results: [WorldClockCity] {
        var seen = Set<String>()
        return (WorldClockSettings.timeZoneMatches(query) + mapResults).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { city in
                    Button {
                        onPick(city)
                    } label: {
                        HStack {
                            Text(city.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(WorldClockFormat.time(city.timeZone, at: Date())) · \(WorldClockFormat.offset(city.timeZone, at: Date()))")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    // Plain: the List's button tint turned the city names green
                    .buttonStyle(.plain)
                }
                if searching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if query.count >= 2 && results.isEmpty {
                    Text(lang.localized("worldClock.noResults")).foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, isPresented: $searchShown, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: lang.localized("worldClock.searchPlaceholder"))
            .onChange(of: query) { _, q in search(q) }
            .navigationTitle(lang.localized("worldClock.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.localized("auth.alipay.cancel")) { dismiss() }
                }
            }
        }
    }

    /// Any city on Earth: Maps search, which also knows its time zone
    private func search(_ q: String) {
        searchTask?.cancel()
        let text = q.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { mapResults = []; searching = false; return }
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)   // wait for typing to pause
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.resultTypes = .address
            let found = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
            guard !Task.isCancelled else { return }
            mapResults = found.compactMap { item in
                guard let tz = item.timeZone else { return nil }
                let name = item.placemark.locality ?? item.name ?? tz.identifier
                return WorldClockCity(name: name, timeZoneId: tz.identifier)
            }
        }
    }
}
