//
//  DropOffReserveSheet.swift
//  sharePlate
//
//  Consumer enters their drop-off address and must be within the donor's radius.
//

import SwiftUI
import MapKit
import CoreLocation

struct DropOffReserveSheet: View {
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    let listing: FoodListing
    let onReserve: (Int, DropOffReservationDetails) async throws -> Void

    @State private var address = ""
    @State private var resolvedCoordinate: CLLocationCoordinate2D?
    @State private var resolvedAddress: String?
    @State private var showMapPicker = false
    @State private var selectedPackages: Int
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(
        listing: FoodListing,
        onReserve: @escaping (Int, DropOffReservationDetails) async throws -> Void
    ) {
        self.listing = listing
        self.onReserve = onReserve
        let maxAllowed = min(listing.effectiveMaxPerBooking, listing.effectivePackagesRemaining)
        _selectedPackages = State(initialValue: maxAllowed > 8 ? 1 : max(1, maxAllowed))
    }

    private var maxAllowed: Int {
        min(listing.effectiveMaxPerBooking, listing.effectivePackagesRemaining)
    }

    private var radiusLabel: String {
        listing.dropOffRadiusLabel ?? String(localized: "the listed radius")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("This donor will travel up to \(radiusLabel) from near \(listing.areaLabel).")
                        .font(AppFont.subheadline)
                        .foregroundStyle(Theme.Palette.mutedText)

                    if let userLocation = location.userLocation,
                       let radiusMeters = listing.dropOffRadiusMeters {
                        let provider = CLLocation(latitude: listing.latitude, longitude: listing.longitude)
                        let here = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
                        let within = provider.distance(from: here) <= radiusMeters
                        Label(
                            within ? "You're within range" : "You're outside the travel radius",
                            systemImage: within ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .font(AppFont.subheadlineMedium)
                        .foregroundStyle(within ? Theme.Palette.primaryGreen : Theme.Palette.urgentRed)
                    } else {
                        Label("Turn on location to confirm you're in range", systemImage: "location.slash")
                            .font(AppFont.subheadlineMedium)
                            .foregroundStyle(Theme.Palette.mutedText)
                    }

                    if maxAllowed > 1 {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Packages")
                                .font(AppFont.headline)
                            PackageCountPicker(
                                selection: $selectedPackages,
                                range: 1...maxAllowed,
                                label: "packages"
                            )
                        }
                        .cardStyle(padding: 0)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Drop-off address")
                            .font(AppFont.headline)
                        TextField("Street address, city", text: $address, axis: .vertical)
                            .lineLimit(2...4)
                            .font(AppFont.body)
                            .foregroundStyle(Theme.Palette.primaryText)
                            .padding(Theme.Spacing.md)
                            .background(Theme.Palette.cardBackground)
                            .boxBorder()
                            .textInputAutocapitalization(.words)

                        Button {
                            Task { await useCurrentLocation() }
                        } label: {
                            Label("Use my current location", systemImage: "location.fill")
                                .font(AppFont.subheadlineMedium)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.primaryGreen)

                        Button {
                            showMapPicker = true
                        } label: {
                            Label("Drop a pin on the map", systemImage: "mappin.and.ellipse")
                                .font(AppFont.subheadlineMedium)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.primaryGreen)
                    }
                    .cardStyle(padding: 0)
                }
                .padding(Theme.Spacing.lg)
            }
            .screenBackground()
            .navigationTitle("Reserve drop off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Text("Reserve \(selectedPackages)x drop off")
                                .font(AppFont.button)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking || address.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(Theme.Spacing.lg)
                .background(Theme.Palette.backgroundCream)
            }
            .alert("Couldn't reserve", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: address) { _, newAddress in
                if let resolvedAddress, newAddress != resolvedAddress {
                    resolvedCoordinate = nil
                    self.resolvedAddress = nil
                }
            }
            .sheet(isPresented: $showMapPicker) {
                MapLocationPicker(
                    initialCoordinate: resolvedCoordinate ?? location.userLocation ?? listing.coordinate,
                    selectedCoordinate: resolvedCoordinate
                ) { coordinate, selectedAddress in
                    resolvedCoordinate = coordinate
                    resolvedAddress = selectedAddress
                    address = selectedAddress
                }
            }
        }
    }

    private func useCurrentLocation() async {
        guard let userLocation = location.userLocation else {
            errorMessage = String(localized: "Location unavailable. Enter your address manually.")
            return
        }
        let loc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        if let request = MKReverseGeocodingRequest(location: loc),
           let item = try? await request.mapItems.first,
           let fullAddress = item.address?.fullAddress {
            address = fullAddress
        } else {
            address = String(format: "%.4f, %.4f", userLocation.latitude, userLocation.longitude)
        }
        resolvedCoordinate = userLocation
        resolvedAddress = address
    }

    private func submit() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = ReserveError.missingDropOffAddress.errorDescription
            return
        }

        guard let radiusMeters = listing.dropOffRadiusMeters else {
            errorMessage = ReserveError.outsideDropOffRadius.errorDescription
            return
        }

        do {
            let coordinate = try await resolveCoordinate(for: trimmed)
            let provider = CLLocation(latitude: listing.latitude, longitude: listing.longitude)
            let dropOff = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard provider.distance(from: dropOff) <= radiusMeters else {
                errorMessage = ReserveError.outsideDropOffRadius.errorDescription
                return
            }

            let details = DropOffReservationDetails(
                address: trimmed,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            try await onReserve(selectedPackages, details)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveCoordinate(for address: String) async throws -> CLLocationCoordinate2D {
        if let resolvedCoordinate, resolvedAddress == address {
            return resolvedCoordinate
        }
        if let request = MKGeocodingRequest(addressString: address),
           let item = try? await request.mapItems.first {
            let coord = item.location.coordinate
            resolvedCoordinate = coord
            resolvedAddress = address
            return coord
        }
        if let resolvedCoordinate {
            return resolvedCoordinate
        }
        throw ReserveError.missingDropOffAddress
    }
}
