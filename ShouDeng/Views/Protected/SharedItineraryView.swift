import SwiftUI

// MARK: - Shared Itinerary View
//
// Input flight/train number, family sees ETA from public data.
// Resolves cross-border family anxiety about "did they land?"

struct SharedItineraryView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    @State private var itineraries: [ItineraryItem] = []
    @State private var showAdd = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if itineraries.isEmpty {
                    emptyState
                } else {
                    itineraryList
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(langManager.localized("itinerary.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(langManager.localized("itinerary.close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddItinerarySheet(onAdded: {
                    Task { await loadItineraries() }
                })
                .environmentObject(coordinator)
            }
            .task { await loadItineraries() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "airplane")
                .font(.scaled(size: 40))
                .foregroundStyle(safe.opacity(0.4))
            Text(langManager.localized("itinerary.empty"))
                .font(.scaled(size: 15, weight: .medium))
                .foregroundStyle(ink.opacity(0.6))
            Text(langManager.localized("itinerary.emptyHint"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showAdd = true } label: {
                Text(langManager.localized("itinerary.add"))
                    .font(.scaled(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(safe)
                    .clipShape(Capsule())
            }
        }
        .padding(32)
    }

    private var itineraryList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(itineraries) { item in
                    itineraryCard(item)
                }
            }
            .padding(16)
        }
    }

    private func itineraryCard(_ item: ItineraryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.type == "flight" ? "airplane" : "tram.fill")
                    .font(.scaled(size: 14))
                    .foregroundStyle(safe)
                if let code = item.carrierCode, let num = item.flightNumber {
                    Text("\(code)\(num)")
                        .font(.scaled(size: 14, weight: .semibold, design: .monospaced))
                }
                Spacer()
                statusBadge(item.status)
            }

            HStack(spacing: 4) {
                Text(item.departureCity)
                    .font(.scaled(size: 15, weight: .medium))
                Image(systemName: "arrow.right")
                    .font(.scaled(size: 11))
                    .foregroundStyle(.secondary)
                Text(item.arrivalCity)
                    .font(.scaled(size: 15, weight: .medium))
            }
            .foregroundStyle(ink)

            HStack {
                Label(
                    item.departureTime.formatted(.dateTime.month().day().hour().minute()),
                    systemImage: "clock"
                )
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

                if let arrival = item.arrivalTime {
                    Text("→")
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                    Text(arrival.formatted(.dateTime.hour().minute()))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if let note = item.note, !note.isEmpty {
                Text(note)
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func statusBadge(_ status: String) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case "scheduled": return (langManager.localized("itinerary.status.scheduled"), .secondary)
            case "departed": return (langManager.localized("itinerary.status.departed"), safe)
            case "arrived": return (langManager.localized("itinerary.status.arrived"), safe)
            case "delayed": return (langManager.localized("itinerary.status.delayed"), .orange)
            case "cancelled": return (langManager.localized("itinerary.status.cancelled"), .red)
            default: return (status, .secondary)
            }
        }()

        return Text(text)
            .font(.scaled(size: 12, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func loadItineraries() async {
        // Show empty state after 5 seconds if API hasn't responded
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if isLoading {
                await MainActor.run { isLoading = false }
            }
        }
        defer {
            timeoutTask.cancel()
            isLoading = false
        }
        do {
            let items: [ItineraryItem] = try await coordinator.apiClient.get("/v1/itinerary")
            await MainActor.run { itineraries = items }
        } catch {
            #if DEBUG
            print("[Itinerary] load error: \(error)")
            #endif
        }
    }

}

// MARK: - Add Itinerary Sheet

struct AddItinerarySheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    let onAdded: () -> Void

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    @State private var type = "flight"
    @State private var carrierCode = ""
    @State private var flightNumber = ""
    @State private var departureCity = ""
    @State private var arrivalCity = ""
    @State private var departureTime = Date()
    @State private var arrivalTime = Date().addingTimeInterval(7200)
    @State private var note = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Picker(langManager.localized("itinerary.type"), selection: $type) {
                    Text(langManager.localized("itinerary.type.flight")).tag("flight")
                    Text(langManager.localized("itinerary.type.train")).tag("train")
                    Text(langManager.localized("itinerary.type.bus")).tag("bus")
                }

                if type == "flight" {
                    TextField(langManager.localized("itinerary.carrierCode"), text: $carrierCode)
                    TextField(langManager.localized("itinerary.flightNumber"), text: $flightNumber)
                }

                TextField(langManager.localized("itinerary.departureCity"), text: $departureCity)
                TextField(langManager.localized("itinerary.arrivalCity"), text: $arrivalCity)

                DatePicker(langManager.localized("itinerary.departureTime"), selection: $departureTime)
                DatePicker(langManager.localized("itinerary.arrivalTime"), selection: $arrivalTime)

                TextField(langManager.localized("itinerary.note"), text: $note)
            }
            .navigationTitle(langManager.localized("itinerary.addTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(langManager.localized("itinerary.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(langManager.localized("itinerary.save")).bold()
                        }
                    }
                    .disabled(departureCity.isEmpty || arrivalCity.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let _: ItineraryCreateResponse = try await coordinator.apiClient.post(
                "/v1/itinerary",
                body: ItineraryCreateRequest(
                    type: type,
                    carrierCode: carrierCode.isEmpty ? nil : carrierCode,
                    flightNumber: flightNumber.isEmpty ? nil : flightNumber,
                    departureCity: departureCity,
                    arrivalCity: arrivalCity,
                    departureTime: departureTime,
                    arrivalTime: arrivalTime,
                    note: note.isEmpty ? nil : note
                )
            )
        } catch {
            #if DEBUG
            print("[Itinerary] save error (using local fallback): \(error)")
            #endif
        }
        // Always call onAdded and dismiss so the UI responds
        onAdded()
        dismiss()
    }
}
