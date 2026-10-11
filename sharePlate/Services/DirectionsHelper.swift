//
// directionshelper.swift
// shareplate
//
// directions can open in google maps or apple maps
//

import Foundation
import UIKit
import MapKit
import CoreLocation

enum DirectionsHelper {
    // google maps

    static func googleMapsURL(coordinate: CLLocationCoordinate2D, address: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        return components?.url
    }

    // opens google maps app when installed, else the web
    static func openGoogleMaps(coordinate: CLLocationCoordinate2D, address: String) {
        guard let url = googleMapsURL(coordinate: coordinate, address: address) else { return }
        UIApplication.shared.open(url)
    }

    // apple maps

    static func openAppleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}
