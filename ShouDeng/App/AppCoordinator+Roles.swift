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
// Work (rides or drives for work) can go with family care: the home then has a "Work"
// side next to "My safety" — the rider home, crew, shifts — and a shift brings it up,
// its end My safety. A pure rider (home style Rider) has no separate Work side.
//
// Server: users.bothRoles and users.workRole (GET/PUT /v1/user/me); users.role keeps
// the home side for older app versions. Everything else on the server goes by
// guardian_links (and crew membership), not role.

/// The sides at the top of the home, in order: Work (rides / drives for work),
/// My safety (looked after), Family (looks after others).
enum HomeSide: String, CaseIterable {
    case work, me, family
}

extension AppCoordinator {

    static let bothRolesKey = "both_roles"
    static let workRoleKey = "work_role"
    static let workSideKey = "work_side_active"
    /// Delivery / courier rider or ride-hailing driver (the words on the Work side)
    static let workKindKey = "work_kind"

    /// The sides this account has; the switch shows when there are two or more
    var homeSides: [HomeSide] {
        var sides: [HomeSide] = []
        if hasWorkSide { sides.append(.work) }
        if isProtectedSide { sides.append(.me) }
        if isGuardianSide { sides.append(.family) }
        return sides
    }

    /// The side on screen
    var currentHomeSide: HomeSide {
        if userRole == .guardian { return .family }
        return hasWorkSide && workSideActive ? .work : .me
    }

    /// The switch at the top of the home
    func switchHome(to side: HomeSide) {
        guard side != currentHomeSide else { return }
        switch side {
        case .family:
            switchHomeSide(to: .guardian)
        case .work, .me:
            workSideActive = side == .work
            liveActivityManager.updateRider(riderCardInfo)
            if userRole != .protected_ { switchHomeSide(to: .protected_) } else { homeSideChanged() }
        }
    }

    /// Sign-up chose "Work" with family care, or Settings turned it on / off. The rider
    /// setup (crew, platforms) runs the first time it's turned on.
    func setWorkRole(_ on: Bool) {
        guard hasWorkRole != on else { return }
        hasWorkRole = on
        if !on { workSideActive = false }
        liveActivityManager.updateRider(riderCardInfo)
        guard !isDemo else { return }
        let api = apiClient
        Task { let _: SuccessResponse? = try? await api.put("/v1/user/me", body: WorkRoleUpdate(workRole: on, useCase: on ? "rider" : "personal")) }
    }

    /// "rider" (delivery, courier) or "driver" (ride-hailing): chosen on the first page
    var workKind: String { UserDefaults.standard.string(forKey: Self.workKindKey) ?? "rider" }

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
/// PUT /v1/user/me { workRole, useCase }
struct WorkRoleUpdate: Encodable { let workRole: Bool; let useCase: String }
