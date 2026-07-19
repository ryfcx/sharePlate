//
//  DirectionsButton.swift
//  sharePlate
//

import SwiftUI
import CoreLocation

struct DirectionsButton: View {
    let coordinate: CLLocationCoordinate2D
    let name: String
    let address: String

    @State private var showOptions = false

    var body: some View {
        Button {
            showOptions = true
        } label: {
            Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .confirmationDialog("Open directions in", isPresented: $showOptions, titleVisibility: .visible) {
            Button("Google Maps") {
                DirectionsHelper.openGoogleMaps(coordinate: coordinate, address: address)
            }
            Button("Apple Maps") {
                DirectionsHelper.openAppleMaps(coordinate: coordinate, name: name)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
