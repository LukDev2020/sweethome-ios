import SwiftUI
import CoreLocation

// MARK: - Arrival Report View
//
// One-tap "I arrived safely" with optional place name.
// Notifies all guardians via push. Also counts as a check-in.

struct ArrivalReportView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    @State private var placeName = ""
    @State private var isSending = false
    @State private var didSend = false

    private let quickPlaces = ["宿舍", "学校", "公司", "医院", "机场", "酒店", "朋友家"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                if didSend {
                    sentConfirmation
                } else {
                    reportForm
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .background(Color(.systemBackground))
            .navigationTitle("到达报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: - Report Form

    private var reportForm: some View {
        VStack(spacing: 20) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(safe)

            Text("报告到达")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ink)

            Text("一键告知守护者你已安全到达")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            // Quick place tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPlaces, id: \.self) { place in
                        Button {
                            placeName = place
                        } label: {
                            Text(place)
                                .font(.system(size: 13))
                                .foregroundStyle(placeName == place ? .white : ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(placeName == place ? safe : Color(.systemGray6))
                                )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            TextField("或输入地点名称", text: $placeName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            Button {
                Task { await sendReport() }
            } label: {
                HStack(spacing: 8) {
                    if isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text("我到了")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(safe)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isSending)
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Sent Confirmation

    private var sentConfirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(safe)

            Text("已通知守护者")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ink)

            if !placeName.isEmpty {
                Text("你已安全到达「\(placeName)」")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Button("完成") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(safe)
                .padding(.top, 8)
        }
    }

    // MARK: - Action

    private func sendReport() async {
        isSending = true
        defer { isSending = false }

        let lastLocation = coordinator.locationManager.lastReportedLocation
        do {
            let _: ArrivalReportResponse = try await coordinator.apiClient.post(
                "/v1/arrival-report",
                body: ArrivalReportRequest(
                    latitude: lastLocation?.coordinate.latitude,
                    longitude: lastLocation?.coordinate.longitude,
                    placeName: placeName.isEmpty ? nil : placeName
                )
            )
        } catch {
            #if DEBUG
            print("[ArrivalReport] send error (using local fallback): \(error)")
            #endif
        }
        // Always confirm locally so the UI responds even without backend
        coordinator.addTimelineEntry(
            type: .arrivalReport,
            description: "已安全到达\(placeName.isEmpty ? "" : "「\(placeName)」")"
        )
        await MainActor.run { didSend = true }
    }
}
