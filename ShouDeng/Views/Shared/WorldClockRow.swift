import SwiftUI
import MapKit

// MARK: - World clocks (home screen, both roles)
//
// The row under the map: my time first, then the family (from where each person
// is), then any cities the person added. Tap it to choose: hide family members
// you don't need, add other cities (up to 4), reorder or remove them.
//
// Apple has no world-clock API an app can use (the Clock app's list is private),
// so cities come from the time-zone database (instant, offline) and Maps search
// (any city; MKMapItem gives its time zone). Choices stay on this phone; the demo
// keeps its own in memory.

struct WorldClockCity: Codable, Hashable, Identifiable {
    var name: String
    var timeZoneId: String
    var id: String { "\(timeZoneId)|\(name)" }
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
    static let maxCities = 4
    private static let storageKey = "world_clock_settings_v1"

    private struct Stored: Codable {
        var hiddenMemberIds: [String] = []
        var cities: [WorldClockCity] = []
    }

    @Published private(set) var hiddenMemberIds: Set<String> = []
    @Published private(set) var cities: [WorldClockCity] = []

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
            hiddenMemberIds = Set(newValue.hiddenMemberIds)
            cities = newValue.cities
        }
    }

    /// Re-read (the demo started or ended)
    func load() {
        if !ExploreMode.isActive { demoStore = nil }
        let s = stored
        hiddenMemberIds = Set(s.hiddenMemberIds)
        cities = s.cities
    }

    func setMember(_ id: String, shown: Bool) {
        var s = stored
        s.hiddenMemberIds.removeAll { $0 == id }
        if !shown { s.hiddenMemberIds.append(id) }
        stored = s
    }

    /// false when full or already there
    @discardableResult
    func add(_ city: WorldClockCity) -> Bool {
        var s = stored
        guard s.cities.count < Self.maxCities, !s.cities.contains(where: { $0.id == city.id }),
              TimeZone(identifier: city.timeZoneId) != nil else { return false }
        s.cities.append(city)
        stored = s
        return true
    }

    func remove(atOffsets offsets: IndexSet) {
        var s = stored
        s.cities.remove(atOffsets: offsets)
        stored = s
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var s = stored
        s.cities.move(fromOffsets: source, toOffset: destination)
        stored = s
    }

    /// The row: me, the family members not hidden, then the added cities
    func entries(me: WorldClockEntry?, family: [WorldClockEntry]) -> [WorldClockEntry] {
        var result: [WorldClockEntry] = me.map { [$0] } ?? []
        result += family.filter { !hiddenMemberIds.contains($0.id) }
        result += cities.map { WorldClockEntry(id: "city:\($0.id)", title: $0.name, timeZone: $0.timeZone, isMe: false) }
        return result
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
            WorldClockSettingsView(family: family).environmentObject(coordinator)
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
    let family: [WorldClockEntry]
    @ObservedObject private var settings = WorldClockSettings.shared
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            List {
                if !family.isEmpty {
                    Section {
                        ForEach(family) { member in
                            Toggle(isOn: Binding(get: { !settings.hiddenMemberIds.contains(member.id) },
                                                 set: { settings.setMember(member.id, shown: $0) })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.person.map { $0 == member.title ? $0 : "\($0) · \(member.title)" } ?? member.title)
                                    Text("\(WorldClockFormat.time(member.timeZone, at: Date())) · \(WorldClockFormat.offset(member.timeZone, at: Date()))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text(lang.localized("worldClock.family"))
                    } footer: {
                        Text(lang.localized("worldClock.familyFooter"))
                    }
                }

                Section {
                    ForEach(settings.cities) { city in
                        HStack {
                            Text(city.name)
                            Spacer()
                            Text("\(WorldClockFormat.time(city.timeZone, at: Date())) · \(WorldClockFormat.offset(city.timeZone, at: Date()))")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { settings.remove(atOffsets: $0) }
                    .onMove { settings.move(fromOffsets: $0, toOffset: $1) }

                    if settings.cities.count < WorldClockSettings.maxCities {
                        Button {
                            showSearch = true
                        } label: {
                            Label(lang.localized("worldClock.add"), systemImage: "plus.circle.fill")
                        }
                        .accessibilityIdentifier("worldClock.add")
                    }
                } header: {
                    Text(lang.localized("worldClock.cities"))
                } footer: {
                    Text(String(format: lang.localized("worldClock.citiesFooter"), WorldClockSettings.maxCities))
                }
            }
            .navigationTitle(lang.localized("worldClock.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !settings.cities.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.localized("common.done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showSearch) {
                WorldClockCitySearch { city in
                    settings.add(city)
                    showSearch = false
                }
            }
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
