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
    @Published var currentRiskScores: [String: BaselineScorer.RiskScore] = [:]
    @Published var currentCoverage: DutyScheduler.DayCoverage?
    @Published var authState: AuthManager.AuthState = .unknown
    @Published var showSignup = false
    @Published var showSetupWizard = false
    @Published var signupPhone: String?
    @Published var signupCountry: CountryCode?
    @Published var timeline: [TimelineEntry] = []
    @Published var familyPosts: [FamilyPost] = []
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
    @Published var trackingPauseExpiresAt: Date?
    private var trackingPauseTimer: Timer?

    // MARK: - Infrastructure

    let offlineQueue = OfflineQueue()
    let apiClient: APIClient
    let authManager: AuthManager
    let localStore = LocalStore.shared

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
    let paymentMethodManager: PaymentMethodManager
    let mapTileCacheManager = MapTileCacheManager()
    let locationBatchUploader = LocationBatchUploader()
    let voiceNoteService = VoiceNoteService()
    let bleTrackerService = BLETrackerService.shared
    let tripRecordingService = TripRecordingService()

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // Register default: lock screen card enabled by default
        UserDefaults.standard.register(defaults: ["lockscreen_card_enabled": true])

        let config = APIClient.Config(
            baseURL: Self.resolveBaseURL()
        )
        apiClient = APIClient(config: config, offlineQueue: offlineQueue)
        #if DEBUG
        print("[AppCoordinator] API base URL: \(config.baseURL)")
        #endif
        authManager = AuthManager(api: apiClient)
        storeKitManager = StoreKitManager(apiClient: apiClient)
        paymentMethodManager = PaymentMethodManager(apiClient: apiClient)

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
        connectivity.start()

        // Sync initial auth state before Combine subscription delivers asynchronously
        authState = authManager.state

        // Wire silent alarm service
        SilentAlarmService.shared.configure(apiClient: apiClient)
        SilentAlarmService.registerNotificationCategory()

        // Wire BLE tracker service
        bleTrackerService.configure(
            apiClient: apiClient,
            onSOSTrigger: { [weak self] in
                self?.triggerSOS(method: .bluetoothButton)
            },
            onSeparationAlert: { [weak self] tag in
                self?.addTimelineEntry(type: .guardianAlert, description: "蓝牙标签「\(tag.name)」超出范围")
                self?.notifyGuardiansOfSeparation(tagName: tag.name)
            },
            onReunion: { [weak self] tag in
                self?.addTimelineEntry(type: .enteredSafeZone, description: "蓝牙标签「\(tag.name)」重新进入范围")
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

        wireServices()
        restoreLocalState()
        observeAuthState()
        observeLanguageChange()
        // Start Live Activity after restoring local state (so we have cached user/guardian data)
        if case .loggedIn = authState,
           UserDefaults.standard.bool(forKey: "lockscreen_card_enabled"),
           currentUser != nil {
            startLiveActivityIfNeeded()
        }
    }

    // MARK: - Language Change Observer

    private func observeLanguageChange() {
        NotificationCenter.default.addObserver(
            forName: LanguageManager.languageDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.syncLocaleToServer()
            // Restart Live Activity so it picks up the new language
            self.liveActivityManager.endAllActivities()
            if UserDefaults.standard.bool(forKey: "lockscreen_card_enabled") {
                self.startLiveActivityIfNeeded()
            }
        }
    }

    // MARK: - Base URL

    private static func resolveBaseURL() -> String {
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
        familyPosts = localStore.loadFamilyPosts()

        // Load safe zones into location manager
        let zones = localStore.loadSafeZones()
        if !zones.isEmpty {
            locationManager.updateSafeZones(zones)
        }
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
                    UserDefaults.standard.set(userId, forKey: "currentUserId")
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
                    self.onLoginComplete()
                case .loggedOut:
                    self.onLogout()
                case .unknown:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func onLoginComplete() {
        // Flush any queued offline requests
        Task { await apiClient.flushOfflineQueue() }

        // Location permission is requested only once someone is signed in
        if UserDefaults.standard.bool(forKey: "onboardingComplete") {
            locationManager.start()
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
                if UserDefaults.standard.bool(forKey: "lockscreen_card_enabled") {
                    startLiveActivityIfNeeded()
                }
            }
        }

        // Sync subscription status from StoreKit (catches overnight expirations/renewals)
        Task { await storeKitManager.refreshSubscriptionStatus() }

        // Sync local notification preferences to server
        syncNotificationPrefs()

        syncWidgetState()

        // Apply any pending deep link that arrived before login
        if let pending = pendingDeepLink {
            pendingDeepLink = nil
            applyDeepLink(pending)
        }
    }

    private func onLogout() {
        liveActivityManager.endAllActivities()
        currentUser = nil
        protectedPersons = []
        myGuardians = []
        activeSOSEvent = nil
        timeline = []
        familyPosts = []
        selectedHotline = nil
        showSignup = false
        signupPhone = nil
        signupCountry = nil
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
        WidgetDataStore.clear()
        WidgetCenter.shared.reloadAllTimelines()

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
            UserDefaults.standard.removeObject(forKey: key)
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
        guard let defaults = UserDefaults(suiteName: WidgetDataStore.appGroupId) else { return }
        guard defaults.bool(forKey: "widget_sos_pending") else { return }

        // Clear the flag immediately to prevent re-triggering
        defaults.set(false, forKey: "widget_sos_pending")

        // Only honor if the intent was within the last 60 seconds
        let timestamp = defaults.double(forKey: "widget_sos_timestamp")
        let age = Date().timeIntervalSince1970 - timestamp
        guard age < 60, age > 0 else { return }

        #if DEBUG
        print("[AppCoordinator] Widget SOS intent detected — triggering SOS")
        #endif
        triggerSOS(method: .widgetTap)
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
            pendingInviteCode = code
            showInviteAccept = true
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
    var localEmergencyNumber: String {
        if let n = selectedHotline?.emergency, !n.isEmpty { return n }
        let country = currentUser?.countryCode.isEmpty == false ? currentUser!.countryCode : (Locale.current.region?.identifier ?? "")
        return RegionalEmergencyInfo.forCountry(country).numbers.first?.number ?? "112"
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
        if let data = UserDefaults.standard.data(forKey: "selected_hotline"),
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
        UserDefaults.standard.removeObject(forKey: "selected_hotline")
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
            UserDefaults.standard.set(data, forKey: "selected_hotline")
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
            self?.addTimelineEntry(type: .enteredSafeZone, description: "进入安全区「\(zone.name)」")
        }

        locationManager.onSafeZoneExit = { [weak self] zone in
            self?.addTimelineEntry(type: .leftSafeZone, description: "离开安全区「\(zone.name)」")
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
        audioCoordinator.distressDetectionEnabled = UserDefaults.standard.bool(forKey: "distress_detection_enabled")
        audioCoordinator.voiceCommandEnabled = UserDefaults.standard.bool(forKey: "voice_command_enabled")

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
                description: "守护者已接手处理"
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
        guard case .loggedIn = authState else { return }
        guard UserDefaults.standard.bool(forKey: "lockscreen_card_enabled") else { return }
        if !liveActivityManager.isRunning {
            startLiveActivityIfNeeded()
        }
    }

    func startLiveActivityIfNeeded() {
        let emergencyPhone = selectedHotline?.emergency ?? "911"

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
                emergencyLabel: selectedHotline?.selectedLabel ?? "911",
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

    // MARK: - SOS Trigger

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
        locationManager.enterSOSMode()

        // Lock-screen card shows SOS — but a duress / disguise SOS must stay invisible and silent
        if !method.isSilent {
            liveActivityManager.triggerSOS(
                localEmergencyNumber: selectedHotline?.emergency ?? "911"
            )
        }

        addTimelineEntry(type: .sosTriggered, description: "触发紧急求助（\(method.rawValue)）")

        #if BETA
        // Beta: simulate escalation — skip real API call and immediately acknowledge
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.activeSOSEvent?.escalationState = .acknowledged
            self?.addTimelineEntry(type: .sosResolved, description: "[Beta 模拟] SOS 自动确认，未发送真实通知")
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

    /// Protected person: what the server has actually done for my SOS.
    func refreshOwnSOSStatus() async {
        guard activeSOSEvent != nil else { return }
        do {
            let response: ActiveSOSResponse = try await apiClient.get("/v1/sos/active")
            await MainActor.run {
                self.ownSOSStatus = response.sos
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
        locationManager.exitSOSMode()

        // Restore lock screen to normal
        liveActivityManager.cancelSOS()

        addTimelineEntry(type: .sosResolved, description: "取消了紧急求助")

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
        let name = currentUser?.displayName ?? "我的位置"
        let mapURL = "https://maps.apple.com/?ll=\(lat),\(lng)&q=\(name)"
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

        addTimelineEntry(type: .checkIn, description: note ?? "报平安")
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

        addTimelineEntry(type: .trackingPaused, description: "暂停了位置共享")

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

        addTimelineEntry(type: .trackingResumed, description: "恢复了位置共享")

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
            protectedPersonName: currentUser?.displayName ?? "被守护者",
            locationDescription: nil
        ))
    }

    private func sendNotification(_ request: NotificationRequest) {
        if request.priority == .critical {
            pushService.fireCriticalSOSAlert(
                protectedPersonName: currentUser?.displayName ?? "被守护者",
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

    func fetchFamilyPosts() async {
        do {
            let serverPosts: [FamilyPost] = try await apiClient.get("/v1/family/posts")
            await MainActor.run {
                // Merge: keep local-only posts, add/update server posts
                let serverIds = Set(serverPosts.map(\.id))
                let localOnly = familyPosts.filter { !serverIds.contains($0.id) }
                var merged = serverPosts
                merged.append(contentsOf: localOnly)
                merged.sort { $0.createdAt > $1.createdAt }
                self.familyPosts = merged
                persistFamilyPosts()
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch family posts: \(error)")
            #endif
            // On failure, keep existing local posts — do NOT clear
        }
    }

    func createFamilyPost(text: String, mediaURLs: [String], latitude: Double? = nil, longitude: Double? = nil, locationName: String? = nil) async throws {
        let response: CreatePostResponse = try await apiClient.post(
            "/v1/family/posts",
            body: CreatePostRequest(text: text, mediaURLs: mediaURLs)
        )
        // Add to local state immediately
        let post = FamilyPost(
            id: response.postId,
            authorId: currentUser?.id ?? "",
            authorName: currentUser?.displayName ?? "",
            authorInitial: currentUser?.avatarInitial ?? "?",
            authorAvatarPath: currentUser?.avatarLocalPath,
            text: text,
            mediaURLs: mediaURLs,
            createdAt: Date(),
            comments: [],
            commentCount: 0,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName
        )
        await MainActor.run {
            familyPosts.insert(post, at: 0)
            persistFamilyPosts()
        }
    }

    func addComment(postId: String, text: String) async {
        do {
            let _: AddCommentResponse = try await apiClient.post(
                "/v1/family/posts/\(postId)/comments",
                body: AddCommentRequest(text: text)
            )
            // Add comment locally
            let comment = FamilyComment(
                id: UUID().uuidString,
                authorId: currentUser?.id ?? "",
                authorName: currentUser?.displayName ?? "",
                authorInitial: currentUser?.avatarInitial ?? "?",
                authorAvatarPath: currentUser?.avatarLocalPath,
                text: text,
                createdAt: Date()
            )
            await MainActor.run {
                if let idx = familyPosts.firstIndex(where: { $0.id == postId }) {
                    familyPosts[idx].comments.append(comment)
                    familyPosts[idx].commentCount += 1
                }
                persistFamilyPosts()
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to add comment: \(error)")
            #endif
        }
    }

    func persistFamilyPosts() {
        localStore.saveFamilyPosts(familyPosts)
    }

    func uploadMedia(data: Data, mimeType: String) async throws -> String {
        // For now, use a simple base64 upload endpoint.
        // In production, this would upload to Firebase Storage directly.
        let base64 = data.base64EncodedString()
        let response: MediaUploadResponse = try await apiClient.post(
            "/v1/family/upload",
            body: ["data": base64, "mimeType": mimeType]
        )
        return response.url
    }

    // MARK: - Notification Preferences

    func syncNotificationPrefs() {
        let prefs = NotificationPrefsRequest(
            sosAlerts: UserDefaults.standard.object(forKey: "notif_sos_alerts") as? Bool ?? true,
            checkinReminder: UserDefaults.standard.object(forKey: "notif_checkin_reminder") as? Bool ?? true,
            checkinOverdue: UserDefaults.standard.object(forKey: "notif_checkin_overdue") as? Bool ?? true,
            familyFeed: UserDefaults.standard.object(forKey: "notif_family_feed") as? Bool ?? true
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

    func createInviteCode() async throws -> CreateInviteResponse {
        let response: CreateInviteResponse = try await apiClient.post(
            "/v1/invite/create",
            body: CreateInviteRequest(role: userRole.rawValue)
        )
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
            let emergencyPhone = selectedHotline?.emergency

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
