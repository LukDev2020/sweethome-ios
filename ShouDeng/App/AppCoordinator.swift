import UIKit
import Combine
import WidgetKit
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

// MARK: - App Coordinator
//
// Central nervous system of the app. Wires together all services
// and algorithms, manages state, and routes events between layers.

final class AppCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var currentUser: User?
    @Published var userRole: UserRole = .protected_
    @Published var protectedPersons: [ProtectedPerson] = []  // Guardian sees these
    @Published var myGuardians: [Guardian] = []               // Protected person sees these
    @Published var activeSOSEvent: SOSEvent?
    /// The direct SOS request didn't get through; it is queued and retried on
    /// reconnect / foreground. Cleared when a flush delivers it.
    @Published var sosDeliveryFailed = false
    /// Server-side state of MY active SOS (who was notified, calls, who acknowledged).
    @Published var ownSOSStatus: SOSStatus?
    /// Guardian side: active SOS per protected person id.
    @Published var guardianSOS: [String: SOSStatus] = [:]
    /// Protected side: show SOSActiveView (never for a silent/duress SOS).
    @Published var isSOSScreenPresented = false
    /// Guardian side: an SOS push was opened — show its response screen.
    @Published var pendingAlertPersonId: String?
    @Published var showFallConfirmation = false
    @Published var fallConfirmationDeadline: Date?
    /// Manual SOS waiting out its cancel window (see requestSOS).
    @Published var pendingSOS: PendingSOS?
    @Published var currentRiskScores: [String: BaselineScorer.RiskScore] = [:]
    @Published var currentCoverage: DutyScheduler.DayCoverage?
    @Published var authState: AuthManager.AuthState = .unknown
    @Published var showSignup = false
    @Published var showSetupWizard = false
    /// Signed-in user hasn't agreed to the current "data stored in the US" wording yet
    @Published var needsDataTransferConsent = false
    @Published var signupPhone: String?
    @Published var signupCountry: CountryCode?
    /// Login verified this number but found no account: signup opens at the
    /// profile step and reuses that verification (no second SMS).
    @Published var signupPhoneVerified = false
    @Published var timeline: [TimelineEntry] = []
    @Published var familyPosts: [FamilyPost] = []
    /// The last family-circle refresh failed (the feed shows cached posts or an error).
    @Published var familyFeedRefreshFailed = false
    /// Last family-feed fetch, for the small diagnostic line under an empty feed
    /// (TestFlight reported an empty circle that we could not reproduce).
    @Published var familyFeedDiagnostic: String?
    private var familyFetchTask: Task<Bool, Never>?
    private var familyDeliveriesInFlight = Set<String>()
    /// Posts the server confirmed, and when (kept through a fetch that started earlier).
    private var familyConfirmedAt: [String: Date] = [:]
    @Published var selectedHotline: SelectedHotline?
    @Published var pendingDeepLink: DeepLinkDestination?
    @Published var showInviteAccept = false
    @Published var pendingInviteCode: String?
    /// Set when an SOS was requested from outside the app UI (lock-screen Live Activity
    /// link, `shoudeng://sos`). The user must confirm before anything is sent so that an
    /// arbitrary web link can never raise an SOS on its own.
    @Published var pendingSOSConfirmation: SOSTriggerMethod?

    // Tracking pause (protected person privacy)
    @Published var isTrackingPaused = false
    /// True while the only connection is carrier satellite data (iOS 26.1+):
    /// only SOS, check-ins and thinned location/heartbeat go out.
    @Published var isOnSatellite = false
    @Published var trackingPauseExpiresAt: Date?
    private var trackingPauseTimer: Timer?

    // MARK: - Infrastructure

    let offlineQueue: OfflineQueue
    let apiClient: APIClient
    /// Explore Mode coordinator: on-device demo data, no real side effects.
    let isDemo: Bool
    /// Preferences store. The demo coordinator gets a throw-away suite so the
    /// real UserDefaults are never touched.
    let defaults: UserDefaults
    let authManager: AuthManager
    /// The demo coordinator gets its own in-memory store (never the real one).
    let localStore: LocalStore

    // MARK: - Services

    let connectivity = ConnectivityMonitor()
    let locationManager = AdaptiveLocationManager()
    let motionService = MotionService()
    let heartbeatService = HeartbeatService()
    let pushService = PushService()
    let escalationEngine = EscalationEngine()
    let baselineScorer = BaselineScorer()
    let dutyScheduler = DutyScheduler()
    let deviceHealthMonitor = DeviceHealthMonitor()
    let crashReporter = CrashReporter.shared
    let liveActivityManager = GuardianActivityManager()
    let locationService = ReactiveLocationService()
    let distressDetectionService = DistressDetectionService()
    let voiceCommandService = VoiceCommandService()
    let audioCoordinator = AudioSessionCoordinator()
    let keyManager = KeyManager()
    lazy var e2eEncryption = E2ELocationEncryption(keyManager: keyManager)
    let storeKitManager: StoreKitManager
    let locationBatchUploader = LocationBatchUploader()
    let voiceNoteService = VoiceNoteService()
    let bleTrackerService = BLETrackerService.shared
    let tripRecordingService = TripRecordingService()

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    /// Everything that differs between the real app and Explore Mode.
    struct Environment {
        var isDemo: Bool
        var baseURL: String
        var sessionConfiguration: URLSessionConfiguration
        var offlineQueue: OfflineQueue
        var defaults: UserDefaults

        static func live() -> Environment {
            Environment(isDemo: false, baseURL: AppCoordinator.resolveBaseURL(),
                        sessionConfiguration: .default, offlineQueue: OfflineQueue(), defaults: .standard)
        }
    }

    convenience init() {
        self.init(environment: .live())
    }

    init(environment: Environment) {
        isDemo = environment.isDemo
        localStore = environment.isDemo ? .inMemory() : .shared
        defaults = environment.defaults
        offlineQueue = environment.offlineQueue

        // Register default: lock screen card enabled by default
        defaults.register(defaults: ["lockscreen_card_enabled": !environment.isDemo])

        let config = APIClient.Config(
            baseURL: environment.baseURL
        )
        apiClient = APIClient(config: config, offlineQueue: offlineQueue, sessionConfiguration: environment.sessionConfiguration)
        #if DEBUG
        print("[AppCoordinator] API base URL: \(config.baseURL)")
        #endif
        authManager = AuthManager(api: apiClient, defaults: environment.defaults, restore: !environment.isDemo)
        storeKitManager = StoreKitManager(apiClient: apiClient, observeTransactions: !environment.isDemo)

        // Wire 401 auto-refresh: when server returns 401, attempt token refresh.
        // In dev bypass mode, suppress logout to avoid wiping local state.
        apiClient.onUnauthorized = { [weak self] in
            guard let self else { return false }
            do {
                try await self.authManager.refreshToken()
                return true
            } catch {
                // Only log out on a definitive 401/403 from /refresh — never on a
                // timeout / 5xx / 429 (that would discard the session mid-SOS).
                if AuthManager.refreshFailureIsDefinitive(error) {
                    await MainActor.run { self.authManager.logout() }
                }
                return false
            }
        }

        // Queued requests belong to the user who made them
        apiClient.currentOwnerId = { [weak self] in
            self?.authManager.currentUserId ?? KeychainHelper.shared.read(.userId)
        }
        apiClient.onQueuedItemsDelivered = { [weak self] items in
            self?.handleQueuedItemsDelivered(items)
        }
        connectivity.onBecameReachable = { [weak self] in
            guard let self, case .loggedIn = self.authState else { return }
            Task { await self.apiClient.flushOfflineQueue() }
        }
        connectivity.onSatelliteChanged = { [weak self] onSatellite in
            guard let self else { return }
            self.apiClient.satellitePolicy.isOnSatellite = onSatellite
            self.isOnSatellite = onSatellite
        }
        if !environment.isDemo {
            connectivity.start()
        }

        // Sync initial auth state before Combine subscription delivers asynchronously
        authState = authManager.state

        // Explore Mode must not rebind the app-wide safety singletons (dead-man
        // switch, BLE, disguise…) to the demo coordinator, nor watch the network.
        if !environment.isDemo {
            configureSingletons()
        }

        wireServices()
        restoreLocalState()
        observeAuthState()
        observeLanguageChange()
        // Start Live Activity after restoring local state (so we have cached user/guardian data)
        if case .loggedIn = authState,
           defaults.bool(forKey: "lockscreen_card_enabled"),
           currentUser != nil {
            startLiveActivityIfNeeded()
        }
    }

    private func configureSingletons() {
        // Wire silent alarm service
            SilentAlarmService.shared.configure(apiClient: apiClient)
            SilentAlarmService.registerNotificationCategory()

            // Wire BLE tracker service
            bleTrackerService.configure(
                apiClient: apiClient,
                onSOSTrigger: { [weak self] in
                    self?.requestSOS(method: .bluetoothButton)
                },
                onSeparationAlert: { [weak self] tag in
                    self?.addTimelineEntry(type: .guardianAlert, description: String(format: LanguageManager.shared.localized("timeline.bleOut"), tag.name))
                    self?.notifyGuardiansOfSeparation(tagName: tag.name)
                },
                onReunion: { [weak self] tag in
                    self?.addTimelineEntry(type: .enteredSafeZone, description: String(format: LanguageManager.shared.localized("timeline.bleBack"), tag.name))
                }
            )

            // Wire trip recording service
            tripRecordingService.configure(apiClient: apiClient)

            // Wire dead man switch — expiry raises the SOS through triggerSOS
            DeadManSwitchService.shared.configure(apiClient: apiClient, locationManager: locationManager)
            DeadManSwitchService.shared.onTriggerSOS = { [weak self] method in
                self?.triggerSOS(method: method)
            }
            FakeCallService.shared.onTriggerSOS = { [weak self] method in
                self?.triggerSOS(method: method)
            }
            DeadManSwitchService.registerNotificationCategories()

            // Wire disguise mode — pass self as SOS trigger target
            DisguiseModeService.shared.configure(coordinator: self)
    }

    // MARK: - Language Change Observer

    private func observeLanguageChange() {
        NotificationCenter.default.addObserver(
            forName: LanguageManager.languageDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isDemo else { return }
            self.syncLocaleToServer()
            // Restart Live Activity so it picks up the new language
            self.liveActivityManager.endAllActivities()
            if defaults.bool(forKey: "lockscreen_card_enabled") {
                self.startLiveActivityIfNeeded()
            }
        }
    }

    // MARK: - Base URL

    static func resolveBaseURL() -> String {
        if let override = Bundle.main.infoDictionary?["API_BASE_URL"] as? String, !override.isEmpty {
            return override
        }
        #if DEBUG
        // Local verification against a stub: launch with `-apiBaseURL http://127.0.0.1:PORT/api`
        if let override = UserDefaults.standard.string(forKey: "apiBaseURL"), !override.isEmpty {
            return override
        }
        #endif
        #if QA_HARNESS
        // QA harness: point to emulator with seed project ID
        return "http://127.0.0.1:5001/sweethome-d1edd/us-central1/api"
        #elseif DEBUG
        return "http://127.0.0.1:5001/sweethome-b4e82/us-central1/api"
        #else
        return "https://us-central1-sweethome-b4e82.cloudfunctions.net/api"
        #endif
    }

    // MARK: - Restore Local State

    private func restoreLocalState() {
        if let user = localStore.loadCurrentUser() {
            currentUser = user
        }
        if let role = localStore.loadUserRole() {
            userRole = role
        }
        myGuardians = localStore.loadGuardians()
        protectedPersons = localStore.loadProtectedPersons()
        activeSOSEvent = localStore.loadActiveSOSEvent()
        timeline = localStore.loadTimeline()
        familyPosts = restoredFamilyPosts()

        // Load safe zones into location manager
        let zones = localStore.loadSafeZones()
        if !zones.isEmpty {
            locationManager.updateSafeZones(zones)
        }
    }

    /// Cached family posts; sends cut short become "not sent", and failed sends
    /// kept by older builds become unsent posts with Retry (once per install).
    private func restoredFamilyPosts() -> [FamilyPost] {
        var posts = FamilyFeedSync.interruptedSendsFailed(localStore.loadFamilyPosts())
        let migratedKey = "familyFeed.legacyUnsentMigrated"
        if !isDemo && !defaults.bool(forKey: migratedKey) {
            let store = localStore
            posts = FamilyFeedSync.legacyFailedSends(posts, myId: currentUser?.id) { fileURL in
                guard let data = try? Data(contentsOf: fileURL),
                      let jpeg = FamilyMediaEncoder.jpegForUpload(data) else { return nil }
                let name = "\(UUID().uuidString)_0.jpg"
                store.saveFamilyMedia(jpeg, name: name)
                return name
            }
            defaults.set(true, forKey: migratedKey)
            localStore.saveFamilyPosts(posts)
        }
        return posts
    }

    // MARK: - Auth State Observer

    private func observeAuthState() {
        authManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                // Mirror auth state as a @Published property on the coordinator,
                // since nested ObservableObject changes don't auto-propagate
                // to views that observe the coordinator via @EnvironmentObject.
                self.authState = state
                switch state {
                case .loggedIn(let userId):
                    defaults.set(userId, forKey: "currentUserId")
                    self.heartbeatService.userId = userId
                    #if canImport(FirebaseCrashlytics)
                    Crashlytics.crashlytics().setUserID(userId)
                    #endif
                    // Set role from login/signup response immediately
                    if let roleStr = self.authManager.lastLoginRole,
                       let role = UserRole(rawValue: roleStr) {
                        self.userRole = role
                        self.localStore.saveUserRole(role)
                    }
                    self.onLoginComplete(userId: userId)
                case .loggedOut:
                    self.onLogout()
                case .unknown:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func onLoginComplete(userId: String) {
        // Flush any queued offline requests
        Task { await apiClient.flushOfflineQueue() }

        // Location + notification permissions are requested only once someone is signed in
        if !isDemo, UserDefaults.standard.bool(forKey: "onboardingComplete") {
            locationManager.start()
            pushService.registerForPushNotifications()
            UIApplication.shared.registerForRemoteNotifications()
        }

        // Tell the server which language / time zone to use for my pushes,
        // SMS and voice calls, and when my local "on duty" hours are
        syncLocaleToServer()

        // Configure location batch uploader for offline → batch mode
        if let userId = currentUser?.id {
            locationBatchUploader.configure(apiClient: apiClient, userId: userId)
        }

        // Check for widget-triggered SOS / check-in
        checkWidgetSOSIntent()
        processPendingWidgetActions()

        // Fetch fresh data from server, then restart Live Activity with real data
        Task {
            await fetchUserProfile()
            if userRole == .guardian {
                await fetchProtectedPersons()
            } else {
                await fetchGuardians()
                await fetchSafeZones()
                await refreshOwnSOSStatus()
            }
            await MainActor.run {
                if defaults.bool(forKey: "lockscreen_card_enabled") {
                    startLiveActivityIfNeeded()
                }
            }
        }

        // Sync subscription status from StoreKit (catches overnight expirations/renewals),
        // and tell the server about subscriptions it hasn't seen (bought on another
        // device, restored, renewed while offline). Purchases carry this account's token.
        if !isDemo {
            let storeKit = storeKitManager
            Task { @MainActor in
                storeKit.setAccount(userId)
                await storeKit.refreshSubscriptionStatus()
                await storeKit.syncEntitlementsWithServer()
            }
        }

        // Sync local notification preferences to server
        syncNotificationPrefs()

        // Guardians who opted in to SOS Critical Alerts get the iOS permission
        // prompt (shown once; later calls just read the current setting).
        // Only after an explicit opt-in (consent card or settings) — a guardian who
        // never saw the choice is not prompted at login.
        if userRole == .guardian, defaults.object(forKey: Self.sosCriticalAlertsKey) as? Bool == true {
            pushService.requestCriticalAlertPermission()
        }

        syncWidgetState()

        #if DEBUG
        // Simulator verification hooks (launch arguments)
        if let personId = defaults.string(forKey: "debugOpenSOSAlert") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.pendingAlertPersonId = personId
                Task { await self?.fetchGuardianSOS(personId: personId) }
            }
        }
        if defaults.bool(forKey: "debugTriggerSOS") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.triggerSOS(method: .longPress) }
        }
        #endif

        // Apply any pending deep link that arrived before login
        if let pending = pendingDeepLink {
            pendingDeepLink = nil
            applyDeepLink(pending)
        }
    }

    private func onLogout() {
        if !isDemo { liveActivityManager.endAllActivities() }
        if !isDemo {
            let storeKit = storeKitManager
            Task { @MainActor in storeKit.setAccount(nil) }
        }
        currentUser = nil
        protectedPersons = []
        myGuardians = []
        activeSOSEvent = nil
        timeline = []
        familyPosts = []
        familyFeedRefreshFailed = false
        selectedHotline = nil
        showSignup = false
        signupPhone = nil
        signupCountry = nil
        signupPhoneVerified = false
        showInviteAccept = false
        pendingInviteCode = nil
        isTrackingPaused = false
        trackingPauseExpiresAt = nil
        trackingPauseTimer?.invalidate()
        trackingPauseTimer = nil
        locationManager.isTrackingPaused = false
        audioCoordinator.stopAll()
        keyManager.clearPeerKeys()
        locationBatchUploader.stop()
        locationBatchUploader.clearAll()
        localStore.clearAll()
        // The medical card is PII: the next user on this phone must not inherit it
        MedicalCardCache.clear()
        // Preserve SOS-critical requests across logout — they must reach the server.
        // They are tagged with their owner and only replay when that user signs in again.
        offlineQueue.retainOnly { $0.isSOS && $0.ownerId != nil }
        guardianSOS = [:]
        ownSOSStatus = nil
        pendingAlertPersonId = nil
        sosDeliveryFailed = false
        if !isDemo {
            WidgetDataStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
        }

        // Clear all user-specific UserDefaults
        let userKeys = [
            "onboardingComplete",
            "selected_hotline",
            "medical_card_cache",
            "custom_emergency_contacts",
            "local_emergency_contacts_v2",
            "notif_sos_alerts",
            "notif_checkin_reminder",
            "notif_checkin_overdue",
            "notif_family_feed",
            "login_failed_attempts",
            "login_lockout_until",
            "signup_failed_attempts",
            "signup_lockout_until",
            "setupWizardComplete",
            "distress_detection_enabled",
            "voice_command_enabled",
        ]
        for key in userKeys {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Scene Lifecycle (driven by ShouDengApp scenePhase)

    func sceneDidBecomeActive() {
        heartbeatService.appDidBecomeActive()
        guard case .loggedIn = authState else { return }
        // Fall detection runs while the app is open, for the person being protected
        // (matches NSMotionUsageDescription)
        if userRole == .protected_ {
            motionService.startForegroundMonitoring()
        }
        // Flush queued requests (SOS, check-ins, locations) now that we're in front
        Task { await apiClient.flushOfflineQueue() }
        // The SOS widget/intent may have fired while we were suspended
        checkWidgetSOSIntent()
        processPendingWidgetActions()
    }

    /// Check-in / "I arrived" tapped on a widget or the Live Activity.
    func processPendingWidgetActions() {
        guard !isDemo else { return }
        guard case .loggedIn = authState else { return }
        for action in WidgetDataStore.takePendingActions() {
            switch action {
            case .checkIn:
                performCheckIn()
            case .arrived:
                apiClient.postQueued("/v1/home-timer/dismiss", body: EmptyBody())
                performCheckIn(note: LanguageManager.shared.localized("widget.arrived.note"))
            }
        }
    }

    func sceneWillResignActive() {
        MainActor.assumeIsolated { DisguiseModeService.shared.rearmIfEnabled() }
        motionService.stopForegroundMonitoring()
        // Auto-start Live Activity when user leaves the app (if enabled)
        startLiveActivityOnBackground()
    }

    // MARK: - Widget SOS Intent

    /// Check if the SOS widget triggered an intent while the app was closed.
    private func checkWidgetSOSIntent() {
        guard !isDemo else { return }
        guard let defaults = UserDefaults(suiteName: WidgetDataStore.appGroupId) else { return }
        guard defaults.bool(forKey: "widget_sos_pending") else { return }

        // Clear the flag immediately to prevent re-triggering
        defaults.set(false, forKey: "widget_sos_pending")

        // Only honor if the intent was within the last 60 seconds
        let timestamp = defaults.double(forKey: "widget_sos_timestamp")
        let age = Date().timeIntervalSince1970 - timestamp
        guard age < 60, age > 0 else { return }

        #if DEBUG
        print("[AppCoordinator] Widget SOS intent detected — starting SOS countdown")
        #endif
        requestSOS(method: .widgetTap)
    }

    // MARK: - Deep Link Handling

    func handleDeepLink(_ url: URL) {
        // Handle custom scheme actions (shoudeng://sos, shoudeng://checkin, etc.)
        if url.scheme == "shoudeng" {
            switch url.host {
            case "sos":
                // Never trigger directly from a URL — ask the user first.
                if case .loggedIn = authState, userRole == .protected_ {
                    pendingSOSConfirmation = .widgetTap
                }
                return
            case "checkin":
                performCheckIn()
                return
            case "share-location":
                shareCurrentLocation()
                return
            default:
                break
            }
        }
        guard let destination = DeepLinkRouter.parse(url: url) else { return }
        handleDeepLinkDestination(destination)
    }

    func handleUserActivity(_ activity: NSUserActivity) {
        guard let destination = DeepLinkRouter.parse(userActivity: activity) else { return }
        handleDeepLinkDestination(destination)
    }

    private func handleDeepLinkDestination(_ destination: DeepLinkDestination) {
        switch authManager.state {
        case .loggedIn:
            applyDeepLink(destination)
        default:
            // Store for after login
            pendingDeepLink = destination
        }
    }

    private func applyDeepLink(_ destination: DeepLinkDestination) {
        switch destination {
        case .invite(let code):
            presentInviteAccept(code: code)
        case .evidence:
            // Evidence links are handled by the web view; no in-app routing needed
            break
        case .sosEvent:
            // Navigate to SOS detail — triggers on guardian tab
            break
        }
    }

    // MARK: - Fetch User Profile

    func fetchUserProfile() async {
        do {
            let profile: UserProfileResponse = try await apiClient.get("/v1/user/me")
            let user = User(
                id: profile.id,
                displayName: profile.displayName,
                role: UserRole(rawValue: profile.role) ?? .protected_,
                avatarInitial: profile.avatarInitial,
                email: profile.email,
                timeZone: TimeZone(identifier: profile.timeZone) ?? .current,
                countryCode: profile.countryCode,
                cityName: profile.cityName,
                createdAt: profile.createdAt
            )
            await MainActor.run {
                self.currentUser = user
                self.userRole = user.role
                self.localStore.saveCurrentUser(user)
                self.localStore.saveUserRole(user.role)
                self.needsDataTransferConsent = !self.isDemo
                    && profile.dataTransferConsentVersion != DataTransferConsent.version
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch profile: \(error)")
            #endif
            // If the token is invalid/expired and refresh also failed, force logout
            if let apiError = error as? APIError, case .unauthorized = apiError {
                await MainActor.run { authManager.logout() }
            }
        }
    }

    /// Number to call when nobody else can be reached.
    /// One source of truth: RegionalEmergencyInfo (ambulance first). The region is the
    /// one picked in the consulate screen, else the profile country, else the device region.
    var localEmergencyNumber: String {
        let picked = selectedHotline?.countryCode ?? ""
        let profile = currentUser?.countryCode ?? ""
        let country = !picked.isEmpty ? picked : (!profile.isEmpty ? profile : (Locale.current.region?.identifier ?? ""))
        return RegionalEmergencyInfo.forCountry(country).primaryNumber
    }

    // MARK: - Explore Mode personas

    /// Become a member of the demo family (no token, nothing stored for real).
    /// Fetches go through DemoURLProtocol like a normal login.
    func beginDemoPersona(userId: String, role: UserRole, location: CLLocationCoordinate2D? = nil) {
        guard isDemo else { return }
        // The demo never reads the real GPS: show the persona where they live
        locationService.currentLocation = location
        locationService.lastUpdateTime = location == nil ? nil : Date()
        locationManager.demoLocation = location.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        // The sample family (Sarah guards Mom and Dad) is on the Family plan; on the
        // free plan the guardian home showed "2 / 1 — plan limit reached".
        let storeKit = storeKitManager
        Task { @MainActor in storeKit.purchasedPlanId = "family" }
        isSOSScreenPresented = false
        pendingAlertPersonId = nil
        activeSOSEvent = nil
        ownSOSStatus = nil
        guardianSOS = [:]
        protectedPersons = []
        myGuardians = []
        timeline = []
        familyPosts = []
        userRole = role
        authManager.startDemoSession(userId: userId, role: role.rawValue)
    }

    /// Demo: show the persona's own SOS again when switching back to their phone.
    func adoptDemoOwnSOS(_ status: SOSStatus) {
        guard isDemo, activeSOSEvent == nil else { return }
        activeSOSEvent = SOSEvent(
            id: status.sosEventId, protectedPersonId: status.protectedPersonId,
            triggeredAt: status.triggeredAt ?? Date(), triggerMethod: .longPress, location: nil,
            batteryLevel: status.batteryLevel, escalationState: status.escalationState,
            resolvedAt: nil, resolvedBy: nil, resolution: nil, clientSOSId: nil)
        ownSOSStatus = status
    }

    // MARK: - Locale / time zone

    struct LocaleUpdateRequest: Encodable {
        let locale: String
        let timeZone: String
    }

    func syncLocaleToServer() {
        guard case .loggedIn = authState else { return }
        let body = LocaleUpdateRequest(
            locale: LanguageManager.shared.current.rawValue,
            timeZone: TimeZone.current.identifier
        )
        Task {
            do {
                let _: SuccessResponse = try await apiClient.put("/v1/user/me", body: body)
            } catch {
                #if DEBUG
                print("[Coordinator] locale sync failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - Safe Zones

    func fetchSafeZones() async {
        do {
            let response: [SafeZoneResponse] = try await apiClient.get("/v1/safe-zones")
            let zones = response.map {
                SafeZone(id: $0.id, name: $0.name, latitude: $0.latitude, longitude: $0.longitude,
                         radius: $0.radius, isAutoSuggested: $0.isAutoSuggested, visitFrequency: 0, typicalHours: nil)
            }
            await MainActor.run {
                self.localStore.saveSafeZones(zones)
                self.locationManager.updateSafeZones(zones)
            }
        } catch {
            #if DEBUG
            print("[Coordinator] safe zone fetch failed: \(error)")
            #endif
        }
    }

    // MARK: - Data Transfer Consent

    func recordDataTransferConsent() async throws {
        let _: SuccessResponse = try await apiClient.post(
            "/v1/user/consent",
            body: ["type": "cross_border_transfer", "version": DataTransferConsent.version]
        )
        await MainActor.run { needsDataTransferConsent = false }
    }

    // MARK: - Member Timeline

    /// Recent events of someone I guard (their own timeline, not mine).
    func fetchTimeline(of personId: String, limit: Int = 10) async -> [TimelineEntry] {
        let id = personId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? personId
        do {
            let response: TimelineResponse = try await apiClient.get("/v1/timeline?personId=\(id)&limit=\(limit)")
            return response.entries
        } catch {
            return []
        }
    }

    // MARK: - Data Export

    /// Everything the server holds about this account, saved as a JSON file to keep or share.
    func exportMyData() async throws -> URL {
        let raw: RawResponse = try await apiClient.post("/v1/user/export", body: EmptyBody())
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanternCare-data-\(day).json")
        try raw.data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    // MARK: - Switch Role

    func switchRole(to newRole: UserRole) async throws {
        let _: [String: Bool] = try await apiClient.put(
            "/v1/user/me",
            body: ["role": newRole.rawValue]
        )
        await MainActor.run {
            self.userRole = newRole
            self.currentUser?.role = newRole
            if let user = self.currentUser {
                self.localStore.saveCurrentUser(user)
            }
            self.localStore.saveUserRole(newRole)
        }
    }

    // MARK: - Fetch Data

    func fetchProtectedPersons() async {
        do {
            let lossy: LossyArray<ProtectedPersonStatusResponse> = try await apiClient.get("/v1/guardian/protected-persons")
            let persons = lossy.elements
            let mapped = persons.map { p in
                ProtectedPerson(
                    id: p.personId,
                    user: User(
                        id: p.personId,
                        displayName: p.displayName,
                        role: .protected_,
                        avatarInitial: String(p.displayName.prefix(1)),
                        timeZone: p.timeZoneId.flatMap { TimeZone(identifier: $0) } ?? .current,
                        countryCode: p.countryCode ?? "",
                        cityName: p.cityName ?? p.locationAddress ?? "",
                        createdAt: Date()
                    ),
                    guardians: [],
                    protectionLayers: p.protectionLayers,
                    lastCheckIn: p.lastCheckIn,
                    lastKnownLocation: p.latitude.flatMap { lat in
                        p.longitude.flatMap { lng in
                            p.locationTimestamp.map { ts in
                                Location(
                                    latitude: lat, longitude: lng,
                                    accuracy: p.locationAccuracy ?? 0,
                                    altitude: nil, speed: nil,
                                    timestamp: ts,
                                    address: p.locationAddress
                                )
                            }
                        }
                    },
                    batteryLevel: p.batteryLevel,
                    batteryState: p.batteryState,
                    lastPhoneActivity: p.lastPhoneActivity,
                    status: p.status,
                    activeSOS: p.activeSOS
                )
            }
            await MainActor.run {
                self.guardianSOS = Dictionary(
                    persons.compactMap { p in p.activeSOS.map { (p.personId, $0) } },
                    uniquingKeysWith: { a, _ in a }
                )
                self.protectedPersons = mapped
                self.localStore.saveProtectedPersons(mapped)
                self.syncWidgetState()
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch protected persons: \(error)")
            #endif
        }
    }

    func fetchGuardians() async {
        do {
            let guardians: [Guardian] = try await apiClient.get("/v1/protected/guardians")
            await MainActor.run {
                self.myGuardians = guardians
                self.localStore.saveGuardians(guardians)
                self.syncWidgetState()
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch guardians: \(error)")
            #endif
        }
    }

    // MARK: - Selected Hotline

    func loadSelectedHotline() {
        // Try local cache first
        if let data = defaults.data(forKey: "selected_hotline"),
           let hotline = try? JSONDecoder().decode(SelectedHotline.self, from: data) {
            selectedHotline = hotline
        }
        // Then try server
        Task {
            do {
                let hotline: SelectedHotline? = try await apiClient.get("/v1/consulate/selected/me")
                if let hotline {
                    await MainActor.run {
                        self.selectedHotline = hotline
                        self.cacheSelectedHotline(hotline)
                    }
                }
            } catch {
                #if DEBUG
                print("[Coordinator] Failed to fetch selected hotline: \(error)")
                #endif
            }
        }
    }

    func saveSelectedHotline(_ hotline: SelectedHotline) {
        selectedHotline = hotline
        cacheSelectedHotline(hotline)
        Task {
            do {
                let _: SuccessResponse = try await apiClient.put(
                    "/v1/consulate/selected",
                    body: SelectedHotlineRequest(
                        countryCode: hotline.countryCode,
                        countryName: hotline.countryName,
                        flag: hotline.flag,
                        emergency: hotline.emergency,
                        embassy: hotline.embassy,
                        selectedPhone: hotline.selectedPhone,
                        selectedLabel: hotline.selectedLabel
                    )
                )
            } catch {
                #if DEBUG
                print("[Coordinator] Failed to save selected hotline to server: \(error)")
                #endif
            }
        }
    }

    func removeSelectedHotline() {
        selectedHotline = nil
        defaults.removeObject(forKey: "selected_hotline")
        Task {
            do {
                let _: SuccessResponse = try await apiClient.delete("/v1/consulate/selected")
            } catch {
                #if DEBUG
                print("[Coordinator] Failed to delete selected hotline from server: \(error)")
                #endif
            }
        }
    }

    private func cacheSelectedHotline(_ hotline: SelectedHotline) {
        if let data = try? JSONEncoder().encode(hotline) {
            defaults.set(data, forKey: "selected_hotline")
        }
    }

    // MARK: - Service Wiring

    private func wireServices() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-screenshot") { return }
        #endif

        // Location → Heartbeat + Server + Reactive SwiftUI bridge + Trip recording
        locationManager.onLocationReport = { [weak self] location in
            self?.heartbeatService.recordBeat(source: .significantLocation, location: location)
            self?.handleLocationUpdate(location)
            // Feed location to trip recording if active
            if self?.tripRecordingService.isRecording == true {
                let clLoc = CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    altitude: location.altitude ?? 0,
                    horizontalAccuracy: location.accuracy,
                    verticalAccuracy: -1,
                    course: -1,
                    speed: location.speed ?? -1,
                    timestamp: location.timestamp
                )
                self?.tripRecordingService.addPoint(clLoc)
            }
        }
        // Bind reactive service AFTER setting the callback — it preserves the chain
        locationService.bind(to: locationManager)

        // Location → Safe zone events
        locationManager.onSafeZoneEnter = { [weak self] zone in
            self?.addTimelineEntry(type: .enteredSafeZone, description: String(format: LanguageManager.shared.localized("timeline.zoneEnter"), zone.name))
        }

        locationManager.onSafeZoneExit = { [weak self] zone in
            self?.addTimelineEntry(type: .leftSafeZone, description: String(format: LanguageManager.shared.localized("timeline.zoneLeave"), zone.name))
        }

        // Location → Auto-discover safe zones
        locationManager.onDwellPointDiscovered = { dwellPoint in
            #if DEBUG
            print("[Coordinator] Discovered dwell point: \(dwellPoint.suggestedName ?? "常去地点") at (\(dwellPoint.latitude), \(dwellPoint.longitude))")
            #endif
        }

        // Motion → Fall detection
        motionService.onFallCandidate = { [weak self] in
            self?.handleFallCandidate()
        }

        motionService.onFallConfirmed = { [weak self] in
            self?.handleFallConfirmed()
        }

        // Motion → Activity type → Location manager
        motionService.onActivityChange = { [weak self] activity in
            guard let self else { return }
            let type: Location.ActivityType
            if activity.stationary { type = .stationary }
            else if activity.walking { type = .walking }
            else if activity.running { type = .running }
            else if activity.automotive { type = .driving }
            else if activity.cycling { type = .cycling }
            else { type = .unknown }
            self.locationManager.detectedActivityType = type
        }

        // Audio → Distress detection → SOS with countdown
        audioCoordinator.distressService = distressDetectionService
        audioCoordinator.voiceService = voiceCommandService

        distressDetectionService.onDistressDetected = { [weak self] label, confidence in
            #if DEBUG
            print("[Coordinator] Distress sound: \(label) (\(Int(confidence * 100))%)")
            #endif
            self?.handleDistressDetected()
        }

        // Voice → SOS command
        voiceCommandService.onSOSCommand = { [weak self] phrase in
            #if DEBUG
            print("[Coordinator] Voice SOS command: \"\(phrase)\"")
            #endif
            self?.handleVoiceSOSCommand(phrase: phrase)
        }

        // Restore audio service preferences
        audioCoordinator.distressDetectionEnabled = defaults.bool(forKey: "distress_detection_enabled")
        audioCoordinator.voiceCommandEnabled = defaults.bool(forKey: "voice_command_enabled")

        // Heartbeat → Server reporting
        heartbeatService.onHeartbeat = { [weak self] signal in
            self?.reportHeartbeatToServer(signal)
        }

        // Push → SOS handling
        pushService.onSOSTakenOver = { [weak self] sosId in
            self?.handleSOSTakenOver(sosId: sosId)
        }

        pushService.onCheckInFromNotification = { [weak self] in
            self?.performCheckIn()
        }

        pushService.onCancelPendingSOS = { [weak self] in
            self?.cancelPendingSOS()
        }
        pushService.onOpenSOSAlert = { [weak self] personId, _ in
            guard let self else { return }
            self.pendingAlertPersonId = personId
            Task { await self.fetchGuardianSOS(personId: personId) }
        }

        // Escalation → Notifications
        escalationEngine.onSendNotification = { [weak self] request in
            self?.sendNotification(request)
        }

        escalationEngine.onEscalationFrozen = { [weak self] session, guardianId in
            self?.addTimelineEntry(
                type: .sosResolved,
                description: LanguageManager.shared.localized("timeline.guardianTookOver")
            )
            _ = session
            _ = guardianId
        }

        // Voice call → server API
        escalationEngine.onInitiateVoiceCall = { [weak self] guardianId, sosEventId in
            self?.initiateVoiceCall(guardianId: guardianId, sosEventId: sosEventId)
        }
    }

    // MARK: - Live Activity

    /// Called when app goes to background — starts Live Activity if user has it enabled.
    func startLiveActivityOnBackground() {
        guard !isDemo else { return }
        guard case .loggedIn = authState else { return }
        guard defaults.bool(forKey: "lockscreen_card_enabled") else { return }
        if !liveActivityManager.isRunning {
            startLiveActivityIfNeeded()
        }
    }

    func startLiveActivityIfNeeded() {
        guard !isDemo else { return }
        let emergencyPhone = localEmergencyNumber

        if userRole == .protected_ {
            // Protected Person: show who is guarding you
            let guardianInfos = myGuardians.map { g in
                ProtectedActivityAttributes.GuardianInfo(
                    name: g.user.displayName,
                    initial: g.user.avatarInitial,
                    isOnDuty: g.isOnDuty,
                    isOnline: g.isOnDuty // approximate: on-duty ≈ online
                )
            }
            // Load emergency medical info from cache
            let cachedCard = MedicalCardCache.load()
            let medInfos: [ProtectedActivityAttributes.MedInfo] = (cachedCard?.emergencyMedications ?? []).map {
                ProtectedActivityAttributes.MedInfo(name: $0.name, location: $0.storageLocation, dosage: $0.dosage)
            }

            liveActivityManager.startProtectedActivity(
                userName: currentUser?.displayName ?? "",
                guardians: guardianInfos,
                lastCheckIn: nil,
                emergencyPhone: emergencyPhone,
                emergencyLabel: localEmergencyNumber,
                bloodType: cachedCard?.bloodType,
                allergies: cachedCard?.allergies ?? [],
                conditions: cachedCard?.conditions ?? [],
                emergencyNote: cachedCard?.emergencyNote,
                emergencyMedications: medInfos
            )
        } else {
            // Guardian: show each protected person's status
            let personInfos = protectedPersons.map { pp in
                GuardianActivityAttributes.PersonInfo(
                    id: pp.id,
                    displayName: pp.user.displayName,
                    initial: pp.user.avatarInitial,
                    status: Self.mapPersonStatus(pp.status),
                    cityName: pp.user.cityName,
                    lastCheckIn: pp.lastCheckIn,
                    batteryLevel: pp.batteryLevel
                )
            }
            let priority = protectedPersons
                .sorted { Self.statusPriority($0.status) > Self.statusPriority($1.status) }
                .first
            liveActivityManager.startGuardianActivity(
                guardianName: currentUser?.displayName ?? "",
                persons: personInfos,
                priorityPersonName: priority?.user.displayName ?? "",
                priorityPersonPhone: emergencyPhone
            )
        }
    }

    private static func mapPersonStatus(_ status: SafetyStatus) -> GuardianActivityAttributes.PersonStatus {
        switch status {
        case .normal, .pendingCheckIn: return .normal
        case .overdue: return .overdue
        case .alert: return .alert
        case .unreachable: return .unreachable
        }
    }

    private static func statusPriority(_ status: SafetyStatus) -> Int {
        switch status {
        case .alert: return 3
        case .overdue: return 2
        case .unreachable: return 1
        case .normal, .pendingCheckIn: return 0
        }
    }

    // MARK: - SOS Cancel Window

    struct PendingSOS: Equatable {
        let method: SOSTriggerMethod
        let deadline: Date
        let duration: Int
    }

    private var pendingSOSWork: DispatchWorkItem?
    private var pendingSOSBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// Seconds the user gets to cancel before guardians are alerted.
    /// 0 = send immediately: a duress SOS must stay silent and instant, and
    /// fall / voice / distress-sound / safety-timer SOS already had their own
    /// confirmation countdown before reaching here.
    static func sosCancelWindow(for method: SOSTriggerMethod) -> Int {
        switch method {
        case .longPress, .widgetTap, .bluetoothButton, .watchQuickAction:
            return 5
        case .duressPassword, .fallDetection, .voiceWakeWord, .audioDistress, .voiceCommand, .deadManSwitch:
            return 0
        }
    }

    /// Entry point for user-initiated SOS. Starts a short cancel countdown
    /// (accidental presses, pocket triggers) and sends the SOS when it ends.
    func requestSOS(method: SOSTriggerMethod = .longPress) {
        // An SOS already running: show it instead of silently ignoring the press.
        if activeSOSEvent != nil {
            if !method.isSilent { isSOSScreenPresented = true }
            return
        }
        guard pendingSOS == nil else { return }
        let seconds = Self.sosCancelWindow(for: method)
        guard seconds > 0 else {
            triggerSOS(method: method)
            return
        }

        pendingSOS = PendingSOS(method: method, deadline: Date().addingTimeInterval(TimeInterval(seconds)), duration: seconds)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        // Keep the countdown alive if the app is backgrounded (BLE button, widget).
        pendingSOSBackgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // Out of background time: send now rather than lose the SOS.
            self?.sendPendingSOSNow()
        }
        if UIApplication.shared.applicationState != .active {
            pushService.firePendingSOSNotice(seconds: seconds)
        }

        let work = DispatchWorkItem { [weak self] in self?.sendPendingSOSNow() }
        pendingSOSWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: work)
    }

    /// Countdown finished, or the user tapped "Send now".
    func sendPendingSOSNow() {
        guard let pending = pendingSOS else { return }
        clearPendingSOS()
        triggerSOS(method: pending.method)
    }

    /// User cancelled within the window: nothing is sent to guardians.
    func cancelPendingSOS() {
        guard pendingSOS != nil else { return }
        clearPendingSOS()
        addTimelineEntry(type: .sosResolved, description: LanguageManager.shared.localized("timeline.sosCancelledInWindow"))
    }

    private func clearPendingSOS() {
        pendingSOSWork?.cancel()
        pendingSOSWork = nil
        pendingSOS = nil
        pushService.removePendingSOSNotice()
        if pendingSOSBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(pendingSOSBackgroundTask)
            pendingSOSBackgroundTask = .invalid
        }
    }

    // MARK: - SOS Trigger

    /// Sends the SOS immediately. User-facing triggers should call requestSOS
    /// so they get the cancel window; only duress and already-confirmed
    /// automatic triggers come here directly.
    func triggerSOS(method: SOSTriggerMethod = .longPress) {
        // authManager is the source of truth: currentUser can still be nil after a
        // locked background relaunch (BLE button, widget, dead-man switch).
        guard let userId = authManager.currentUserId ?? currentUser?.id, !userId.isEmpty else {
            #if DEBUG
            print("[AppCoordinator] Cannot trigger SOS: not signed in")
            #endif
            return
        }
        // Already in an SOS: don't create a second local event
        if let existing = activeSOSEvent, existing.isActive {
            return
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawBattery = UIDevice.current.batteryLevel
        let battery: Double? = rawBattery >= 0 ? Double(rawBattery) : nil
        let localId = UUID().uuidString
        let now = Date()
        let sosEvent = SOSEvent(
            id: localId,
            protectedPersonId: userId,
            triggeredAt: now,
            triggerMethod: method,
            location: nil,
            batteryLevel: battery,
            escalationState: .initiated,
            resolvedAt: nil,
            resolvedBy: nil,
            resolution: nil,
            clientSOSId: localId
        )

        activeSOSEvent = sosEvent
        ownSOSStatus = nil
        if !method.isSilent { isSOSScreenPresented = true }
        localStore.saveActiveSOSEvent(sosEvent)
        syncWidgetState()

        // If tracking was paused, auto-resume — safety overrides privacy
        if isTrackingPaused {
            resumeTracking()
        }

        // Switch location to SOS mode
        if !isDemo { locationManager.enterSOSMode() }

        // Lock-screen card shows SOS — but a duress / disguise SOS must stay invisible and silent
        if !method.isSilent && !isDemo {
            liveActivityManager.triggerSOS(
                localEmergencyNumber: localEmergencyNumber
            )
        }

        addTimelineEntry(type: .sosTriggered, description: String(format: LanguageManager.shared.localized("timeline.sosTriggered"),
                                                                         LanguageManager.shared.localized("sos.method.\(method.rawValue)")))

        #if BETA
        // Beta: simulate escalation — skip real API call and immediately acknowledge
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.activeSOSEvent?.escalationState = .acknowledged
            self?.addTimelineEntry(type: .sosResolved, description: LanguageManager.shared.localized("timeline.sosBetaSim"))
        }
        #else
        // Persist to the offline queue FIRST, then try right away with a short
        // timeout; if that fails the queue retries on reconnect / foreground.
        sosDeliveryFailed = false
        let sosLocation = locationManager.lastReportedLocation
        let triggerRequest = SOSTriggerRequest(
            protectedPersonId: userId,
            triggerMethod: method,
            latitude: sosLocation?.coordinate.latitude,
            longitude: sosLocation?.coordinate.longitude,
            batteryLevel: battery,
            clientSOSId: localId,
            clientTriggeredAt: now
        )
        let api = apiClient
        Task { @MainActor [weak self] in
            let response: SOSTriggerResponse? = await api.postSOS("/v1/sos/trigger", body: triggerRequest)
            guard let self else { return }
            if let response {
                self.applyServerSOSId(response.sosEventId, forClientId: localId)
                await self.refreshOwnSOSStatus()
            } else if self.activeSOSEvent?.clientSOSId == localId {
                self.sosDeliveryFailed = true
            }
        }
        #endif
    }

    /// The server answered for a queued/direct SOS trigger: adopt its id so
    /// resolve and status polling address the real event.
    private func applyServerSOSId(_ serverId: String, forClientId clientId: String?) {
        guard var event = activeSOSEvent, event.clientSOSId == clientId || clientId == nil else { return }
        event.id = serverId
        activeSOSEvent = event
        localStore.saveActiveSOSEvent(event)
    }

    private func handleQueuedItemsDelivered(_ items: [OfflineQueue.Item]) {
        guard items.contains(where: { $0.path == "/v1/sos/trigger" }) else { return }
        sosDeliveryFailed = false
        Task { await refreshOwnSOSStatus() }
    }

    private var hasQueuedSOSTrigger: Bool {
        offlineQueue.peekAll().contains { $0.path == "/v1/sos/trigger" }
    }

    /// Local cleanup for an SOS that already ended on the server (no API calls).
    private func clearEndedSOSLocally() {
        guard activeSOSEvent != nil else { return }
        activeSOSEvent = nil
        ownSOSStatus = nil
        sosDeliveryFailed = false
        isSOSScreenPresented = false
        localStore.saveActiveSOSEvent(nil)
        syncWidgetState()
        if !isDemo {
            locationManager.exitSOSMode()
            liveActivityManager.cancelSOS()
        }
    }

    /// Protected person: what the server has actually done for my SOS.
    func refreshOwnSOSStatus() async {
        guard activeSOSEvent != nil else { return }
        do {
            let response: ActiveSOSResponse = try await apiClient.get("/v1/sos/active")
            await MainActor.run {
                self.ownSOSStatus = response.sos
                if response.sos == nil, !self.hasQueuedSOSTrigger,
                   let local = self.activeSOSEvent, Date().timeIntervalSince(local.triggeredAt) > 60 {
                    // The server has no active SOS for me (a guardian resolved it, or it
                    // ended while the app was closed), nothing is waiting to be sent, and
                    // it isn't one just sent: drop the stale local copy, which otherwise
                    // blocked every new SOS.
                    self.clearEndedSOSLocally()
                    return
                }
                if let sos = response.sos {
                    self.sosDeliveryFailed = false
                    if self.activeSOSEvent?.id != sos.sosEventId {
                        self.applyServerSOSId(sos.sosEventId, forClientId: nil)
                    }
                    self.activeSOSEvent?.escalationState = sos.escalationState
                }
            }
        } catch {
            #if DEBUG
            print("[Coordinator] SOS status fetch failed: \(error)")
            #endif
        }
    }

    // MARK: - Guardian: active SOS of a protected person

    func fetchGuardianSOS(personId: String) async {
        do {
            let response: ActiveSOSResponse = try await apiClient.get("/v1/guardian/sos/active?personId=\(personId)")
            await MainActor.run {
                if let sos = response.sos {
                    self.guardianSOS[personId] = sos
                } else {
                    self.guardianSOS.removeValue(forKey: personId)
                }
            }
        } catch {
            #if DEBUG
            print("[Coordinator] guardian SOS fetch failed: \(error)")
            #endif
        }
    }

    /// "I've got it": stops the automatic pushes / SMS / calls and tells the
    /// rest of the family. Does NOT close the SOS.
    @discardableResult
    func acknowledgeSOS(sosEventId: String) async throws -> SOSAcknowledgeResponse {
        let response: SOSAcknowledgeResponse = try await apiClient.post(
            "/v1/sos/acknowledge", body: SOSAcknowledgeRequest(sosEventId: sosEventId)
        )
        await MainActor.run { escalationEngine.freeze(by: response.acknowledgedBy) }
        if let personId = guardianSOS.first(where: { $0.value.sosEventId == sosEventId })?.key {
            await fetchGuardianSOS(personId: personId)
        }
        return response
    }

    /// "She's safe": closes the SOS for everyone.
    func resolveSOSAsGuardian(sosEventId: String, personId: String) async throws {
        let _: SuccessResponse = try await apiClient.post(
            "/v1/sos/resolve",
            body: SOSResolveRequest(sosEventId: sosEventId, resolvedBy: currentUser?.id ?? "", resolution: .guardianConfirmedSafe)
        )
        await MainActor.run {
            self.guardianSOS.removeValue(forKey: personId)
            if let idx = self.protectedPersons.firstIndex(where: { $0.id == personId }) {
                self.protectedPersons[idx].activeSOS = nil
                if self.protectedPersons[idx].status == .alert { self.protectedPersons[idx].status = .normal }
            }
        }
    }

    // MARK: - BLE Tag Separation Alert

    private func notifyGuardiansOfSeparation(tagName: String) {
        guard currentUser != nil else { return }
        let location = locationManager.lastReportedLocation
        apiClient.postQueued("/v1/device/ble-separation", body: BLESeparationRequest(
            tagName: tagName,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude
        )) { _ in }
    }

    // MARK: - Duress Code SOS

    func triggerDuressSOS() {
        // Silently trigger SOS with duress method — no on-screen alerts
        triggerSOS(method: .duressPassword)
        #if DEBUG
        print("[AppCoordinator] Duress code triggered — silent SOS activated")
        #endif
    }

    func confirmPendingSOS() {
        guard let method = pendingSOSConfirmation else { return }
        pendingSOSConfirmation = nil
        triggerSOS(method: method)
    }

    func cancelSOS() {
        guard let sos = activeSOSEvent else { return }
        let userId = authManager.currentUserId ?? currentUser?.id ?? "unknown"
        escalationEngine.resolve(by: userId, resolution: .protectedCancelled)
        activeSOSEvent = nil
        ownSOSStatus = nil
        sosDeliveryFailed = false
        localStore.saveActiveSOSEvent(nil)
        syncWidgetState()
        if !isDemo {
            locationManager.exitSOSMode()
            // Restore lock screen to normal
            liveActivityManager.cancelSOS()
        }

        addTimelineEntry(type: .sosResolved, description: LanguageManager.shared.localized("timeline.sosCancelled"))

        // If the trigger never left the phone, drop it instead of sending a
        // trigger + cancel later (which would alert the family for nothing).
        if let clientId = sos.clientSOSId {
            let removed = offlineQueue.removeItems { item in
                item.path == "/v1/sos/trigger"
                    && item.body.flatMap { String(data: $0, encoding: .utf8) }?.contains(clientId) == true
            }
            if !removed.isEmpty, sos.id == clientId { return }
        }

        apiClient.postQueued("/v1/sos/resolve", body: SOSResolveRequest(
            sosEventId: sos.id,
            resolvedBy: userId,
            resolution: .protectedCancelled
        ))
    }

    // MARK: - Check-In

    /// Share current location via system share sheet (triggered from Lock Screen card)
    func shareCurrentLocation() {
        guard let loc = locationManager.bestAvailableLocation else { return }
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        let name = currentUser?.displayName ?? LanguageManager.shared.localized("share.myLocation")
        let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mapURL = "https://maps.apple.com/?ll=\(lat),\(lng)&q=\(query)"
        let items: [Any] = [mapURL]
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(ac, animated: true)
        }
    }

    func performCheckIn(note: String? = nil) {
        guard let userId = currentUser?.id, !userId.isEmpty else { return }

        let checkIn = CheckInEvent.create(userId: userId, location: nil)

        addTimelineEntry(type: .checkIn, description: note ?? LanguageManager.shared.localized("timeline.checkIn"))
        syncWidgetState()

        let checkinLocation = locationManager.lastReportedLocation
        apiClient.postQueued("/v1/checkin", body: CheckInRequest(
            userId: userId,
            latitude: checkinLocation?.coordinate.latitude,
            longitude: checkinLocation?.coordinate.longitude,
            note: note
        ))
        _ = checkIn
    }

    // MARK: - Tracking Pause

    static let maxPauseDurationHours: Double = 4

    private struct TrackingPauseRequest: Encodable {
        let userId: String
        let paused: Bool
        var expiresAt: String?
    }

    func pauseTracking() {
        let expiry = Date().addingTimeInterval(Self.maxPauseDurationHours * 3600)
        isTrackingPaused = true
        trackingPauseExpiresAt = expiry
        locationManager.isTrackingPaused = true

        addTimelineEntry(type: .trackingPaused, description: LanguageManager.shared.localized("timeline.paused"))

        // Notify server so guardians see paused status
        if let userId = currentUser?.id {
            apiClient.postQueued("/v1/location/pause", body: TrackingPauseRequest(userId: userId, paused: true, expiresAt: ISO8601DateFormatter().string(from: expiry)))
        }

        // Auto-resume timer
        trackingPauseTimer?.invalidate()
        trackingPauseTimer = Timer.scheduledTimer(withTimeInterval: Self.maxPauseDurationHours * 3600, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.resumeTracking()
            }
        }
    }

    func resumeTracking() {
        isTrackingPaused = false
        trackingPauseExpiresAt = nil
        locationManager.isTrackingPaused = false
        trackingPauseTimer?.invalidate()
        trackingPauseTimer = nil

        addTimelineEntry(type: .trackingResumed, description: LanguageManager.shared.localized("timeline.resumed"))

        // Notify server
        if let userId = currentUser?.id {
            apiClient.postQueued("/v1/location/pause", body: TrackingPauseRequest(userId: userId, paused: false))
        }

        // Send a fresh location immediately
        locationManager.requestSingleLocation()
    }

    var trackingPauseRemainingMinutes: Int {
        guard let expiry = trackingPauseExpiresAt else { return 0 }
        return max(0, Int(expiry.timeIntervalSinceNow / 60))
    }

    // MARK: - Event Handlers

    private func handleLocationUpdate(_ location: Location) {
        // Build E2E encrypted payload for each guardian who has a public key
        var encryptedPayload: E2ELocationEncryption.EncryptedPayload?
        if let firstGuardian = myGuardians.first,
           let peerKeyData = keyManager.getPeerPublicKey(userId: firstGuardian.id) {
            let payload = E2ELocationEncryption.LocationPayload(
                latitude: location.latitude,
                longitude: location.longitude,
                accuracy: location.accuracy,
                altitude: location.altitude,
                speed: location.speed,
                timestamp: location.timestamp,
                activityType: location.activityType?.rawValue
            )
            encryptedPayload = try? e2eEncryption.encrypt(
                location: payload,
                forRecipientPublicKey: peerKeyData
            )
        }

        apiClient.postQueued("/v1/location/report", body: LocationReportRequest(
            userId: currentUser?.id ?? "",
            latitude: location.latitude,
            longitude: location.longitude,
            accuracy: location.accuracy,
            altitude: location.altitude,
            speed: location.speed,
            timestamp: location.timestamp,
            isInSafeZone: location.isInSafeZone,
            safeZoneName: location.safeZoneName,
            activityType: location.activityType?.rawValue,
            encryptedPayload: encryptedPayload
        ))

        // Live Activity is updated via startLiveActivityIfNeeded / sync calls
    }

    private func handleFallCandidate() {
        #if DEBUG
        print("[Coordinator] Fall candidate detected — showing confirmation dialog")
        #endif
        // Show 60-second confirmation dialog. If user doesn't dismiss,
        // FallDetector transitions to .confirmed → handleFallConfirmed() → SOS
        fallConfirmationDeadline = Date().addingTimeInterval(60)
        showFallConfirmation = true

        // Play haptic + audio alert
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    func dismissFallConfirmation() {
        showFallConfirmation = false
        fallConfirmationDeadline = nil
        motionService.userDismissedFallAlert()
    }

    private func handleFallConfirmed() {
        showFallConfirmation = false
        fallConfirmationDeadline = nil
        triggerSOS(method: .fallDetection)
    }

    private func handleDistressDetected() {
        // Same countdown flow as fall detection — give user 60 sec to dismiss
        fallConfirmationDeadline = Date().addingTimeInterval(60)
        showFallConfirmation = true
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        // If user doesn't dismiss within 60 sec, trigger SOS
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, self.showFallConfirmation else { return }
            self.showFallConfirmation = false
            self.fallConfirmationDeadline = nil
            self.triggerSOS(method: .audioDistress)
        }
    }

    private func handleVoiceSOSCommand(phrase: String) {
        // Voice commands trigger the same confirmation countdown
        fallConfirmationDeadline = Date().addingTimeInterval(60)
        showFallConfirmation = true
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, self.showFallConfirmation else { return }
            self.showFallConfirmation = false
            self.fallConfirmationDeadline = nil
            self.triggerSOS(method: .voiceCommand)
        }
    }

    /// Guardian tapped "I've got it" on the SOS push: tell the server (which stops
    /// the calls and notifies the others), not just the local engine.
    private func handleSOSTakenOver(sosId: String) {
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "sos-acknowledge")
        Task {
            do {
                try await acknowledgeSOS(sosEventId: sosId)
            } catch {
                #if DEBUG
                print("[Coordinator] acknowledge from push failed: \(error)")
                #endif
                // Keep the acknowledgement: replay when back online
                apiClient.postQueued("/v1/sos/acknowledge", body: SOSAcknowledgeRequest(sosEventId: sosId))
            }
            await MainActor.run { UIApplication.shared.endBackgroundTask(bgTask) }
        }
    }

    private func reportHeartbeatToServer(_ signal: HeartbeatSignal) {
        apiClient.postQueued("/v1/heartbeat", body: HeartbeatRequest(
            userId: signal.userId,
            timestamp: signal.timestamp,
            source: signal.source,
            batteryLevel: signal.batteryLevel,
            batteryState: signal.batteryState,
            latitude: signal.location?.latitude,
            longitude: signal.location?.longitude,
            accuracy: signal.location?.accuracy
        ))
    }

    private func initiateVoiceCall(guardianId: String, sosEventId: String) {
        apiClient.postQueued("/v1/voice-call", body: VoiceCallRequest(
            guardianId: guardianId,
            sosEventId: sosEventId,
            protectedPersonName: currentUser?.displayName ?? LanguageManager.shared.localized("push.protectedFallback"),
            locationDescription: nil
        ))
    }

    private func sendNotification(_ request: NotificationRequest) {
        if request.priority == .critical {
            pushService.fireCriticalSOSAlert(
                protectedPersonName: currentUser?.displayName ?? LanguageManager.shared.localized("push.protectedFallback"),
                locationDescription: request.body,
                sosEventId: request.data["sos_id"] ?? ""
            )
        }
    }

    // MARK: - Device Token

    func registerDeviceToken(_ token: Data) {
        pushService.didRegisterForRemoteNotifications(withDeviceToken: token)

        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        apiClient.postQueued("/v1/device/token", body: DeviceTokenRequest(
            token: tokenString,
            platform: "ios",
            environment: {
                #if DEBUG
                return "development"
                #else
                return "production"
                #endif
            }()
        ))
    }

    // MARK: - Timeline

    func fetchTimeline() async {
        do {
            let response: TimelineResponse = try await apiClient.get("/v1/timeline")
            await MainActor.run {
                // Merge server entries with local-only entries
                let serverIds = Set(response.entries.map(\.id))
                let localOnly = timeline.filter { !serverIds.contains($0.id) }
                var merged = response.entries
                merged.append(contentsOf: localOnly)
                merged.sort { $0.timestamp > $1.timestamp }
                self.timeline = Array(merged.prefix(200))
                localStore.saveTimeline(self.timeline)
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch timeline: \(error)")
            #endif
            // Keep local timeline on failure
        }
    }

    func addTimelineEntry(type: TimelineEntryType, description: String) {
        let entry = TimelineEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            type: type,
            description: description,
            detail: nil
        )
        timeline.insert(entry, at: 0)

        // Keep last 200 entries in memory
        if timeline.count > 200 {
            timeline = Array(timeline.prefix(200))
        }
        localStore.saveTimeline(timeline)
    }

    // MARK: - Family Feed

    /// Refreshes the family circle. Concurrent calls share one request. Returns
    /// whether it reached the server; `familyFeedRefreshFailed` mirrors the last result.
    @MainActor
    @discardableResult
    func fetchFamilyPosts() async -> Bool {
        if let running = familyFetchTask { return await running.value }
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            return await self.performFamilyFetch()
        }
        familyFetchTask = task
        let ok = await task.value
        familyFetchTask = nil
        return ok
    }

    @MainActor
    private func performFamilyFetch() async -> Bool {
        let startedAt = Date()
        do {
            let lossy: LossyArray<FamilyPost> = try await apiClient.get("/v1/family/posts")
            #if DEBUG
            if lossy.droppedCount > 0 { print("[Coordinator] Skipped \(lossy.droppedCount) unreadable family posts") }
            #endif
            let keep = Set(familyConfirmedAt.filter { $0.value >= startedAt }.keys)
            familyConfirmedAt = familyConfirmedAt.filter { $0.value >= startedAt }
            familyPosts = FamilyFeedSync.merge(server: lossy.elements, local: familyPosts, keep: keep)
            familyFeedRefreshFailed = false
            familyFeedDiagnostic = "OK · \(lossy.elements.count) received · \(lossy.droppedCount) unreadable · \(Self.shortTime(Date()))"
            persistFamilyPosts()
            // The server is reachable: try the posts that didn't go out earlier
            Task { @MainActor [weak self] in await self?.retryUnsentFamilyPosts(automatic: true) }
            return true
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch family posts: \(error)")
            #endif
            // Keep what we have; the feed says it couldn't refresh
            familyFeedRefreshFailed = true
            familyFeedDiagnostic = "\(Self.diagnosticName(error)) · \(Self.shortTime(Date()))"
            return false
        }
    }

    private static func shortTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: date)
    }

    /// Error kind only — never message bodies or tokens.
    private static func diagnosticName(_ error: Error) -> String {
        guard let api = error as? APIError else { return String(describing: type(of: error)) }
        switch api {
        case .unauthorized: return "401 unauthorized"
        case .forbidden: return "403 forbidden"
        case .notFound: return "404 not found"
        case .serverError(let code): return "\(code) server error"
        case .rateLimited: return "429 rate limited"
        case .networkError(let e): return "network: \((e as NSError).code)"
        case .decoding: return "decoding error"
        default: return String(describing: api)
        }
    }

    /// Adds a post to the feed as "sending" and returns its id (nil if there is
    /// nothing to send). Photos are downsized and kept on this phone until uploaded.
    /// Then `sendFamilyPost(id:)`; if that fails the post stays here as "not sent"
    /// with Retry, and is retried after the next successful refresh.
    @MainActor
    func queueFamilyPost(text: String, images: [Data]) async -> String? {
        let id = UUID().uuidString
        let store = localStore
        let names: [String] = await Task.detached(priority: .userInitiated) {
            images.enumerated().compactMap { index, data in
                guard let jpeg = FamilyMediaEncoder.jpegForUpload(data) else { return nil }
                let name = "\(id)_\(index).jpg"
                store.saveFamilyMedia(jpeg, name: name)
                return name
            }
        }.value
        guard !text.isEmpty || !names.isEmpty else { return nil }

        let location = locationManager.bestAvailableLocation
        let post = FamilyPost(
            id: id,
            authorId: currentUser?.id ?? "",
            authorName: currentUser?.displayName ?? "",
            authorInitial: currentUser?.avatarInitial ?? "?",
            authorAvatarPath: currentUser?.avatarLocalPath,
            text: text,
            mediaURLs: [],
            createdAt: Date(),
            comments: [],
            commentCount: 0,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            locationName: currentUser?.cityName,
            delivery: FamilyPostDelivery(state: .sending, attempts: 0, pendingImages: names)
        )
        familyPosts.insert(post, at: 0)
        persistFamilyPosts()
        return id
    }

    /// Sends a queued post (also Retry from the "not sent" row), then refreshes.
    @MainActor
    func sendFamilyPost(id: String) async {
        if await deliverFamilyPost(id: id) {
            await fetchFamilyPosts()
        }
    }

    /// Deletes a post that never reached the server (nothing to tell the server).
    @MainActor
    func deleteUnsentFamilyPost(id: String) {
        guard !familyDeliveriesInFlight.contains(id) else { return }
        removeUnsentFamilyPost(id: id)
    }

    @MainActor
    private func removeUnsentFamilyPost(id: String) {
        guard let index = familyPosts.firstIndex(where: { $0.id == id }),
              let delivery = familyPosts[index].delivery else { return }
        delivery.pendingImages.forEach { localStore.deleteFamilyMedia(name: $0) }
        familyPosts.remove(at: index)
        persistFamilyPosts()
    }

    @MainActor
    func retryUnsentFamilyPosts(automatic: Bool) async {
        let due = familyPosts.filter { post in
            guard let d = post.delivery, d.state == .failed else { return false }
            return !automatic || d.attempts < FamilyFeedSync.maxAutomaticAttempts
        }
        // Oldest first, so they keep their order on the server
        for post in due.reversed() {
            guard await deliverFamilyPost(id: post.id) else { break }
        }
    }

    /// Uploads the post's remaining photos, then creates it under its own id (so a
    /// retry after a lost response can't duplicate it). Returns true once it's on the server.
    @MainActor
    @discardableResult
    func deliverFamilyPost(id: String) async -> Bool {
        guard !familyDeliveriesInFlight.contains(id),
              let start = familyPosts.firstIndex(where: { $0.id == id }),
              familyPosts[start].delivery != nil else { return false }
        familyDeliveriesInFlight.insert(id)
        defer { familyDeliveriesInFlight.remove(id) }

        func update(_ change: (inout FamilyPost) -> Void) {
            guard let i = familyPosts.firstIndex(where: { $0.id == id }) else { return }
            change(&familyPosts[i])
            persistFamilyPosts()
        }
        func fail() -> Bool {
            update { $0.delivery?.state = .failed }
            return false
        }

        update {
            $0.delivery?.state = .sending
            $0.delivery?.attempts += 1
        }

        // Photos first; each one uploaded is moved from the phone to the post
        for name in familyPosts[start].delivery?.pendingImages ?? [] {
            guard let data = localStore.loadFamilyMedia(name: name) else {
                update { $0.delivery?.pendingImages.removeAll { $0 == name } }
                continue
            }
            do {
                let url = try await uploadMedia(data: data, mimeType: "image/jpeg")
                update {
                    $0.mediaURLs.append(url)
                    $0.delivery?.pendingImages.removeAll { $0 == name }
                }
                localStore.deleteFamilyMedia(name: name)
            } catch {
                #if DEBUG
                print("[Coordinator] Family photo upload failed: \(error)")
                #endif
                return fail()
            }
        }

        guard let post = familyPosts.first(where: { $0.id == id }), post.delivery != nil else { return false }
        let media = FamilyFeedSync.remoteMediaURLs(post.mediaURLs)
        guard !post.text.isEmpty || !media.isEmpty else {
            // Nothing left to send (photos gone from the phone and no text)
            removeUnsentFamilyPost(id: id)
            return false
        }
        do {
            let response: CreatePostResponse = try await apiClient.post(
                "/v1/family/posts",
                body: CreatePostRequest(text: post.text, mediaURLs: media, latitude: post.latitude,
                                        longitude: post.longitude, locationName: post.locationName,
                                        clientPostId: post.id)
            )
            update {
                $0.id = response.postId
                $0.mediaURLs = media
                $0.delivery = nil
            }
            familyConfirmedAt[response.postId] = Date()
            return true
        } catch {
            #if DEBUG
            print("[Coordinator] Family post not sent: \(error)")
            #endif
            return fail()
        }
    }

    /// Returns false when the reply didn't reach the server (the caller keeps the text).
    @MainActor
    func addComment(postId: String, text: String) async -> Bool {
        do {
            let response: AddCommentResponse = try await apiClient.post(
                "/v1/family/posts/\(postId)/comments",
                body: AddCommentRequest(text: text)
            )
            let comment = FamilyComment(
                id: response.commentId,
                authorId: currentUser?.id ?? "",
                authorName: currentUser?.displayName ?? "",
                authorInitial: currentUser?.avatarInitial ?? "?",
                authorAvatarPath: currentUser?.avatarLocalPath,
                text: text,
                createdAt: Date()
            )
            if let idx = familyPosts.firstIndex(where: { $0.id == postId }) {
                familyPosts[idx].comments.append(comment)
                familyPosts[idx].commentCount += 1
            }
            persistFamilyPosts()
            return true
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to add comment: \(error)")
            #endif
            return false
        }
    }

    func persistFamilyPosts() {
        localStore.saveFamilyPosts(familyPosts)
    }

    /// Uploads one (already downsized) photo; returns its https URL.
    func uploadMedia(data: Data, mimeType: String) async throws -> String {
        let base64 = data.base64EncodedString()
        let response: MediaUploadResponse = try await apiClient.post(
            "/v1/family/upload",
            body: ["data": base64, "mimeType": mimeType]
        )
        guard let url = FamilyFeedSync.remoteMediaURLs([response.url]).first else {
            throw APIError.validation("upload returned no usable URL")
        }
        return url
    }

    // MARK: - Notification Preferences

    static let sosCriticalAlertsKey = "notif_sos_critical"

    /// Guardian's in-app choice for SOS Critical Alerts (default on, matching
    /// the server default for guardians linked before this setting existed).
    static var sosCriticalAlertsEnabled: Bool {
        UserDefaults.standard.object(forKey: sosCriticalAlertsKey) as? Bool ?? true
    }

    /// Records the guardian's choice, syncs it to the server (which decides
    /// critical vs time-sensitive for SOS pushes) and, when enabled, asks iOS
    /// for Critical Alerts permission.
    func setSOSCriticalAlerts(enabled: Bool) {
        defaults.set(enabled, forKey: Self.sosCriticalAlertsKey)
        syncNotificationPrefs()
        if enabled {
            pushService.requestCriticalAlertPermission()
        }
    }

    func syncNotificationPrefs() {
        let prefs = NotificationPrefsRequest(
            sosAlerts: defaults.object(forKey: "notif_sos_alerts") as? Bool ?? true,
            sosCriticalAlerts: defaults.object(forKey: Self.sosCriticalAlertsKey) as? Bool ?? true,
            checkinReminder: defaults.object(forKey: "notif_checkin_reminder") as? Bool ?? true,
            checkinOverdue: defaults.object(forKey: "notif_checkin_overdue") as? Bool ?? true,
            familyFeed: defaults.object(forKey: "notif_family_feed") as? Bool ?? true
        )
        Task {
            do {
                let _: SuccessResponse = try await apiClient.put(
                    "/v1/user/notification-preferences",
                    body: prefs
                )
            } catch {
                #if DEBUG
                print("[Coordinator] Failed to sync notification prefs: \(error)")
                #endif
            }
        }
    }

    // MARK: - Guardian Management

    // MARK: - Invites

    /// Open the invite confirmation sheet (RootView presents it). Used by invite
    /// links, the family circle, Settings and the setup wizard.
    func presentInviteAccept(code: String? = nil) {
        pendingInviteCode = code.flatMap(DeepLinkRouter.normalizedInviteCode)
        showInviteAccept = true
    }

    /// - Parameter inviterRole: what I become once the invite is accepted
    ///   (`.protected_`: the other person guards me; `.guardian`: I guard them).
    func createInviteCode(inviterRole: UserRole) async throws -> CreateInviteResponse {
        let response: CreateInviteResponse = try await apiClient.post(
            "/v1/invite/create",
            body: CreateInviteRequest(inviterRole: inviterRole)
        )
        return response
    }

    func previewInvite(code: String) async throws -> InvitePreviewResponse {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? code
        return try await apiClient.getReportingCode("/v1/invite/preview?code=\(encoded)")
    }

    /// Accept an invite; the invite decides who guards whom. Afterwards the
    /// profile (the server may have moved my home view) and family are refreshed.
    func acceptInvite(code: String, criticalAlertConsent: Bool?) async throws -> AcceptInviteResponse {
        let response: AcceptInviteResponse = try await apiClient.postReportingCode(
            "/v1/invite/accept",
            body: AcceptInviteRequest(code: code, criticalAlertConsent: criticalAlertConsent)
        )
        let iAmGuardian = response.acceptorRole.map { $0 == UserRole.guardian.rawValue }
            ?? (response.guardianId == authManager.currentUserId)
        await MainActor.run {
            if iAmGuardian, let consent = criticalAlertConsent {
                setSOSCriticalAlerts(enabled: consent)
            }
        }
        await fetchUserProfile()
        if iAmGuardian {
            await fetchProtectedPersons()
        } else {
            await fetchGuardians()
        }
        return response
    }

    func updateGuardianPermissions(guardianId: String, permissions: GuardianPermissions) async throws {
        let _: SuccessResponse = try await apiClient.put(
            "/v1/protected/guardians/\(guardianId)/permissions",
            body: UpdatePermissionsRequest(
                canSeeLocation: permissions.canSeeLocation,
                canSeeBattery: permissions.canSeeBattery,
                canSeeHealth: permissions.canSeeHealth,
                canSeePhoneActivity: permissions.canSeePhoneActivity,
                canHearEmergencyAudio: permissions.canHearEmergencyAudio
            )
        )
    }

    func removeGuardian(guardianId: String) async throws {
        let _: SuccessResponse = try await apiClient.delete("/v1/protected/guardians/\(guardianId)")
        await MainActor.run {
            myGuardians.removeAll { $0.id == guardianId }
            localStore.saveGuardians(myGuardians)
        }
    }

    // MARK: - Emergency Contacts

    func fetchEmergencyContacts() async -> [LocalEmergencyContact] {
        do {
            let contacts: [LocalEmergencyContact] = try await apiClient.get("/v1/emergency-contacts")
            return contacts
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch emergency contacts: \(error)")
            #endif
            return []
        }
    }

    func saveEmergencyContacts(_ contacts: [LocalEmergencyContact]) async {
        do {
            let _: SuccessResponse = try await apiClient.put(
                "/v1/emergency-contacts",
                body: contacts
            )
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to save emergency contacts: \(error)")
            #endif
        }
    }

    // MARK: - Subscription

    func fetchSubscription() async {
        await storeKitManager.refreshSubscriptionStatus()
    }

    // MARK: - Risk Score Refresh

    func refreshRiskScores() {
        for person in protectedPersons {
            let score = baselineScorer.computeRiskScore(
                personId: person.id,
                lastCheckIn: person.lastCheckIn,
                lastHeartbeat: person.lastPhoneActivity,
                currentLocation: person.lastKnownLocation,
                batteryLevel: person.batteryLevel,
                batteryState: person.batteryState,
                regionRiskLevel: 0.3,
                timeZone: person.user.timeZone
            )
            currentRiskScores[person.id] = score
        }
    }

    // MARK: - Duty Coverage Refresh

    func refreshDutyCoverage() {
        guard let firstPerson = protectedPersons.first else { return }
        currentCoverage = dutyScheduler.buildDayCoverage(
            protectedPerson: firstPerson,
            guardians: firstPerson.guardians
        )
    }

    // MARK: - Widget Sync (debounced, background)

    private var widgetSyncTask: Task<Void, Never>?

    func syncWidgetState() {
        guard !isDemo else { return }
        // Debounce: cancel any pending sync and schedule a new one after 0.3s
        widgetSyncTask?.cancel()
        widgetSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
            guard !Task.isCancelled else { return }

            // Capture data on main actor
            let persons = protectedPersons.map { p in
                WidgetProtectedPerson(
                    id: p.id,
                    displayName: p.user.displayName,
                    initial: p.user.avatarInitial,
                    status: p.status.rawValue,
                    lastCheckIn: p.lastCheckIn,
                    batteryLevel: p.batteryLevel,
                    homeTimerDeadline: nil
                )
            }
            let isLoggedIn = authState != .loggedOut && authState != .unknown
            let role = userRole.rawValue
            let userName = currentUser?.displayName
            let guardianCount = myGuardians.count
            let lastCheckIn = timeline.first(where: { $0.type == .checkIn })?.timestamp
            let sosActive = activeSOSEvent != nil
            let sosTriggeredAt = activeSOSEvent?.triggeredAt
            let emergencyPhone: String? = localEmergencyNumber

            // Move encoding + widget reload to background
            Task.detached(priority: .utility) {
                let emergencyMeds: [WidgetMedication] = {
                    guard let card = MedicalCardCache.load() else { return [] }
                    return card.emergencyMedications.map {
                        WidgetMedication(id: $0.id, name: $0.name, location: $0.storageLocation, dosage: $0.dosage)
                    }
                }()

                let state = WidgetState(
                    isLoggedIn: isLoggedIn,
                    userRole: role,
                    userName: userName,
                    guardianCount: guardianCount,
                    lastCheckInDate: lastCheckIn,
                    sosActive: sosActive,
                    sosTriggeredAt: sosTriggeredAt,
                    homeTimerActive: false,
                    homeTimerDeadline: nil,
                    homeTimerLabel: nil,
                    protectedPersons: persons,
                    emergencyMedications: emergencyMeds,
                    emergencyPhone: emergencyPhone,
                    updatedAt: Date()
                )

                WidgetDataStore.write(state)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    // MARK: - Shared Coders (Fix 5: reuse instead of allocating new ones)

    static let sharedEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let sharedDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return d
    }()

}
