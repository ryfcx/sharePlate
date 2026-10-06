//
//  MapLocationPicker.swift
//  sharePlate
//
//  Reusable address picker: tap the map, review the resolved address, confirm.
//

import SwiftUI
import MapKit
import CoreLocation

struct MapLocationPicker: View {
    @Environment(\.dismiss) private var dismiss

    let initialCoordinate: CLLocationCoordinate2D
    let selectedCoordinate: CLLocationCoordinate2D?
    let onSelect: (CLLocationCoordinate2D, String) -> Void

    @State private var cameraPosition: MapCameraPosition
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var address = String(localized: "Tap the map to place a pin.")
    @State private var isResolvingAddress = false
    @State private var geocodingTask: Task<Void, Never>?

    init(
        initialCoordinate: CLLocationCoordinate2D,
        selectedCoordinate: CLLocationCoordinate2D? = nil,
        onSelect: @escaping (CLLocationCoordinate2D, String) -> Void
    ) {
        self.initialCoordinate = initialCoordinate
        self.selectedCoordinate = selectedCoordinate
        self.onSelect = onSelect
        _pinCoordinate = State(initialValue: selectedCoordinate)
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: selectedCoordinate ?? initialCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        )))
        if let selectedCoordinate {
            _address = State(initialValue: Self.coordinateText(selectedCoordinate))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        if let pinCoordinate {
                            Marker("Selected location", coordinate: pinCoordinate)
                                .tint(Theme.Palette.primaryGreen)
                        }
                    }
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .onTapGesture { point in
                        guard let coordinate = proxy.convert(point, from: .local) else { return }
                        choose(coordinate)
                    }
                }

                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Theme.Palette.primaryGreen)
                    Group {
                        if isResolvingAddress {
                            Text("Finding address…")
                        } else {
                            Text(address)
                        }
                    }
                    .font(AppFont.body)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.lg)
                .background(Theme.Palette.cardBackground)
            }
            .screenBackground()
            .navigationTitle("Drop a Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let pinCoordinate else { return }
                    onSelect(pinCoordinate, address)
                    dismiss()
                } label: {
                    Label("Use This Location", systemImage: "mappin.and.ellipse")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(pinCoordinate == nil || isResolvingAddress)
                .padding(Theme.Spacing.lg)
                .background(Theme.Palette.backgroundCream)
            }
        }
        .task {
            if let selectedCoordinate {
                await resolveAddress(for: selectedCoordinate)
            }
        }
        .onDisappear {
            geocodingTask?.cancel()
        }
    }

    private func choose(_ coordinate: CLLocationCoordinate2D) {
        pinCoordinate = coordinate
        address = Self.coordinateText(coordinate)
        geocodingTask?.cancel()
        geocodingTask = Task {
            await resolveAddress(for: coordinate)
        }
    }

    private func resolveAddress(for coordinate: CLLocationCoordinate2D) async {
        isResolvingAddress = true
        defer { isResolvingAddress = false }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first,
              let fullAddress = item.address?.fullAddress,
              !fullAddress.isEmpty,
              !Task.isCancelled else {
            return
        }
        address = fullAddress
    }

    private static func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
}
