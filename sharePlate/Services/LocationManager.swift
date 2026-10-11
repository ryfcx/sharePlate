//
// locationmanager.swift
// shareplate
//

import Foundation
import CoreLocation
import MapKit

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    // downtown chicago used when location is unavailable
    static let chicago = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)

    private let manager = CLLocationManager()
    private var hasRequestedAuthorization = false

    var authorizationStatus: CLAuthorizationStatus
    var userLocation: CLLocationCoordinate2D?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 400
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isAuthorizedAlways: Bool {
        authorizationStatus == .authorizedAlways
    }

    // show always allow prompt only after when in use is granted
    var canRequestAlways: Bool {
        authorizationStatus == .authorizedWhenInUse
    }

    var isLocationAvailable: Bool {
        isAuthorized && userLocation != nil
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    // map center is user location if known, else chicago
    var mapCenter: CLLocationCoordinate2D {
        userLocation ?? Self.chicago
    }

    var defaultRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: mapCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    }

    // requests permission when needed, updates start after auth callback
    func bootstrapIfNeeded() {
        switch authorizationStatus {
        case .notDetermined:
            guard !hasRequestedAuthorization else { return }
            hasRequestedAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingIfAuthorized()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    // safe to call on foreground, no ops until access granted
    func resumeIfAuthorized() {
        startUpdatingIfAuthorized()
    }

    // asks to upgrade from while using to always
    // keeps nearby alerts working while app is not open
    // only meaningful after when in use was granted
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    private func startUpdatingIfAuthorized() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        if authorizationStatus == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    // distance in meters to a coordinate, or nil if unknown
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let user = userLocation else { return nil }
        let from = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let to = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: to)
    }

    // friendly distance string, or nil if unknown
    func distanceText(to coordinate: CLLocationCoordinate2D) -> String? {
        guard let meters = distance(to: coordinate) else { return nil }
        let miles = meters / 1609.344
        if miles < 0.1 {
            return String(localized: "nearby")
        }
        return String(format: "%.1f mi", miles)
    }

    // location manager delegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.startUpdatingIfAuthorized()
            } else {
                self.stopUpdating()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.userLocation = coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // expected when permission denied or simulator has no fix, falls back to chicago
    }
}
