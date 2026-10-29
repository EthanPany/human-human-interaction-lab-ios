import CoreLocation
import Foundation
import Observation
import UIKit

/// Tells the server roughly where this phone is, so the agent only sends a
/// heads up about someone who is actually around (both within about 300 m).
///
/// Privacy: only while the app is open (When In Use), about every three
/// minutes, at about 100 m accuracy, rounded to a ~110 m grid before it leaves
/// the phone. The server forgets it after 15 minutes and never shows it to
/// anyone. Settings > Heads ups turns it off (on by default), which also
/// deletes the last report.
@MainActor
@Observable
final class LocationReporter: NSObject {
    static let enabledKey = "shareApproximateLocation"
    static let interval: Duration = .seconds(180)

    enum Status: Equatable {
        case off, waitingForPermission, denied, sharing

        var label: String {
            switch self {
            case .off: return "Off"
            case .waitingForPermission: return "Waiting for permission"
            case .denied: return "Location is off for this app (Settings > Privacy > Location Services)"
            case .sharing: return "On while the app is open"
            }
        }
    }

    private(set) var status: Status = .off
    private(set) var lastSentAt: Date?

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    @ObservationIgnored private let backend: Backend
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(backend: Backend) {
        self.backend = backend
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        })
    }

    /// Signed in: start reporting while the app is in front (if sharing is on).
    func start(userId: String) {
        self.userId = userId
        resume()
    }

    /// Signed out: stop and forget the last report.
    func stop() {
        pause()
        if let userId { Task { [backend] in try? await backend.clearLocation(userId: userId) } }
        userId = nil
        status = .off
    }

    /// The Settings switch changed.
    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            resume()
        } else {
            pause()
            status = .off
            if let userId { Task { [backend] in try? await backend.clearLocation(userId: userId) } }
        }
    }

    private func resume() {
        guard userId != nil, Self.isEnabled, UIApplication.shared.applicationState != .background else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .waitingForPermission
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .denied
        default:
            status = .sharing
            startLoop()
        }
    }

    private func pause() {
        loop?.cancel()
        loop = nil
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.manager.requestLocation()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private func send(latitude: Double, longitude: Double, accuracy: Double) {
        guard let userId, Self.isEnabled else { return }
        // Round on the phone too: a ~110 m grid is all the server ever sees.
        let lat = (latitude * 1000).rounded() / 1000
        let lng = (longitude * 1000).rounded() / 1000
        lastSentAt = Date()
        Task { [backend] in
            try? await backend.reportLocation(userId: userId, latitude: lat, longitude: lng, accuracy: max(accuracy, 100))
        }
    }
}

extension LocationReporter: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
        let lat = fix.coordinate.latitude
        let lng = fix.coordinate.longitude
        let accuracy = fix.horizontalAccuracy
        Task { @MainActor in self.send(latitude: lat, longitude: lng, accuracy: accuracy) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Indoors or no fix yet: the next round tries again.
    }
}
