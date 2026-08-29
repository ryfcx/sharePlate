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
            return "Couldn't verify your device identity. Check your connection and try again."
        case .missingUser:
            return "Couldn't verify your device identity. Check your connection and try again."
        case .missingPhoto:
            return "Add a photo of the food before posting."
        case .missingRemoteListing:
            return "This listing is not synced yet. Try again in a moment."
        case .missingPickupInstructions:
            return "Add how pickers should get the food before posting."
        }
    }
}

enum PantryClaimError: LocalizedError {
    case notClaimable

    var errorDescription: String? {
        switch self {
        case .notClaimable:
            return "This location can't be claimed."
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
        dropOffRadiusMeters: Double?,
        pantryGCFDLocationID: Int?
    ) async throws -> FoodListing

    // MARK: - Pantry manager

    func pantryClaims() -> [PantryClaim]
    func myPantryClaim() -> PantryClaim?
    func syncPantryClaims() async
    func reapplyPantryClaimsToResources()
    func claimPantry(_ resource: FoodResource) async throws
    func releasePantryClaim(_ claim: PantryClaim) async throws
    func setPantryClosed(_ claim: PantryClaim, isClosed: Bool, note: String?) async throws
    func pantryListings(for claim: PantryClaim) -> [FoodListing]

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
