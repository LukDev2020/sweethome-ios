import Foundation
import CoreLocation

// MARK: - Rider mode: shift, crew, crew alerts
//
// Server: /v1/crew (shoudeng-backend/functions/src/routes/crew.ts). In the demo the
// same calls are answered by DemoStore (Kai's phone).

extension AppCoordinator {

    /// Rider home and rider SOS: the protected person chose Rider in Settings → Home
    /// screen (in the demo: Kai's phone).
    var isRiderMode: Bool {
        guard userRole == .protected_ else { return false }
        return effectiveHomeStyle == HomeStyle.rider.rawValue
    }

    /// The home style in use: the demo keeps its own (Kai's phone starts on Rider), so
    /// trying the setting there never changes the real one.
    var effectiveHomeStyle: String {
        if isDemo {
            return demoHomeStyle ?? (currentUser?.id == DemoDataset.kaiId ? HomeStyle.rider.rawValue : HomeStyle.standard.rawValue)
        }
        return UserDefaults.standard.string(forKey: HomeStyle.storageKey) ?? HomeStyle.standard.rawValue
    }

    func setHomeStyle(_ style: HomeStyle) {
        if isDemo {
            demoHomeStyle = style.rawValue
        } else {
            UserDefaults.standard.set(style.rawValue, forKey: HomeStyle.storageKey)
        }
        if style == .rider { liveActivityManager.updateRider(riderCardInfo) } else { liveActivityManager.updateRider(nil) }
    }

    var isOnShift: Bool { riderShift != nil }

    private struct ShiftRequest: Encodable { let onShift: Bool; let plannedEnd: Date?; var watcherIds: [String]? = nil }
    private struct MemberRequest: Encodable { let memberId: String }
    private struct NameRequest: Encodable { let name: String }
    private struct CodeRequest: Encodable { let code: String }
    private struct RespondRequest: Encodable { let sosEventId: String; let response: String }
    private struct CautionRequest: Encodable { let latitude: Double; let longitude: Double; let note: String }

    // MARK: Shift

    /// `watcherIds` nil: the watchers from last time (Siri / Shortcuts start)
    func startShift(plannedEnd: Date?, watcherIds: [String]? = nil) async {
        let shift = RiderShift(startedAt: Date(), plannedEnd: plannedEnd,
                               watcherIds: watcherIds ?? crew?.myWatcherIds)
        await MainActor.run { setRiderShift(shift) }
        locationManager.requestSingleLocation()
        do {
            let _: SuccessResponse = try await apiClient.post("/v1/crew/shift",
                                                             body: ShiftRequest(onShift: true, plannedEnd: plannedEnd, watcherIds: watcherIds))
        } catch {
            #if DEBUG
            print("[Rider] shift start not sent: \(error)")
            #endif
        }
        await refreshCrew()
    }

    func endShift() async {
        await MainActor.run { setRiderShift(nil) }
        do {
            let _: SuccessResponse = try await apiClient.post("/v1/crew/shift", body: ShiftRequest(onShift: false, plannedEnd: nil))
        } catch {
            #if DEBUG
            print("[Rider] shift end not sent: \(error)")
            #endif
        }
    }

    @MainActor
    private func setRiderShift(_ shift: RiderShift?) {
        riderShift = shift
        if let shift, let data = try? JSONEncoder().encode(shift) {
            UserDefaults.standard.set(data, forKey: "rider_shift")
        } else {
            UserDefaults.standard.removeObject(forKey: "rider_shift")
        }
        liveActivityManager.updateRider(riderCardInfo)
    }

    // MARK: Crew

    func refreshCrew() async {
        do {
            let envelope: CrewEnvelope = try await apiClient.get("/v1/crew")
            await MainActor.run {
                crew = envelope.crew
                liveActivityManager.updateRider(riderCardInfo)
            }
        } catch {
            #if DEBUG
            print("[Rider] crew load failed: \(error)")
            #endif
        }
    }

    func createCrew(name: String) async throws {
        let envelope: CrewEnvelope = try await apiClient.post("/v1/crew", body: NameRequest(name: name))
        await MainActor.run { crew = envelope.crew }
    }

    func joinCrew(code: String) async throws {
        let envelope: CrewEnvelope = try await apiClient.post("/v1/crew/join", body: CodeRequest(code: code))
        await MainActor.run {
            crew = envelope.crew
            pendingCrewCode = nil
        }
    }

    /// Watch the shifts of a crew mate who watches mine.
    func watchBack(_ member: CrewMember) async throws {
        let _: SuccessResponse = try await apiClient.post("/v1/crew/watch-back", body: MemberRequest(memberId: member.id))
        await refreshCrew()
    }

    /// Names of who watches this shift (crew mates and family)
    func watcherNames(_ ids: [String]) -> [String] {
        ids.compactMap { id in
            crew?.members.first(where: { $0.id == id })?.name
                ?? myGuardians.first(where: { $0.user.id == id || $0.id == id })?.user.displayName
        }
    }

    func leaveCrew() async throws {
        let _: SuccessResponse = try await apiClient.post("/v1/crew/leave", body: [String: String]())
        await MainActor.run { crew = nil }
    }

    /// "Bike tampered with here" — a caution spot the crew sees for the night.
    func addCaution(note: String) async throws {
        guard let here = locationManager.bestAvailableLocation?.coordinate else { throw APIError.validation("no location yet") }
        let _: [String: String] = try await apiClient.post("/v1/crew/caution",
                                                           body: CautionRequest(latitude: here.latitude, longitude: here.longitude, note: note))
        await refreshCrew()
    }

    // MARK: Crew alerts (a crew mate's SOS)

    func refreshCrewAlerts() async {
        do {
            let envelope: CrewAlertsEnvelope = try await apiClient.get("/v1/crew/alerts")
            await MainActor.run { crewAlerts = envelope.alerts }
        } catch {
            #if DEBUG
            print("[Rider] crew alerts load failed: \(error)")
            #endif
        }
    }

    func respondToCrewAlert(_ alert: CrewAlert, going: Bool) async throws {
        let _: SuccessResponse = try await apiClient.post("/v1/crew/respond",
                                                         body: RespondRequest(sosEventId: alert.sosEventId, response: going ? "going" : "cant_help"))
        await refreshCrewAlerts()
    }

    // MARK: Lock-screen card

    /// What the rider version of the lock-screen card shows.
    var riderCardInfo: RiderCardInfo? {
        guard isRiderMode else { return nil }
        let goingName = ownSOSStatus?.crewResponses?.first(where: \.isGoing)
        return RiderCardInfo(
            shiftStartedAt: riderShift?.startedAt,
            checkDueAt: riderShift?.plannedEnd,
            crewOnShiftNearby: crew?.members.filter { $0.onShift && ($0.distanceM ?? .max) <= 1000 }.count ?? 0,
            sosAddress: nil,
            helperName: goingName?.name,
            helperDistanceM: goingName?.distanceM
        )
    }

    /// The street, for whoever reads the card or calls during the SOS
    var riderCardWithAddress: RiderCardInfo? {
        var info = riderCardInfo
        info?.sosAddress = riderSOSAddress
        return info
    }

    /// Looks up the street where the SOS started, then puts it on the card.
    func updateRiderCardForSOS() {
        liveActivityManager.updateRider(riderCardWithAddress)
        guard let location = locationManager.bestAvailableLocation else { return }
        Task {
            let marks = try? await CLGeocoder().reverseGeocodeLocation(
                location, preferredLocale: Locale(identifier: LanguageManager.shared.current.rawValue))
            guard let mark = marks?.first else { return }
            let street = [mark.thoroughfare, mark.subLocality ?? mark.locality].compactMap { $0 }.joined(separator: ", ")
            await MainActor.run {
                riderSOSAddress = street.isEmpty ? mark.name : street
                liveActivityManager.updateRider(riderCardWithAddress)
            }
        }
    }

    /// Demo only (Kai's phone): Ahmed calls SOS so the crew alert can be tried.
    func demoCrewSOS() {
        guard isDemo, let id = DemoURLProtocol.store?.practiceCrewSOS() else { return }
        Task {
            await refreshCrewAlerts()
            await MainActor.run { pendingCrewAlertId = id }
        }
    }
}
