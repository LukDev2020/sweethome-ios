import UIKit
import CoreLocation

// MARK: - Lock-screen card: emergency features
//
// The card's buttons (Shared/LiveActivityIntents.swift) queue an action in the App
// Group and wake the app, which acts here. The card shows:
// - the running countdown (safety timer or home timer) with +15 min / I'm here
// - during my SOS: how far the alert got (from GET /v1/sos/active); after a fall, or
//   two minutes without me opening the app, the bystander version (medical info,
//   address, call the emergency number / the family)
// - for a guardian: the SOS of someone they look after, with Call / On my way / Directions

extension AppCoordinator {

    /// Seconds without the person opening the app before the SOS card turns to a bystander
    static let bystanderDelay: UInt64 = 120

    // MARK: Card buttons

    /// Actions that don't need a full sign-in round trip (and must not wait for it):
    /// silent SOS, fake call. Called before the signed-in actions.
    func processLockScreenEmergencyActions() {
        for action in WidgetDataStore.takePendingActions([.armSilentSOS, .fakeCall]) {
            switch action {
            case .armSilentSOS:
                let until = WidgetDataStore.silentSOSArmedUntil() ?? Date().addingTimeInterval(WidgetDataStore.silentSOSWindow)
                liveActivityManager.setSilentSOSArmed(until: until)
                // Back to "Silent SOS" if no second tap comes
                let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "silent-sos.arm")
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64((WidgetDataStore.silentSOSWindow + 0.5) * 1_000_000_000))
                    if WidgetDataStore.silentSOSArmedUntil() == nil { self?.liveActivityManager.setSilentSOSArmed(until: nil) }
                    if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
                }
            case .fakeCall:
                startFakeCallFromLockScreen()
            default:
                break
            }
        }
        // The silent SOS needs who I am; it stays queued until the session is back
        if authManager.currentUserId != nil, !WidgetDataStore.takePendingActions([.silentSOS]).isEmpty {
            sendSilentSOSFromLockScreen()
        }
    }

    /// Second tap on "Silent SOS": an SOS with nothing on this phone's screen or card
    /// (someone may be watching). Guardians get it like any other SOS.
    func sendSilentSOSFromLockScreen() {
        guard userRole == .protected_ else { return }
        triggerSOS(method: .widgetTap, clientSOSId: nil, silent: true)
        liveActivityManager.markSilentSOSSent(Date())
    }

    /// "Fake call": the incoming call comes after the delay chosen in Settings → Fake
    /// call; the app is kept running until then.
    func startFakeCallFromLockScreen() {
        let service = FakeCallService.shared
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "fake-call")
        service.scheduleCall()
        let wait = service.selectedDelay.timeInterval + 5
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }
    }

    /// Countdown "+15 min": the safety timer if it runs, else the home timer (whose
    /// deadline lives on the server).
    func extendCountdownFromLockScreen() {
        let safety = DeadManSwitchService.shared
        if safety.isActive {
            safety.extend(by: .min15)
            refreshLiveActivityTimer()
            return
        }
        guard let home = homeTimerForWidget else { return }
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "home-timer.extend")
        Task { @MainActor [weak self] in
            defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }
            guard let self else { return }
            do {
                let response: HomeTimerExtendResponse = try await self.apiClient.post(
                    "/v1/home-timer/extend", body: HomeTimerExtendRequest(minutes: 15))
                // Only a deadline the server took goes on the card
                self.setHomeTimerForWidget(deadline: response.deadline, label: home.label)
            } catch {
                #if DEBUG
                print("[LockScreen] home timer extend failed: \(error)")
                #endif
            }
        }
    }

    /// Countdown "I'm here": ends whichever countdown runs and checks in.
    func arrivedFromLockScreen() {
        let safety = DeadManSwitchService.shared
        if safety.isActive {
            safety.cancel()
        } else {
            apiClient.postQueued("/v1/home-timer/dismiss", body: EmptyBody())
            setHomeTimerForWidget(deadline: nil, label: nil)
        }
        performCheckIn(note: LanguageManager.shared.localized("widget.arrived.note"))
        refreshLiveActivityTimer()
    }

    // MARK: Countdown on the card

    /// Puts the running countdown on the card: the safety timer first, else the home timer.
    func refreshLiveActivityTimer() {
        guard !isDemo, userRole == .protected_ else { return }
        let safety = DeadManSwitchService.shared
        if let deadline = safety.runningDeadline {
            liveActivityManager.updateProtectedTimer(
                deadline: deadline,
                startedAt: deadline.addingTimeInterval(-TimeInterval(safety.totalSeconds)),
                kind: "safety", label: nil)
        } else if let home = homeTimerForWidget, home.deadline > Date() {
            liveActivityManager.updateProtectedTimer(
                deadline: home.deadline, startedAt: homeTimerStartedAt, kind: "home",
                label: home.label.isEmpty ? nil : home.label)
        } else {
            liveActivityManager.updateProtectedTimer(deadline: nil, label: nil)
        }
    }

    // MARK: My SOS on the card

    /// Called when an SOS starts: the card shows it (not for a silent / duress SOS).
    func showSOSOnCard(method: SOSTriggerMethod, startedAt: Date) {
        sosCardAddress = nil
        // After a fall the person may not be able to answer: bystander card right away
        sosCardBystander = method == .fallDetection
        liveActivityManager.triggerSOS(localEmergencyNumber: localEmergencyNumber, startedAt: startedAt,
                                       bystander: sosCardBystander, demo: isDemo)
        if !sosCardBystander { scheduleBystanderCard() }
        guard !isDemo, let location = locationManager.bestAvailableLocation else { return }
        Task { @MainActor [weak self] in
            let street = await Self.streetAddress(of: location)
            guard let self, self.activeSOSEvent != nil else { return }
            self.sosCardAddress = street
            self.updateOwnSOSCard()
        }
    }

    /// The card's SOS from what the server reports (`ownSOSStatus`).
    func updateOwnSOSCard() {
        guard let event = activeSOSEvent, !sosConcealed, !event.triggerMethod.isSilent, !sosCardSilent else { return }
        let status = ownSOSStatus
        liveActivityManager.updateOwnSOS(.init(
            startedAt: event.triggeredAt,
            guardiansNotified: status?.guardiansNotified ?? 0,
            callsPlaced: status?.callsPlaced ?? 0,
            acknowledgedByName: status?.acknowledgedByName,
            nextStep: status?.nextStep,
            nextStepAt: status?.nextStepAt,
            address: sosCardAddress,
            bystander: sosCardBystander
        ))
    }

    /// Two minutes after the SOS (or after the app last went to the background during
    /// it) with the app not opened: the card speaks to whoever finds the phone.
    func scheduleBystanderCard() {
        bystanderTask?.cancel()
        guard activeSOSEvent != nil, !sosConcealed, !sosCardSilent, !sosCardBystander else { return }
        bystanderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.bystanderDelay * 1_000_000_000)
            guard let self, !Task.isCancelled, self.activeSOSEvent != nil,
                  UIApplication.shared.applicationState != .active else { return }
            self.sosCardBystander = true
            self.updateOwnSOSCard()
        }
    }

    /// The person opened the app during the SOS: they can answer, back to their card.
    func personReturnedDuringSOS() {
        bystanderTask?.cancel()
        bystanderTask = nil
        guard activeSOSEvent != nil, sosCardBystander else { return }
        sosCardBystander = false
        updateOwnSOSCard()
    }

    /// First guardian with a phone number (on duty first), for the bystander's "Call …"
    var familyContactForCard: (name: String, phone: String)? {
        let withPhone = myGuardians.filter { !($0.user.phone ?? "").isEmpty }
        guard let g = withPhone.first(where: \.isOnDuty) ?? withPhone.first, let phone = g.user.phone else { return nil }
        return (g.user.displayName, phone)
    }

    // MARK: Guardian: SOS on the card

    /// The newest SOS among the people I look after goes on the card (nil clears it).
    func refreshGuardianSOSCard() {
        guard !isDemo, userRole == .guardian else { return }
        guard let (personId, sos) = guardianSOS.max(by: { ($0.value.triggeredAt ?? .distantPast) < ($1.value.triggeredAt ?? .distantPast) }) else {
            guardianCardSOSId = nil
            liveActivityManager.updateGuardianSOS(nil)
            return
        }
        guardianCardSOSId = sos.sosEventId
        let person = protectedPersons.first { $0.id == personId }
        let myId = authManager.currentUserId ?? currentUser?.id
        let target = sos.trail?.last.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
            ?? sos.latitude.flatMap { lat in sos.longitude.map { CLLocation(latitude: lat, longitude: $0) } }
        let me = locationManager.bestAvailableLocation
        let distance = target.flatMap { t in me.map { Int($0.distance(from: t)) } }
        let key = target.map { "\(sos.sosEventId)@\(Int($0.coordinate.latitude * 1000)),\(Int($0.coordinate.longitude * 1000))" }
        let info = GuardianActivityAttributes.SOSCardInfo(
            sosEventId: sos.sosEventId,
            personName: sos.personName.isEmpty ? (person?.user.displayName ?? "") : sos.personName,
            initial: person?.user.avatarInitial ?? String(sos.personName.prefix(1)),
            startedAt: sos.triggeredAt ?? Date(),
            batteryLevel: sos.batteryLevel,
            address: key.flatMap { guardianSOSAddresses[$0] },
            distanceMeters: distance,
            locationAt: sos.locationUpdatedAt ?? sos.triggeredAt,
            latitude: target?.coordinate.latitude,
            longitude: target?.coordinate.longitude,
            phone: person?.user.phone,
            acknowledgedByName: sos.acknowledgedByName,
            acknowledgedByMe: (sos.acknowledgedBy != nil && sos.acknowledgedBy == myId) || guardianAckSent.contains(sos.sosEventId)
        )
        liveActivityManager.updateGuardianSOS(info)
        // Street name once per place
        if let key, let target, guardianSOSAddresses[key] == nil {
            Task { @MainActor [weak self] in
                guard let street = await Self.streetAddress(of: target), let self else { return }
                self.guardianSOSAddresses[key] = street
                self.refreshGuardianSOSCard()
            }
        }
    }

    /// Guardian card "On my way": acknowledge the SOS on the card (stops the automatic
    /// calls, tells the person and the other guardians).
    func acknowledgeSOSFromLockScreen() {
        guard let sosId = guardianCardSOSId else { return }
        // On the card straight away; the server's answer follows
        guardianAckSent.insert(sosId)
        refreshGuardianSOSCard()
        handleSOSTakenOver(sosId: sosId)
    }

    // MARK: Helpers

    /// "Rue Sainte-Catherine, Ville-Marie" for a place (nil if the lookup fails)
    static func streetAddress(of location: CLLocation) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(
            location, preferredLocale: Locale(identifier: LanguageManager.shared.current.rawValue))
        guard let mark = marks?.first else { return nil }
        let street = [[mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " "),
                      mark.subLocality ?? mark.locality ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return street.isEmpty ? mark.name : street
    }
}
