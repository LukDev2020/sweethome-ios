import Foundation
import CoreLocation

// MARK: - Explore Mode: one real location fix, on request
//
// The demo normally never reads GPS (ExploreModeIsolation). Two opt-ins may ask
// for ONE fix after the person agrees on an explanation screen:
//   • the weather card ("Use my location") — the fix is used only for the weather
//   • "Show me where I really am" — the fix becomes the protected person's own
//     pin and their "share location" (AdaptiveLocationManager.demoLocation)
// The fix lives in ExploreModeController's memory. Every API call of the demo is
// answered on the phone by DemoURLProtocol, so it can't reach a server, and
// ExploreModeController.exit() forgets it. Background tracking, trip recording and
// indoor positioning stay blocked (ExploreMode.blocks("location")).

enum DemoLocateError: Error, Equatable {
    /// Location is off for the app (or restricted): the person can allow it in Settings.
    case denied
    /// No fix in time (indoors, airplane mode…).
    case failed
}

@MainActor
protocol DemoLocating: AnyObject {
    /// Asks for When-In-Use permission if it was never asked, then takes one fix.
    func locateOnce() async throws -> CLLocation
}

/// The device's location, read once (no updates, no background).
@MainActor
final class DeviceDemoLocator: NSObject, DemoLocating {
    private var manager: CLLocationManager?
    private var authWaiter: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var fixWaiter: CheckedContinuation<CLLocation, Error>?
    private var timeout: Task<Void, Never>?

    func locateOnce() async throws -> CLLocation {
        let manager = self.manager ?? CLLocationManager()
        self.manager = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { waiter in
                authWaiter = waiter
                manager.requestWhenInUseAuthorization()
            }
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { throw DemoLocateError.denied }

        // A previous request still waiting: let it go
        finishFix(.failure(DemoLocateError.failed))
        return try await withCheckedThrowingContinuation { waiter in
            fixWaiter = waiter
            manager.requestLocation()
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                self?.finishFix(.failure(DemoLocateError.failed))
            }
        }
    }

    fileprivate func finishAuth(_ status: CLAuthorizationStatus) {
        guard status != .notDetermined, let waiter = authWaiter else { return }
        authWaiter = nil
        waiter.resume(returning: status)
    }

    fileprivate func finishFix(_ result: Result<CLLocation, Error>) {
        timeout?.cancel()
        timeout = nil
        guard let waiter = fixWaiter else { return }
        fixWaiter = nil
        waiter.resume(with: result)
    }
}

extension DeviceDemoLocator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.finishAuth(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        Task { @MainActor in self.finishFix(.success(fix)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in self.finishFix(.failure(denied ? DemoLocateError.denied : DemoLocateError.failed)) }
    }
}

/// A person typed into "Add a family member" during the demo, carried (in memory
/// only) to the real sign-up when they choose "Invite your real family".
struct DemoInvitee: Equatable, Identifiable {
    let name: String
    /// The side the person will have: guardian (looks out for me) or protected.
    let role: UserRole
    var id: String { "\(role.rawValue):\(name)" }

    /// What the account holder becomes when this person accepts the invite.
    var inviterRole: UserRole { role == .guardian ? .protected_ : .guardian }
}
