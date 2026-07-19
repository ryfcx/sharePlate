//
//  DirectionsHelper.swift
//  sharePlate
//
//  Directions can open in either Google Maps or Apple Maps.
//

import Foundation
import UIKit
import MapKit
import CoreLocation

enum DirectionsHelper {
    // MARK: - Google Maps

    static func googleMapsURL(coordinate: CLLocationCoordinate2D, address: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        return components?.url
    }

    /// Opens the Google Maps app via universal link when installed, else the web.
    static func openGoogleMaps(coordinate: CLLocationCoordinate2D, address: String) {
        guard let url = googleMapsURL(coordinate: coordinate, address: address) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Apple Maps

    static func openAppleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}
