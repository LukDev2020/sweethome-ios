import SwiftUI

// MARK: - Shared Itinerary View
//
// Input flight/train number, family sees ETA from public data.
// Resolves cross-border family anxiety about "did they land?"

struct SharedItineraryView: View {
    @EnvironmentObject var coordinator: AppCoordinator
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
            .navigationTitle("共享行程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
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
                .font(.system(size: 40))
                .foregroundStyle(safe.opacity(0.4))
            Text("还没有共享行程")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ink.opacity(0.6))
            Text("添加航班或车次，家人可以看到你的行程状态")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showAdd = true } label: {
                Text("添加行程")
                    .font(.system(size: 14, weight: .medium))
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
                    .font(.system(size: 14))
                    .foregroundStyle(safe)
                if let code = item.carrierCode, let num = item.flightNumber {
                    Text("\(code)\(num)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                }
                Spacer()
                statusBadge(item.status)
            }

            HStack(spacing: 4) {
                Text(item.departureCity)
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(item.arrivalCity)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(ink)

            HStack {
                Label(
                    item.departureTime.formatted(.dateTime.month().day().hour().minute()),
                    systemImage: "clock"
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                if let arrival = item.arrivalTime {
                    Text("→")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(arrival.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if let note = item.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 12))
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
            case "scheduled": return ("计划中", .secondary)
            case "departed": return ("已出发", safe)
            case "arrived": return ("已到达", safe)
            case "delayed": return ("延误", .orange)
            case "cancelled": return ("取消", .red)
            default: return (status, .secondary)
            }
        }()

        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func loadItineraries() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items: [ItineraryItem] = try await coordinator.apiClient.get("/v1/itinerary")
            await MainActor.run { itineraries = items }
        } catch {
            #if DEBUG
            print("[Itinerary] load error (using local fallback): \(error)")
            // Show mock data in dev mode so the UI is demonstrable
            if coordinator.devBypassLogin {
                await MainActor.run {
                    itineraries = Self.devMockItineraries
                }
            }
            #endif
        }
    }

    #if DEBUG
    private static let devMockItineraries: [ItineraryItem] = [
        ItineraryItem(
            id: "mock-1", userId: "dev_local_user", displayName: "我",
            type: "flight", carrierCode: "CA", flightNumber: "981",
            departureCity: "北京", arrivalCity: "多伦多",
            departureTime: Date().addingTimeInterval(86400),
            arrivalTime: Date().addingTimeInterval(86400 + 13 * 3600),
            note: "经停温哥华", status: "scheduled"
        ),
        ItineraryItem(
            id: "mock-2", userId: "dev_local_user", displayName: "我",
            type: "train", carrierCode: nil, flightNumber: nil,
            departureCity: "上海", arrivalCity: "北京",
            departureTime: Date().addingTimeInterval(-3600),
            arrivalTime: Date().addingTimeInterval(3600 * 4),
            note: nil, status: "departed"
        ),
    ]
    #endif
}

// MARK: - Add Itinerary Sheet

struct AddItinerarySheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
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
                Picker("类型", selection: $type) {
                    Text("航班").tag("flight")
                    Text("火车").tag("train")
                    Text("大巴").tag("bus")
                }

                if type == "flight" {
                    TextField("航空公司代码 (如 CA)", text: $carrierCode)
                    TextField("航班号 (如 981)", text: $flightNumber)
                }

                TextField("出发城市", text: $departureCity)
                TextField("到达城市", text: $arrivalCity)

                DatePicker("出发时间", selection: $departureTime)
                DatePicker("预计到达", selection: $arrivalTime)

                TextField("备注 (可选)", text: $note)
            }
            .navigationTitle("添加行程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存").bold()
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
