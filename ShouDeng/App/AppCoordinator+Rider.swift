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

    func setHomeStyle(_ style: HomeStyle, syncToServer: Bool = true) {
        if isDemo {
            demoHomeStyle = style.rawValue
        } else {
            UserDefaults.standard.set(style.rawValue, forKey: HomeStyle.storageKey)
            // Kept on the account too, so a new phone opens on the same home
            if syncToServer {
                let api = apiClient
                Task { let _: SuccessResponse? = try? await api.put("/v1/user/me", body: HomeStyleUpdate(homeStyle: style.rawValue)) }
            }
        }
        if style == .rider { liveActivityManager.updateRider(riderCardInfo) } else { liveActivityManager.updateRider(nil) }
        // Simple home → the older-adult fall profile, unless the person chose otherwise
        applyFallProfile()
    }

    var isOnShift: Bool { riderShift != nil }

    private struct ShiftRequest: Encodable {
        let onShift: Bool
        let plannedEnd: Date?
        var watcherIds: [String]? = nil
        // Settings → Rider: late-shift alert, night "Still OK?" check
        var graceMinutes: Int? = nil
        var stillOkEveryMin: Int? = nil
        var stillOkFromHour: Int? = nil
        var stillOkToHour: Int? = nil
    }
    private struct MemberRequest: Encodable { let memberId: String }
    private struct NameRequest: Encodable { let name: String }
    private struct CodeRequest: Encodable { let code: String }
    private struct RespondRequest: Encodable { let sosEventId: String; let response: String }
    private struct CautionRequest: Encodable { let latitude: Double; let longitude: Double; let note: String; var ttlHours: Int? = nil }

    // MARK: Shift

    /// `watcherIds` nil: the watchers from last time (Siri / Shortcuts start)
    func startShift(plannedEnd: Date?, watcherIds: [String]? = nil) async {
        let shift = RiderShift(startedAt: Date(), plannedEnd: plannedEnd,
                               watcherIds: watcherIds ?? crew?.myWatcherIds)
        await MainActor.run { setRiderShift(shift) }
        locationManager.requestSingleLocation()
        do {
            let s = riderSettings
            let still = s.stillOkEveryMin > 0
            let _: SuccessResponse = try await apiClient.post("/v1/crew/shift", body: ShiftRequest(
                onShift: true, plannedEnd: plannedEnd, watcherIds: watcherIds,
                graceMinutes: s.graceMinutes,
                stillOkEveryMin: still ? s.stillOkEveryMin : nil,
                stillOkFromHour: still ? s.stillOkFromHour : nil,
                stillOkToHour: still ? s.stillOkToHour : nil))
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
        // The demo keeps its shift in memory only (it used to write the real one)
        if !isDemo {
            if let shift, let data = try? JSONEncoder().encode(shift) {
                UserDefaults.standard.set(data, forKey: "rider_shift")
            } else {
                UserDefaults.standard.removeObject(forKey: "rider_shift")
            }
        }
        liveActivityManager.updateRider(riderCardInfo)
    }

    // MARK: Crew

    func refreshCrew() async {
        do {
            let envelope: CrewEnvelope = try await apiClient.get("/v1/crew")
            await MainActor.run {
                crew = envelope.crew
                applyServerCrewPrefs(envelope.crew?.myPrefs)
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
                                                           body: CautionRequest(latitude: here.latitude, longitude: here.longitude, note: note,
                                                                                ttlHours: riderSettings.cautionHours))
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
        let s = riderSettings
        return RiderCardInfo(
            shiftStartedAt: riderShift?.startedAt,
            checkDueAt: riderShift?.plannedEnd,
            crewOnShiftNearby: crew?.members.filter { $0.onShift && ($0.distanceM ?? .max) <= 1000 }.count ?? 0,
            sosAddress: nil,
            helperName: goingName?.name,
            helperDistanceM: goingName?.distanceM,
            buttons: s.lockButtons.map(\.rawValue),
            showTimer: s.showShiftTimer,
            watcherNames: s.showWatchers ? watcherNames(riderShift?.watcherIds ?? []) : nil,
            vehicleSymbol: s.vehicle.symbol
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

    // MARK: Family watch back

    private struct GuardianIdBody: Encodable { let guardianId: String }
    private struct PersonIdBody: Encodable { let personId: String }
    private struct RespondBody: Encodable { let personId: String; let accept: Bool }
    private struct OtherIdBody: Encodable { let otherId: String }

    func fetchWatchBack() async {
        do {
            let overview: WatchBackOverview = try await apiClient.get("/v1/watch-back")
            await MainActor.run { watchBack = overview }
            // The person cared for sees the guardians they watch back on their home screen
            if userRole == .protected_, overview.guardians.contains(where: { $0.state == "active" }) {
                await fetchProtectedPersons()
            } else if userRole == .protected_ {
                await MainActor.run { protectedPersons = [] }
            }
        } catch {
            #if DEBUG
            print("[WatchBack] load failed: \(error)")
            #endif
        }
    }

    /// Person cared for: ask to watch this guardian back (they agree in their app).
    func requestWatchBack(guardianId: String) async throws {
        let _: WatchBackStateResponse = try await apiClient.post("/v1/watch-back/request", body: GuardianIdBody(guardianId: guardianId))
        await fetchWatchBack()
    }

    /// Guardian: let this person watch over me too.
    func offerWatchBack(personId: String) async throws {
        let _: WatchBackStateResponse = try await apiClient.post("/v1/watch-back/offer", body: PersonIdBody(personId: personId))
        await fetchWatchBack()
    }

    func respondWatchBack(personId: String, accept: Bool) async throws {
        let _: WatchBackStateResponse = try await apiClient.post("/v1/watch-back/respond", body: RespondBody(personId: personId, accept: accept))
        await fetchWatchBack()
    }

    func stopWatchBack(otherId: String) async throws {
        let _: SuccessResponse = try await apiClient.post("/v1/watch-back/stop", body: OtherIdBody(otherId: otherId))
        await fetchWatchBack()
    }
}
