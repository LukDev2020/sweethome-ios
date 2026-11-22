import Foundation

// MARK: - Both roles: looked after and looking after family (docs/roles/ROLES.md, phase B)
//
// One account can be looked after (protected, rider included) and look after family at
// the same time. `userRole` is only the side the home shows; a switch at the top of the
// home flips it. What protects the person never depends on the side on screen: fall
// detection, location, heartbeat, the SOS button and the lock-screen SOS run whenever
// they are on the protected side (`isProtectedSide`), and SOS alerts from family arrive
// whenever they look after someone (`isGuardianSide`).
//
// Server: users.bothRoles (GET/PUT /v1/user/me); users.role keeps the home side for
// older app versions. Everything else on the server goes by guardian_links, not role.

extension AppCoordinator {

    static let bothRolesKey = "both_roles"

    /// Being looked after: protections run, whichever side is on screen
    var isProtectedSide: Bool { userRole == .protected_ || hasBothRoles }
    /// Looking after family: their SOS and status reach this phone
    var isGuardianSide: Bool { userRole == .guardian || hasBothRoles }

    /// Sign-up chose both, or Settings turned it on / off. Off keeps the side on screen.
    func setBothRoles(_ on: Bool) {
        guard hasBothRoles != on else { return }
        hasBothRoles = on
        guard !isDemo else { return }
        let api = apiClient
        Task { let _: SuccessResponse? = try? await api.put("/v1/user/me", body: BothRolesUpdate(bothRoles: on)) }
        homeSideChanged()
    }

    /// The switch at the top of the home: shows the other side straight away and tells
    /// the server (best effort — the next launch reads it back).
    func switchHomeSide(to side: UserRole) {
        guard userRole != side else { return }
        userRole = side
        currentUser?.role = side
        if let user = currentUser { localStore.saveCurrentUser(user) }
        localStore.saveUserRole(side)
        homeSideChanged()
        guard !isDemo else { return }
        let api = apiClient
        Task { let _: SuccessResponse? = try? await api.put("/v1/user/me", body: ["role": side.rawValue]) }
    }

    /// After a change of side: data for both sides, the right lock-screen card,
    /// fall detection kept on while protected.
    func homeSideChanged() {
        guard !isDemo, case .loggedIn = authState else { return }
        Task {
            if isGuardianSide { await fetchProtectedPersons() }
            if isProtectedSide {
                await fetchGuardians()
                await fetchSafeZones()
            }
            await MainActor.run {
                // The lock-screen card is the side on screen (protected / rider, or family)
                if UserDefaults.standard.bool(forKey: "lockscreen_card_enabled") {
                    liveActivityManager.endAllActivities()
                    startLiveActivityIfNeeded()
                }
                syncWidgetState()
            }
        }
        if isProtectedSide { motionService.startForegroundMonitoring() }
    }
}

/// PUT /v1/user/me { bothRoles }
struct BothRolesUpdate: Encodable { let bothRoles: Bool }
