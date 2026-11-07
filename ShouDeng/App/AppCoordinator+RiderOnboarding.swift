import UIKit
import ActivityKit
import CoreMotion

// MARK: - Rider onboarding (docs/rider-onboarding-plan.md)
//
// A rider is a protected person with Rider mode on — no third role. They arrive by
// choosing "I deliver or drive for work" at sign-up, through a crew invite link, a
// partner link, or Settings → Home screen → Rider. All of them go through the same
// rider setup (RiderSetupView): where you ride → crew → someone at home → SOS without
// looking → permissions → plan & rider notice → ready / first shift.

/// What the sign-up should start as (a crew / partner link chose Rider).
struct SignupIntent: Equatable {
    var rider: Bool
    var partnerCode: String? = nil
}

enum RiderSetupStep: Int, CaseIterable {
    case ride, crew, home, sos, permissions, plan, ready
}

struct RiderProfileInfo: Codable, Equatable {
    struct Milestones: Codable, Equatable {
        var crewAt: Date?
        var firstShiftAt: Date?
        var lockCardAt: Date?
        var setupDoneAt: Date?
    }
    struct RiderFree: Codable, Equatable {
        var included: [String]
        var active: Bool
    }
    var city: String?
    var platforms: [String]
    var partnerOrg: String?
    var onboardedAt: Date?
    var milestones: Milestones?
    var riderFree: RiderFree?
}

struct HomeStyleUpdate: Encodable { let homeStyle: String }

/// PUT /v1/user/me: rider fields only (others untouched)
struct RiderProfileUpdate: Encodable {
    struct Profile: Encodable {
        var city: String?
        var platforms: [String]?
        var milestones: [String: Bool]?
    }
    var useCase: String?
    var homeStyle: String?
    var riderProfile: Profile?
}

struct PartnerPreview: Decodable { let name: String }
struct PartnerJoinRequest: Encodable { let shareStats: Bool }
struct PartnerJoinResponse: Decodable { let name: String; let shareStats: Bool }

/// What a rider still needs before a shift is fully covered.
struct RiderChecklist: Equatable {
    var crew: Bool
    var watcher: Bool
    var lockCard: Bool
    var email: Bool
    var faceID: Bool

    /// The safety essentials (the "Finish setting up" card shows while any is missing)
    var essentialsDone: Bool { crew && watcher && lockCard }
    var doneCount: Int { [crew, watcher, lockCard, email, faceID].filter { $0 }.count }
    static let total = 5
}

/// Platforms offered as chips (server: riderProfile.PLATFORMS). Shown by local relevance.
enum RiderPlatforms {
    static let all = ["ubereats", "doordash", "deliveroo", "menulog", "meituan", "eleme", "uber", "didi",
                      "grab", "foodpanda", "glovo", "lyft", "other"]

    static func forCountry(_ cc: String) -> [String] {
        let local: [String]
        switch cc.uppercased() {
        case "CN": local = ["meituan", "eleme", "didi"]
        case "AU": local = ["ubereats", "doordash", "menulog", "deliveroo", "uber", "didi"]
        case "GB", "IE", "FR": local = ["deliveroo", "ubereats", "glovo", "uber"]
        case "US", "CA": local = ["doordash", "ubereats", "uber", "lyft"]
        case "SG", "MY", "TH", "PH", "TW", "HK": local = ["grab", "foodpanda", "ubereats", "deliveroo"]
        case "JP": local = ["ubereats", "didi"]
        default: local = []
        }
        return local + all.filter { !local.contains($0) && $0 != "other" } + ["other"]
    }

    static func name(_ id: String) -> String {
        switch id {
        case "ubereats": return "Uber Eats"
        case "doordash": return "DoorDash"
        case "deliveroo": return "Deliveroo"
        case "menulog": return "Menulog"
        case "meituan": return LanguageManager.shared.current.isChinese ? "美团" : "Meituan"
        case "eleme": return LanguageManager.shared.current.isChinese ? "饿了么" : "Ele.me"
        case "uber": return "Uber"
        case "didi": return LanguageManager.shared.current.isChinese ? "滴滴" : "DiDi"
        case "grab": return "Grab"
        case "foodpanda": return "foodpanda"
        case "glovo": return "Glovo"
        case "lyft": return "Lyft"
        default: return LanguageManager.shared.localized("rider.setup.platform.other")
        }
    }
}

extension AppCoordinator {

    static let riderSetupDoneKey = "rider_setup_done"

    /// Rider setup finished on this phone or on the account
    var riderSetupDone: Bool {
        if isDemo { return demoRiderSetupDone || currentUser?.id == DemoDataset.kaiId }
        return UserDefaults.standard.bool(forKey: Self.riderSetupDoneKey) || riderProfile?.milestones?.setupDoneAt != nil
    }

    var riderChecklist: RiderChecklist {
        RiderChecklist(
            crew: crew != nil,
            watcher: !myGuardians.isEmpty,
            lockCard: UserDefaults.standard.bool(forKey: "lockscreen_card_enabled") && ActivityAuthorizationInfo().areActivitiesEnabled,
            email: !(currentUser?.email ?? "").isEmpty,
            faceID: BiometricAuthManager.shared.isEnabled
        )
    }

    /// Open the rider setup (sign-up, Settings, a link, the "Finish setting up" card).
    func beginRiderSetup(at step: RiderSetupStep = .ride) {
        guard userRole == .protected_ else { return }
        riderSetupStartStep = step
        if !isRiderMode { setHomeStyle(.rider) }
        showRiderSetup = true
    }

    func finishRiderSetup() {
        showRiderSetup = false
        guard !isDemo else { demoRiderSetupDone = true; return }
        UserDefaults.standard.set(true, forKey: Self.riderSetupDoneKey)
        saveRiderProfile(.init(riderProfile: .init(milestones: ["setupDone": true])))
    }

    /// Account created: remember why they came, and riders go straight to their setup.
    func completeSignup(asRider rider: Bool) {
        guard !isDemo else { return }
        saveRiderProfile(.init(useCase: rider ? "rider" : (userRole == .guardian ? "guardian" : "personal")))
        if rider {
            setHomeStyle(.rider)
            beginRiderSetup(at: .ride)
        }
    }

    func saveRiderProfile(_ update: RiderProfileUpdate) {
        guard !isDemo else { return }
        let api = apiClient
        Task { let _: SuccessResponse? = try? await api.put("/v1/user/me", body: update) }
    }

    /// GET /v1/user/me: the home and rider setup follow the account to a new phone.
    func applyServerRiderFields(_ profile: UserProfileResponse) {
        guard !isDemo else { return }
        riderProfile = profile.riderProfile
        let local = UserDefaults.standard.string(forKey: HomeStyle.storageKey)
        if local == nil, let serverStyle = profile.homeStyle.flatMap(HomeStyle.init(rawValue:)) {
            setHomeStyle(serverStyle, syncToServer: false)
        }
        if profile.riderProfile?.milestones?.setupDoneAt != nil {
            UserDefaults.standard.set(true, forKey: Self.riderSetupDoneKey)
        }
    }

    // MARK: Links

    /// A crew link / QR: riders join (Rider mode turns on); a guardian is told crews are for riders.
    func handleCrewLink(code: String) {
        if userRole == .guardian {
            showInfoAlert(title: "rider.link.guardian.title", message: "rider.link.guardian.body")
            return
        }
        pendingCrewCode = code
        if !riderSetupDone { beginRiderSetup(at: .crew) }
    }

    /// A partner / "for riders" link while signed in.
    func handleRiderStartLink(partnerCode: String?) {
        if userRole == .guardian {
            showInfoAlert(title: "rider.link.guardian.title", message: "rider.link.guardian.body")
            return
        }
        pendingSignupIntent = SignupIntent(rider: true, partnerCode: partnerCode)
        beginRiderSetup(at: .ride)
    }

    /// After sign-in: a link chose Rider (sign-up handles its own case in completeSignup).
    func applyPendingRiderIntent() {
        guard !isDemo, !showRiderSetup else { return }
        if pendingCrewCode != nil, userRole == .guardian {
            pendingCrewCode = nil
            showInfoAlert(title: "rider.link.guardian.title", message: "rider.link.guardian.body")
            return
        }
        guard pendingSignupIntent?.rider == true || pendingCrewCode != nil, userRole == .protected_ else { return }
        if !riderSetupDone {
            beginRiderSetup(at: pendingCrewCode != nil && pendingSignupIntent?.partnerCode == nil ? .crew : .ride)
        } else if !isRiderMode {
            setHomeStyle(.rider)
        }
    }

    func previewPartner(code: String) async -> String? {
        let preview: PartnerPreview? = try? await apiClient.get("/v1/org/partner/\(code)")
        return preview?.name
    }

    func joinPartner(code: String, shareStats: Bool) async -> Bool {
        let r: PartnerJoinResponse? = try? await apiClient.post("/v1/org/partner/\(code)/join", body: PartnerJoinRequest(shareStats: shareStats))
        return r != nil
    }

    private func showInfoAlert(title: String, message: String) {
        let L = LanguageManager.shared
        let alert = UIAlertController(title: L.localized(title), message: L.localized(message), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L.localized("common.ok"), style: .default))
        Self.topViewController()?.present(alert, animated: true)
    }

    // MARK: A shift left running

    /// Over half an hour past its planned end, or 14 h with no planned end.
    static func shiftLooksForgotten(_ shift: RiderShift?, now: Date = Date()) -> Bool {
        guard let shift else { return false }
        if let end = shift.plannedEnd { return now.timeIntervalSince(end) > 30 * 60 }
        return now.timeIntervalSince(shift.startedAt) > 14 * 3600
    }
}

// MARK: - "Riding for work?" (phase 3, on-device only)
//
// Motion history never leaves the phone. Three days in the last week with a cycling
// stretch of 20+ minutes → one card suggesting Rider mode; "Not for me" hides it for good.

enum RiderSuggestion {
    struct Sample { let start: Date; let cycling: Bool }

    static let dismissedKey = "rider_suggestion_dismissed"
    static let minSession: TimeInterval = 20 * 60
    static let minDays = 3

    /// Activity changes (oldest first) → days with a long cycling stretch.
    static func ridingDays(_ samples: [Sample], now: Date = Date(), calendar: Calendar = .current) -> Int {
        var days = Set<DateComponents>()
        var sessionStart: Date?
        for (i, s) in samples.enumerated() {
            let next = i + 1 < samples.count ? samples[i + 1].start : now
            if s.cycling {
                if sessionStart == nil { sessionStart = s.start }
            } else {
                sessionStart = nil
            }
            if let start = sessionStart, next.timeIntervalSince(start) >= minSession,
               !(i + 1 < samples.count && samples[i + 1].cycling) {
                days.insert(calendar.dateComponents([.year, .month, .day], from: start))
            }
        }
        return days.count
    }

    static func shouldSuggest(_ samples: [Sample], now: Date = Date()) -> Bool {
        ridingDays(samples, now: now) >= minDays
    }
}

extension AppCoordinator {
    /// Checked when the app comes to the front (at most once a day).
    func evaluateRiderSuggestion() {
        guard !isDemo, userRole == .protected_, !isRiderMode,
              !UserDefaults.standard.bool(forKey: RiderSuggestion.dismissedKey),
              CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() == .authorized else { return }
        let last = UserDefaults.standard.double(forKey: "rider_suggestion_checked")
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "rider_suggestion_checked")
        CMMotionActivityManager().queryActivityStarting(from: Date().addingTimeInterval(-7 * 24 * 3600), to: Date(), to: .main) { [weak self] activities, _ in
            let samples = (activities ?? []).filter { $0.confidence != .low }
                .map { RiderSuggestion.Sample(start: $0.startDate, cycling: $0.cycling) }
            if RiderSuggestion.shouldSuggest(samples) { self?.showRiderSuggestion = true }
        }
    }

    func dismissRiderSuggestion() {
        showRiderSuggestion = false
        UserDefaults.standard.set(true, forKey: RiderSuggestion.dismissedKey)
    }
}
