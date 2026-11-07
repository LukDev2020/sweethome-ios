import SwiftUI
import Combine
import CoreLocation

// MARK: - Explore Mode Controller
//
// Owns one demo session: a separate AppCoordinator wired to DemoURLProtocol, the
// in-memory DemoStore, storage overlays, the guided tour, the scenario engine,
// and the progress checklist. Exiting tears all of it down and restores the
// logged-out app exactly as it was — it never goes through the real logout path.

enum DemoLesson: String, CaseIterable, Identifiable {
    case dashboard, respond, practiceSOS, homeSafe, coverage, records
    var id: String { rawValue }
    var titleKey: String { "explore.lesson.\(rawValue)" }
    /// Where to go to learn it.
    var role: DemoRole {
        switch self {
        case .practiceSOS, .homeSafe: return .mom
        default: return .sarah
        }
    }
}

struct DemoNotification: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let body: String
    enum Action: Equatable { case openAlert(personId: String), none }
    let action: Action
}

enum DemoSheet: String, Identifiable {
    case dutySchedule, claimMaterials
    var id: String { rawValue }
}

@MainActor
final class ExploreModeController: ObservableObject {

    static let shared = ExploreModeController()

    // MARK: Published state

    @Published private(set) var isActive = false
    @Published private(set) var role: DemoRole = .mom
    @Published private(set) var stepIndex: [DemoRole: Int] = [.mom: 0, .sarah: 0, .kai: 0]
    @Published var isTourVisible = true
    @Published var notification: DemoNotification?
    @Published var showHandoff = false
    @Published var showChecklist = false
    @Published private(set) var learned: Set<DemoLesson> = []
    @Published var anchorFrames: [String: CGRect] = [:]
    @Published var blockedFeature: String?
    @Published var presentedSheet: DemoSheet?
    /// True while the app (under the overlay) shows a sheet or alert — tips step aside.
    @Published private(set) var isAppPresentingModal = false

    /// Where the person dragged the "Show tip" button (offset from its resting place),
    /// kept for the whole demo so it stays out of the way.
    @Published var tipButtonOffset: CGSize = .zero

    /// On-screen frames of the overlay's tappable parts (tip card, banner, …).
    /// The overlay window only takes touches inside these; everything else passes through.
    private(set) var overlayRegions: [String: CGRect] = [:]
    private var modalPoll: Timer?

    private(set) var coordinator: AppCoordinator?
    private(set) var store: DemoStore?
    private var defaultsSuiteName: String?
    private(set) var overlayWindow: UIWindow?
    private var cancellables = Set<AnyCancellable>()
    private var blockedObserver: NSObjectProtocol?

    /// Set by the app: opens real sign-up after the demo ends.
    var onSetUpRealFamily: (() -> Void)?

    // MARK: Lifecycle

    func start(role: DemoRole) {
        guard !isActive else { return }
        beginIsolation()

        let dataset = DemoDataset.build()
        let store = DemoStore(dataset: dataset, currentUserId: role.userId)
        store.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        DemoURLProtocol.store = store
        self.store = store

        let suite = "com.shoudeng.explore.\(UUID().uuidString)"
        defaultsSuiteName = suite
        let coordinator = AppCoordinator(environment: .init(
            isDemo: true,
            baseURL: DemoURLProtocol.baseURL,
            sessionConfiguration: DemoURLProtocol.sessionConfiguration(),
            offlineQueue: OfflineQueue(fileURL: nil),
            defaults: UserDefaults(suiteName: suite) ?? .standard
        ))
        self.coordinator = coordinator

        learned = []
        stepIndex = [.mom: 0, .sarah: 0, .kai: 0]
        isTourVisible = true
        showChecklist = false
        showHandoff = false
        notification = nil
        self.role = role
        isActive = true
        coordinator.beginDemoPersona(userId: role.userId, role: role.userRole, location: role.homeCoordinate)

        blockedObserver = NotificationCenter.default.addObserver(
            forName: ExploreMode.blockedFeatureNotification, object: nil, queue: .main
        ) { [weak self] note in
            let feature = note.object as? String
            Task { @MainActor in self?.showBlocked(feature) }
        }
        installOverlayWindow()
        enterStep()
    }

    /// See the other phone without telling any server (no switchRole()).
    func switchRole(to newRole: DemoRole) {
        guard isActive, let coordinator, let store, newRole != role else { return }
        role = newRole
        store.currentUserId = newRole.userId
        notification = nil
        coordinator.beginDemoPersona(userId: newRole.userId, role: newRole.userRole, location: newRole.homeCoordinate)
        if newRole == .mom, let own = store.sosStatus(personId: DemoDataset.momId) {
            coordinator.adoptDemoOwnSOS(own)
        }
        enterStep()
        // A sample lock-screen card from the other phone is wrong now
        if coordinator.liveActivityManager.isRunning {
            coordinator.liveActivityManager.endAllActivities()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5)) // the new persona's data loads
                if self.isActive { self.coordinator?.startLiveActivityIfNeeded() }
            }
        }
    }

    /// Own teardown: restores the logged-out app without touching real data.
    func exit(setUpRealFamily: Bool = false) {
        guard isActive else { return }
        isActive = false
        overlayWindow?.isHidden = true
        overlayWindow = nil
        modalPoll?.invalidate()
        modalPoll = nil
        overlayRegions = [:]
        isAppPresentingModal = false
        if let blockedObserver { NotificationCenter.default.removeObserver(blockedObserver) }
        blockedObserver = nil
        cancellables.removeAll()
        // The demo's sample lock-screen card goes with it
        coordinator?.liveActivityManager.endAllActivities()
        coordinator = nil
        store = nil
        DemoURLProtocol.store = nil
        endIsolation()
        anchorFrames = [:]
        presentedSheet = nil
        if setUpRealFamily { onSetUpRealFamily?() }
    }

    // MARK: Isolation

    private func beginIsolation() {
        ExploreMode.setActive(true)
        KeychainHelper.shared.beginOverlay()
        LocalStore.shared.beginOverlay()
        MedicalCardCache.beginOverlay()
        WidgetDataStore.writesSuspended = true
    }

    private func endIsolation() {
        KeychainHelper.shared.endOverlay()
        LocalStore.shared.endOverlay()
        MedicalCardCache.endOverlay()
        WidgetDataStore.writesSuspended = false
        if let suite = defaultsSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        defaultsSuiteName = nil
        ExploreMode.setActive(false)
    }

    // MARK: Tour

    var steps: [DemoTourStep] { DemoTour.steps(for: role) }

    var currentStep: DemoTourStep? {
        let idx = stepIndex[role] ?? 0
        return steps.indices.contains(idx) ? steps[idx] : nil
    }

    var currentStepNumber: Int { (stepIndex[role] ?? 0) + 1 }

    func next() {
        guard let step = currentStep else { return }
        if let lesson = step.teaches, step.completion == nil { learn(lesson) }
        advance()
    }

    func back() {
        let idx = stepIndex[role] ?? 0
        guard idx > 0 else { return }
        stepIndex[role] = idx - 1
        enterStep()
    }

    func performPrimary() {
        guard let step = currentStep else { return }
        switch step.action {
        case .next:
            next()
        case .tryIt:
            // The user does it on the real control; the tip stays until it happens
            break
        case .openAlert:
            openMomAlert()
            advance()
        case .openSheet(let sheet):
            presentedSheet = sheet
            if let lesson = step.teaches { learn(lesson) }
            advance()
        }
    }

    private func advance() {
        let idx = (stepIndex[role] ?? 0) + 1
        stepIndex[role] = idx
        if idx >= steps.count {
            isTourVisible = false
            // The checklist is the Chen family story; Kai's rider tour just ends
            showChecklist = role != .kai
        } else {
            enterStep()
        }
    }

    private func enterStep() {
        guard let step = currentStep else { return }
        isTourVisible = true
        // Scenario: the respond step needs an SOS on the guardian's dashboard
        if step.id == "sarah.respond", store?.activeSOS(for: DemoDataset.momId) == nil {
            sosArrives()
        }
        if step.id == "sarah.ack", coordinator?.pendingAlertPersonId == nil {
            openMomAlert()
        }
        Task { await refreshCurrentPhone() }
    }

    func jump(to lesson: DemoLesson) {
        showChecklist = false
        if lesson.role != role { switchRole(to: lesson.role) }
        if let idx = DemoTour.steps(for: lesson.role).firstIndex(where: { $0.teaches == lesson }) {
            stepIndex[lesson.role] = idx
        }
        enterStep()
    }

    private func learn(_ lesson: DemoLesson) {
        learned.insert(lesson)
    }

    // MARK: Scenario engine (scripted events into the coordinator)

    /// Mom's SOS reaches Sarah's phone.
    func sosArrives() {
        guard let store else { return }
        store.triggerSOS(personId: DemoDataset.momId)
    }

    /// Mom taps Home Safe (seen from Sarah's phone).
    func homeSafeArrives() {
        store?.recordCheckIn(userId: DemoDataset.momId)
    }

    func batteryDrops() {
        store?.setDadBattery(0.09)
        let t = DemoText(language: LanguageManager.shared.current)
        notify(String(format: LanguageManager.shared.localized("explore.notif.battery.title"), t.dadName),
               LanguageManager.shared.localized("explore.notif.battery.body"), .none)
        Task { await refreshCurrentPhone() }
    }

    func missedCheckIn() {
        store?.setDadStatus(.overdue)
        let t = DemoText(language: LanguageManager.shared.current)
        notify(String(format: LanguageManager.shared.localized("explore.notif.missed.title"), t.dadName),
               LanguageManager.shared.localized("explore.notif.missed.body"), .none)
        Task { await refreshCurrentPhone() }
    }

    private func handle(_ event: DemoStore.DemoEvent) {
        let lm = LanguageManager.shared
        let t = DemoText(language: lm.current)
        switch event {
        case .checkedIn(let personId, let at):
            guard personId == DemoDataset.momId else { return }
            learn(.homeSafe)
            let time = DateFormatter.localizedString(from: at, dateStyle: .none, timeStyle: .short)
            notify(String(format: lm.localized("explore.notif.homeSafe.title"), t.momName),
                   String(format: lm.localized("explore.notif.homeSafe.body"), t.chengdu, time, t.sarahName, t.kevinName, t.lucyName),
                   .none)
            if currentStep?.completion == .homeSafe { advance() }
        case .sosTriggered(let personId):
            guard personId == DemoDataset.momId else { return }
            if role == .mom {
                learn(.practiceSOS)
                // Let the SOS screen sink in, then hand off to Toronto
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                    guard let self, self.isActive, self.role == .mom else { return }
                    self.isTourVisible = false
                    self.showHandoff = true
                }
            } else {
                notify(String(format: lm.localized("explore.notif.sos.title"), t.momName),
                       String(format: lm.localized("explore.notif.sos.body"), DemoText(language: lm.current).momAddress, 82),
                       .openAlert(personId: DemoDataset.momId))
            }
            Task { await refreshCurrentPhone() }
        case .sosAcknowledged:
            learn(.respond)
            if currentStep?.completion == .acknowledged { advance() }
            Task { await refreshCurrentPhone() }
        case .sosResolved:
            Task { await refreshCurrentPhone() }
        }
    }

    /// Hand-off button: "See Sarah's phone →"
    func continueToGuardian() {
        showHandoff = false
        switchRole(to: .sarah)
        if let idx = DemoTour.steps(for: .sarah).firstIndex(where: { $0.id == "sarah.respond" }) {
            stepIndex[.sarah] = idx
        }
        learn(.dashboard)
        let lm = LanguageManager.shared
        let t = DemoText(language: lm.current)
        notify(String(format: lm.localized("explore.notif.sos.title"), t.momName),
               String(format: lm.localized("explore.notif.sos.body"), t.momAddress, 82),
               .openAlert(personId: DemoDataset.momId))
        enterStep()
    }

    func tapNotification() {
        guard let n = notification else { return }
        notification = nil
        if case .openAlert = n.action {
            openMomAlert()
            if currentStep?.id == "sarah.respond" { advance() }
        }
    }

    /// Present Mom's alert screen on Sarah's phone. Deferred a beat so it also
    /// works right after a side switch, when the guardian tabs are just appearing.
    private func openMomAlert() {
        Task { await coordinator?.fetchGuardianSOS(personId: DemoDataset.momId) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isActive, self.role == .sarah else { return }
            self.coordinator?.pendingAlertPersonId = DemoDataset.momId
        }
    }

    private func notify(_ title: String, _ body: String, _ action: DemoNotification.Action) {
        let n = DemoNotification(title: title, body: body, action: action)
        notification = n
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            if self?.notification == n { self?.notification = nil }
        }
    }

    /// "Not started in the demo: the safety timer". Shown as a short alert from the app's
    /// own window: the overlay window's banner didn't always redraw (iOS 27), so pressing
    /// Start on a blocked feature seemed to do nothing.
    private func showBlocked(_ feature: String?) {
        let name = DemoOverlayView.featureName(feature ?? "feature")
        let message = String(format: LanguageManager.shared.localized("explore.blocked"), name)
        guard let top = AppCoordinator.topViewController(), !(top is UIAlertController) else { return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: LanguageManager.shared.localized("common.ok"), style: .cancel))
        top.present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak alert] in
            if alert?.presentingViewController != nil { alert?.dismiss(animated: true) }
        }
    }

    private func refreshCurrentPhone() async {
        guard let coordinator else { return }
        if role == .sarah {
            await coordinator.fetchProtectedPersons()
            await coordinator.fetchGuardianSOS(personId: DemoDataset.momId)
        } else {
            await coordinator.fetchGuardians()
            await coordinator.refreshOwnSOSStatus()
        }
        await coordinator.fetchTimeline()
        await coordinator.fetchWatchBack()
    }

    // MARK: Coach-mark anchors

    func report(anchor id: String, frame: CGRect?) {
        guard isActive else { return }
        if let frame {
            if anchorFrames[id] != frame { anchorFrames[id] = frame }
        } else {
            anchorFrames[id] = nil
        }
    }

    // MARK: Overlay regions & modal detection

    func setOverlayRegion(_ id: String, _ frame: CGRect?) {
        overlayRegions[id] = frame.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// SwiftUI sheets/alerts don't announce themselves; poll the app window's
    /// presentation chain while the demo runs (cheap, 2.5×/s).
    private func startModalPolling(in scene: UIWindowScene) {
        modalPoll?.invalidate()
        modalPoll = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self, weak scene] _ in
            MainActor.assumeIsolated {
                guard let self, let scene else { return }
                let appWindow = scene.windows.first { !($0 is PassthroughWindow) && $0.isKeyWindow }
                    ?? scene.windows.first { !($0 is PassthroughWindow) }
                // A sheet/alert, or the full-screen SOS countdown / fall check (drawn
                // as overlays, not presented): the tips must not cover their buttons.
                let presenting = appWindow?.rootViewController?.presentedViewController != nil
                    || self.coordinator?.pendingSOS != nil
                    || self.coordinator?.showFallConfirmation == true
                if presenting != self.isAppPresentingModal { self.isAppPresentingModal = presenting }
            }
        }
    }

    // MARK: Overlay window (tips stay above sheets)

    private func installOverlayWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ??
                UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        // Tour cards are designed light (white card, navy text) in either app mode
        window.overrideUserInterfaceStyle = .light
        window.interactiveRegions = { [weak self] in
            MainActor.assumeIsolated { self.map { Array($0.overlayRegions.values) } ?? [] }
        }
        let host = UIHostingController(rootView: DemoOverlayView().environmentObject(self))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        overlayWindow = window
        startModalPolling(in: scene)
    }
}

/// Lets touches through everywhere the overlay draws nothing interactive.
final class PassthroughWindow: UIWindow {
    var interactiveRegions: () -> [CGRect] = { [] }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        if hit !== rootViewController?.view { return hit }
        // SwiftUI buttons have no UIView of their own: the hosting view is hit for a
        // button and for empty space alike. Only keep touches inside the regions the
        // overlay reported (tip card, banner, hand-off, checklist).
        return interactiveRegions().contains { $0.contains(point) } ? hit : nil
    }
}
