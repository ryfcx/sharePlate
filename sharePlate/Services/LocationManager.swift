//
//  LocationManager.swift
//  sharePlate
//

import Foundation
import CoreLocation
import MapKit

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    /// Downtown Chicago, used as the default when location is unavailable.
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

    var isLocationAvailable: Bool {
        isAuthorized && userLocation != nil
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    /// The coordinate to center maps on: the user's location if known, else Chicago.
    var mapCenter: CLLocationCoordinate2D {
        userLocation ?? Self.chicago
    }

    var defaultRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: mapCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    }

    /// Requests permission when needed; location updates begin in the authorization callback.
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

    /// Safe to call on foreground — no-ops until the user has granted access.
    func resumeIfAuthorized() {
        startUpdatingIfAuthorized()
    }

    private func startUpdatingIfAuthorized() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    /// Distance in meters from the user to a coordinate, or nil if unknown.
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let user = userLocation else { return nil }
        let from = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let to = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: to)
    }

    /// Human-friendly distance string (e.g. "1.2 mi"), or nil if unknown.
    func distanceText(to coordinate: CLLocationCoordinate2D) -> String? {
        guard let meters = distance(to: coordinate) else { return nil }
        let miles = meters / 1609.344
        if miles < 0.1 {
            return "nearby"
        }
        return String(format: "%.1f mi", miles)
    }

    // MARK: - CLLocationManagerDelegate

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
        // Expected when permission is denied or the simulator has no fix — fall back to Chicago.
    }
}
