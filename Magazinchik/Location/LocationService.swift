import CoreLocation
import Observation
import UIKit

@MainActor
@Observable
final class LocationService: NSObject {
    enum Access: Equatable {
        case notDetermined
        case denied
        case restricted
        case approximate
        case precise
    }

    private(set) var access: Access = .notDetermined
    /// Fix the screens rank against. Assigned only when the person has moved, or when a press or a return to the app asks for it.
    private(set) var location: CLLocation?
    /// Newest callback, including ones that were not worth redrawing the cards for.
    @ObservationIgnored private(set) var latestFix: CLLocation?
    /// Bumps only when `location` is published, so the lists can follow a fix without reading every tick.
    private(set) var locationGeneration = 0

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var isUpdating = false
    @ObservationIgnored private var fixGates: [FixGate] = []

    /// Standing still, Core Location still delivers fixes. Redrawing every card for a few metres is the hitch.
    private static let publishDistance: CLLocationDistance = 20

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        manager.activityType = .other
        refreshAccess()
    }

    var isAuthorized: Bool { access == .approximate || access == .precise }

    var point: GeoPoint? {
        location.map { GeoPoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestPreciseLocation() {
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "NearbyStore")
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Called when the app becomes active. Updates keep the suggestion fresh while the app is open; they do not start a store search.
    func start() {
        guard isAuthorized, !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    /// The next fix determined at or after `earliest`. Used when the person asks, or when the app has just become active.
    /// A GPS tick that was already on screen does not count.
    func nextFix(since earliest: Date, timeout: Duration = .seconds(10)) async -> CLLocation? {
        guard isAuthorized else {
            if access == .notDetermined { requestPermission() }
            return nil
        }
        if let latestFix, latestFix.timestamp >= earliest { return latestFix }
        return await withCheckedContinuation { continuation in
            let gate = FixGate(earliest: earliest, continuation: continuation)
            fixGates.append(gate)
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                self.expire(gate)
            }
        }
    }

    private func expire(_ gate: FixGate) {
        guard fixGates.contains(where: { $0 === gate }) else { return }
        fixGates.removeAll { $0 === gate }
        gate.resume(nil)
    }

    /// Shows `fix` on the next render. Used by the location button and by returning to the app, not by ordinary ticks.
    func adopt(_ fix: CLLocation) {
        latestFix = fix
        publish(fix)
    }

    private func publish(_ fix: CLLocation) {
        location = fix
        locationGeneration += 1
    }

    private func shouldPublish(_ latest: CLLocation) -> Bool {
        guard let current = location else { return true }
        if current.distance(from: latest) >= Self.publishDistance { return true }
        let limit = NearbyRanking.maxAccuracyAllowance * 3
        let wasTrusted = current.horizontalAccuracy >= 0 && current.horizontalAccuracy <= limit
        let nowTrusted = latest.horizontalAccuracy >= 0 && latest.horizontalAccuracy <= limit
        return wasTrusted != nowTrusted
    }

    private func deliver(_ latest: CLLocation) {
        latestFix = latest
        if shouldPublish(latest) {
            publish(latest)
        }
        let due = fixGates.filter { latest.timestamp >= $0.earliest }
        guard !due.isEmpty else { return }
        fixGates.removeAll { gate in due.contains { $0 === gate } }
        for gate in due {
            gate.resume(latest)
        }
    }

    private func failWaiters() {
        let pending = fixGates
        fixGates.removeAll()
        for gate in pending {
            gate.resume(nil)
        }
    }

    func stop() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    private func refreshAccess() {
        switch manager.authorizationStatus {
        case .notDetermined: access = .notDetermined
        case .denied: access = .denied
        case .restricted: access = .restricted
        case .authorizedAlways, .authorizedWhenInUse:
            access = manager.accuracyAuthorization == .fullAccuracy ? .precise : .approximate
        @unknown default: access = .denied
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    // The manager is created on the main thread, so its delegate callbacks arrive there too.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            refreshAccess()
            if isAuthorized {
                start()
            } else {
                stop()
                location = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        MainActor.assumeIsolated {
            deliver(latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // `locationUnknown` is transient and the manager keeps trying.
        if let error = error as? CLError, error.code == .locationUnknown { return }
        MainActor.assumeIsolated {
            failWaiters()
        }
    }
}

/// One waiter for a location fix. Resuming twice is ignored.
private final class FixGate {
    let earliest: Date
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    init(earliest: Date, continuation: CheckedContinuation<CLLocation?, Never>) {
        self.earliest = earliest
        self.continuation = continuation
    }

    func resume(_ location: CLLocation?) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: location)
    }
}
