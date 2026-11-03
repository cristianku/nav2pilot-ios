import CoreLocation
import Foundation

/// The phone's position, used as the start of the route previews (the phone is normally in the car).
public protocol LocationProvider: AnyObject {
    func currentLocation() async -> LatLng?
}

/// One-shot location through CoreLocation, asking for "when in use" permission the first time.
/// Its state is only touched on the main thread (see currentLocation), hence @unchecked Sendable.
public final class CoreLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate, @unchecked Sendable {
    private var manager: CLLocationManager?
    private var pending: [CheckedContinuation<LatLng?, Never>] = []

    // A fix younger than this is reused instead of waiting for a new one.
    private static let maxAgeSeconds: TimeInterval = 120

    public override init() {
        super.init()
    }

    public func currentLocation() async -> LatLng? {
        return await withCheckedContinuation { continuation in
            // CLLocationManager wants the thread with a run loop it was created on: the main thread.
            DispatchQueue.main.async {
                self.pending.append(continuation)
                self.request()
            }
        }
    }

    /// The last fix CoreLocation already has, without asking for the permission or waiting for a new one: nil when
    /// there is none from the last half hour. For hints that must not slow anything down, like the search region.
    public func recentLocation() async -> LatLng? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume(returning: self.cachedLocation())
            }
        }
    }

    private static let recentMaxAgeSeconds: TimeInterval = 1800

    private func cachedLocation() -> LatLng? {
        let manager = locationManager()
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            return nil
        }
        guard let location = manager.location, -location.timestamp.timeIntervalSinceNow < CoreLocationProvider.recentMaxAgeSeconds else {
            return nil
        }
        return LatLng(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private func locationManager() -> CLLocationManager {
        if let existing = manager {
            return existing
        }
        let created = CLLocationManager()
        created.delegate = self
        created.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager = created
        return created
    }

    private func request() {
        let manager = locationManager()
        if let recent = manager.location, -recent.timestamp.timeIntervalSinceNow < CoreLocationProvider.maxAgeSeconds {
            finish(recent)
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            // the answer arrives in locationManagerDidChangeAuthorization
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(nil)
        default:
            manager.requestLocation()
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if pending.isEmpty {
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            return
        case .denied, .restricted:
            finish(nil)
        default:
            manager.requestLocation()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        var result: LatLng?
        if let location = location {
            result = LatLng(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        }
        let waiting = pending
        pending = []
        for continuation in waiting {
            continuation.resume(returning: result)
        }
    }
}
