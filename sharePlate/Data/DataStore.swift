//
//  DataStore.swift
//  sharePlate
//
//  Abstraction over persistence so the SwiftData implementation can later be
//  swapped for a cloud backend (with universal login) without touching views.
//

import Foundation

enum ReserveError: LocalizedError {
    case notAvailable
    case expired
    case outsideDropOffRadius
    case missingDropOffAddress
    case invalidPackageCount

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "This listing is no longer available."
        case .expired:
            return "This listing has expired."
        case .outsideDropOffRadius:
            return "Your location and drop-off address must be within the donor's travel radius."
        case .missingDropOffAddress:
            return "Enter the address where you want the food dropped off."
        case .invalidPackageCount:
            return "Choose a valid number of packages for this booking."
        }
    }
}

enum PostListingError: LocalizedError {
    case notSignedIn
    case missingUser
    case missingPhoto
    case missingRemoteListing
    case missingPickupInstructions

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Your sign-in session expired. Sign out and sign back in, then try again."
        case .missingUser:
            return "Could not verify your account. Sign out and sign back in, then try again."
        case .missingPhoto:
            return "Add a photo of the food before posting."
        case .missingRemoteListing:
            return "This listing is not synced yet. Try again in a moment."
        case .missingPickupInstructions:
            return "Add how pickers should get the food before posting."
        }
    }
}

enum SyncError: LocalizedError {
    case remoteUpdateFailed(String)

    var errorDescription: String? {
        switch self {
        case .remoteUpdateFailed(let detail):
            return "Couldn't sync with the server. Check your connection and try again. (\(detail))"
        }
    }
}

/// Address + coordinates supplied by the consumer when reserving a drop-off.
struct DropOffReservationDetails: Equatable {
    let address: String
    let latitude: Double
    let longitude: Double
}

@MainActor
protocol DataStore {
    func seedIfNeeded()
    /// Expires overdue listings and auto-releases lapsed reservations.
    func runMaintenance()
    /// Pulls the latest shared listings from Supabase into the local cache.
    func syncListings() async
    func syncListings(force: Bool) async
    func syncListing(_ listing: FoodListing) async
    func syncListing(remoteID: String) async

    func resources() -> [FoodResource]
    func listings() -> [FoodListing]

    @discardableResult
    func createListing(
        category: FoodCategory,
        customTitle: String?,
        packageCount: Int,
        maxPackagesPerBooking: Int,
        pickupType: PickupType,
        photo: Data?,
        pickupAddress: String,
        area: String,
        latitude: Double,
        longitude: Double,
        pickupDeadline: Date,
        pickupNotes: String?,
        pickupInstructions: ReservationCoordination,
        dropOffRadiusMeters: Double?
    ) async throws -> FoodListing

    func reserve(_ listing: FoodListing, packageCount: Int, dropOff: DropOffReservationDetails?) async throws
    func releaseReservation(_ listing: FoodListing) async throws
    func markReady(_ listing: FoodListing) async throws
    func markPickedUp(_ listing: FoodListing) async throws
    func joinWaitlist(_ listing: FoodListing)
    func saveCoordinationLocally(_ coordination: ReservationCoordination, for listing: FoodListing)
    func publishCoordination(_ coordination: ReservationCoordination, for listing: FoodListing) async throws
    func cancelReservation(_ listing: FoodListing) async throws
    func delete(_ listing: FoodListing)
    func report(_ listing: FoodListing, reason: ReportReason, notes: String?)
}
