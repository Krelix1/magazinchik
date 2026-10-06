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
    private(set) var location: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var isUpdating = false

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

    /// Called when the app becomes active. The first fix is the launch check; later ones keep the suggestion fresh while the app is open.
    func start() {
        guard isAuthorized, !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
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
            location = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // `locationUnknown` is transient and the manager keeps trying; other errors are reflected via authorization.
    }
}
