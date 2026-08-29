//
//  LocalDataStore.swift
//  sharePlate
//
//  SwiftData-backed implementation of `DataStore`.
//

import Foundation
import CoreLocation
import Supabase
import SwiftData
import UIKit

@MainActor
@Observable
final class LocalDataStore: DataStore {
    private let context: ModelContext
    private let session: SessionContext

    /// Stores the content signature of the dataset last imported, so existing
    /// installs re-import whenever the bundled/downloaded database changes
    /// (see `GCFDDatabase.datasetVersion()`). Adding an optional property is a
    /// lightweight SwiftData migration that does NOT wipe the store, so we
    /// reset resources here when the signature changes.
    /// Bump when import mapping logic changes so existing installs re-import
    /// even if the bundled database file has not changed.
    private let resourceImportVersion = 5
    private let resourceImportVersionKey = "gcfdResourceImportVersion"
    private let seedSignatureKey = "gcfdDatasetSignature"

    init(context: ModelContext, session: SessionContext) {
        self.context = context
        self.session = session
    }

    func seedIfNeeded() {
        let storedSignature = UserDefaults.standard.string(forKey: seedSignatureKey)
        let storedImportVersion = UserDefaults.standard.integer(forKey: resourceImportVersionKey)
        let currentSignature = GCFDDatabase.datasetVersion()
        let count = (try? context.fetchCount(FetchDescriptor<FoodResource>())) ?? 0
        let needsImport = count == 0
            || storedSignature != currentSignature
            || storedImportVersion != resourceImportVersion
        guard needsImport else { return }

        // Replace any older dataset (e.g. the original curated seed) wholesale.
        for resource in resources() {
            context.delete(resource)
        }

        let gcfd = GCFDDatabase.loadLocations()
        if gcfd.isEmpty {
            // Fallback to the curated list if the bundled database is unavailable.
            for resource in SeedData.resources() {
                context.insert(resource)
            }
        } else {
            for location in gcfd {
                context.insert(
                    FoodResource(
                        name: location.name,
                        address: location.address,
                        latitude: location.latitude,
                        longitude: location.longitude,
                        hours: location.hours,
                        phone: location.phone,
                        summary: location.summary,
                        type: location.type,
                        openingIntervals: location.intervals,
                        serviceHours: location.serviceHours,
                        gcfdLocationID: location.locationID
                    )
                )
            }
        }
        try? context.save()
        UserDefaults.standard.set(currentSignature, forKey: seedSignatureKey)
        UserDefaults.standard.set(resourceImportVersion, forKey: resourceImportVersionKey)
        reapplyPantryClaimsToResources()
    }

    func runMaintenance() {
        if let lastMaintenanceRun, Date().timeIntervalSince(lastMaintenanceRun) < 45 {
            return
        }
        lastMaintenanceRun = Date()

        var changed = false
        for listing in listings() {
            // Only expire unclaimed listings by deadline — active handoffs (claimed
            // reserved/ready-for-pickup) stay completable past the deadline; see
            // `FoodListing.hasActiveHandoff`.
            if listing.status == .available, listing.isExpired {
                listing.status = .expired
                changed = true
                continue
            }
            // Auto-release only abandoned holds (reserved with nobody claimed).
            if listing.status == .reserved,
               listing.claimedByDeviceID == nil,
               let until = listing.reservedUntil,
               until < Date() {
                reopen(listing)
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    func syncListing(_ listing: FoodListing) async {
        guard let remoteID = listing.remoteID, let id = UUID(uuidString: remoteID) else { return }
        do {
            let remote = try await SupabaseListingService.fetch(id: id)
            applyRemoteListing(remote)
            try? context.save()
        } catch {
            // Offline — keep local cache.
        }
    }

    func syncListings() async {
        await syncListings(force: false)
    }

    func syncListings(force: Bool) async {
        guard session.currentUserID != nil else { return }

        if !force, let lastListingsSync, Date().timeIntervalSince(lastListingsSync) < listingsSyncMinInterval {
            return
        }

        if let inFlightListingsSync {
            await inFlightListingsSync.value
            if !force, let lastListingsSync, Date().timeIntervalSince(lastListingsSync) < listingsSyncMinInterval {
                return
            }
        }

        let task = Task {
            await performListingsSync()
        }
        inFlightListingsSync = task
        await task.value
        inFlightListingsSync = nil
        lastListingsSync = Date()
    }

    func syncListing(remoteID: String) async {
        guard let id = UUID(uuidString: remoteID) else { return }
        do {
            let remote = try await SupabaseListingService.fetch(id: id)
            applyRemoteListing(remote)
            try? context.save()
        } catch {
            // Offline — keep local cache.
        }
    }

    private let listingsSyncMinInterval: TimeInterval = 25
    private var lastListingsSync: Date?
    private var lastMaintenanceRun: Date?
    private var inFlightListingsSync: Task<Void, Never>?

    private func performListingsSync() async {
        do {
            let remoteRows = try await SupabaseListingService.fetchActive()
            var remoteIDs = Set(remoteRows.map { $0.id.uuidString })

            for remote in remoteRows {
                applyRemoteListing(remote)
            }

            for listing in listings() {
                guard let remoteID = listing.remoteID, let id = UUID(uuidString: remoteID) else { continue }
                guard remoteIDs.contains(remoteID) else {
                    let involved = session.matches(listing.postedByDeviceID)
                        || session.matches(listing.claimedByDeviceID)
                    let status = listing.effectiveStatus
                    guard involved, status == .reserved || status == .readyForPickup else { continue }
                    if let remote = try? await SupabaseListingService.fetch(id: id) {
                        applyRemoteListing(remote)
                        let remoteStatus = ListingStatus.from(raw: remote.status)
                        if remoteStatus != .pickedUp, remoteStatus != .expired {
                            remoteIDs.insert(remoteID)
                        }
                    }
                    continue
                }
            }

            for listing in listings() {
                guard let remoteID = listing.remoteID else { continue }
                let status = listing.effectiveStatus
                if status == .pickedUp || status == .expired {
                    context.delete(listing)
                    continue
                }
                if !remoteIDs.contains(remoteID) {
                    let involved = session.matches(listing.postedByDeviceID)
                        || session.matches(listing.claimedByDeviceID)
                    if involved && (status == .reserved || status == .readyForPickup) {
                        continue
                    }
                    context.delete(listing)
                }
            }

            try? context.save()
        } catch {
            // Offline or auth issue — keep showing the local cache.
        }
    }

    func cachePhoto(_ listing: FoodListing, data: Data) {
        guard listing.photo == nil else { return }
        listing.photo = data
        if let url = listing.photoURL, let image = UIImage(data: data) {
            ListingPhotoCache.store(image, forKey: url)
        }
        try? context.save()
    }

    func resources() -> [FoodResource] {
        let descriptor = FetchDescriptor<FoodResource>(
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func listings() -> [FoodListing] {
        let descriptor = FetchDescriptor<FoodListing>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Pantry manager

    func pantryClaims() -> [PantryClaim] {
        (try? context.fetch(FetchDescriptor<PantryClaim>())) ?? []
    }

    /// The pantry this device's identity currently manages, if any.
    func myPantryClaim() -> PantryClaim? {
        guard let userID = session.currentUserID else { return nil }
        return pantryClaims().first { $0.claimedByUserID.caseInsensitiveCompare(userID) == .orderedSame }
    }

    /// Pulls the latest pantry claims from Supabase and reapplies the
    /// closed/managed overlay onto the local `FoodResource` cache.
    func syncPantryClaims() async {
        guard session.currentUserID != nil else { return }
        guard let remote = try? await SupabasePantryClaimService.fetchAll() else { return }

        let existingByID = Dictionary(uniqueKeysWithValues: pantryClaims().map { ($0.gcfdLocationID, $0) })
        var seenIDs = Set<Int>()

        for remoteClaim in remote {
            seenIDs.insert(remoteClaim.gcfdLocationID)
            if let local = existingByID[remoteClaim.gcfdLocationID] {
                local.pantryName = remoteClaim.pantryName
                local.claimedByUserID = remoteClaim.claimedBy.uuidString
                local.isTemporarilyClosed = remoteClaim.isTemporarilyClosed
                local.closedNote = remoteClaim.closedNote
            } else {
                context.insert(PantryClaim(
                    gcfdLocationID: remoteClaim.gcfdLocationID,
                    pantryName: remoteClaim.pantryName,
                    claimedByUserID: remoteClaim.claimedBy.uuidString,
                    claimedAt: remoteClaim.claimedAt,
                    isTemporarilyClosed: remoteClaim.isTemporarilyClosed,
                    closedNote: remoteClaim.closedNote
                ))
            }
        }

        for (id, claim) in existingByID where !seenIDs.contains(id) {
            context.delete(claim)
        }

        try? context.save()
        reapplyPantryClaimsToResources()
    }

    /// Re-derives each `FoodResource`'s claimed/closed overlay from the local
    /// `PantryClaim` cache. Must run after every `seedIfNeeded()` import
    /// (which wipes and reinserts resources) and after every claims sync.
    func reapplyPantryClaimsToResources() {
        let claimsByID = Dictionary(uniqueKeysWithValues: pantryClaims().map { ($0.gcfdLocationID, $0) })
        for resource in resources() {
            guard let locationID = resource.gcfdLocationID else { continue }
            let claim = claimsByID[locationID]
            resource.managedByUserID = claim?.claimedByUserID
            resource.isTemporarilyClosed = claim?.isTemporarilyClosed ?? false
            resource.pantryClosedNote = claim?.closedNote
        }
        try? context.save()
    }

    /// Claims an unclaimed pantry from the GCFD directory on behalf of this
    /// device's identity. Fails if someone already claimed it first.
    func claimPantry(_ resource: FoodResource) async throws {
        guard let locationID = resource.gcfdLocationID else {
            throw PantryClaimError.notClaimable
        }
        guard SupabaseManager.client.auth.currentSession != nil,
              let userID = session.currentUserID, let claimedBy = UUID(uuidString: userID) else {
            throw PostListingError.notSignedIn
        }

        let remote = try await SupabasePantryClaimService.claim(RemotePantryClaimInsert(
            gcfdLocationID: locationID,
            pantryName: resource.name,
            claimedBy: claimedBy
        ))

        context.insert(PantryClaim(
            gcfdLocationID: remote.gcfdLocationID,
            pantryName: remote.pantryName,
            claimedByUserID: remote.claimedBy.uuidString,
            claimedAt: remote.claimedAt
        ))
        try? context.save()
        reapplyPantryClaimsToResources()
    }

    /// Gives up management of a pantry — it returns to the unclaimed,
    /// read-only directory entry.
    func releasePantryClaim(_ claim: PantryClaim) async throws {
        try await SupabasePantryClaimService.release(gcfdLocationID: claim.gcfdLocationID)
        context.delete(claim)
        try? context.save()
        reapplyPantryClaimsToResources()
    }

    /// Toggles whether a claimed pantry shows as temporarily closed on the
    /// map, with an optional note (e.g. "Out of food until Thursday").
    func setPantryClosed(_ claim: PantryClaim, isClosed: Bool, note: String?) async throws {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await SupabasePantryClaimService.updateStatus(
            gcfdLocationID: claim.gcfdLocationID,
            patch: RemotePantryClaimUpdate(
                isTemporarilyClosed: isClosed,
                closedNote: (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
            )
        )
        claim.isTemporarilyClosed = isClosed
        claim.closedNote = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
        try? context.save()
        reapplyPantryClaimsToResources()
    }

    /// Active (unexpired, unpicked-up) surplus listings posted by a claimed pantry.
    func pantryListings(for claim: PantryClaim) -> [FoodListing] {
        listings().filter { $0.pantryGCFDLocationID == claim.gcfdLocationID && $0.effectiveStatus != .pickedUp }
    }

    @discardableResult
    func createListing(
        category: FoodCategory,
        customTitle: String? = nil,
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
        dropOffRadiusMeters: Double? = nil,
        pantryGCFDLocationID: Int? = nil
    ) async throws -> FoodListing {
        let trimmedCustom = customTitle?.trimmingCharacters(in: .whitespaces)
        let title: String
        if category == .other, let trimmedCustom, !trimmedCustom.isEmpty {
            title = trimmedCustom
        } else {
            title = category.displayName
        }

        let cappedMax = min(max(1, maxPackagesPerBooking), max(1, packageCount))
        let quantityLabel = FoodListing.quantityLabel(packageCount: packageCount, maxPerBooking: cappedMax)
        let quantitySize = QuantitySize.from(packageCount: packageCount)
        let details = ListingDetailsCodec.encode(ListingDetailsCodec.Payload(
            dropOffRadiusMeters: dropOffRadiusMeters,
            packageCount: packageCount,
            maxPackagesPerBooking: cappedMax,
            packagesRemaining: packageCount
        ))

        guard SupabaseManager.client.auth.currentSession != nil else {
            throw PostListingError.notSignedIn
        }
        guard let userID = session.currentUserID, let postedBy = UUID(uuidString: userID) else {
            throw PostListingError.missingUser
        }
        guard let photo, !photo.isEmpty else {
            throw PostListingError.missingPhoto
        }
        guard pickupInstructions.isReadyForConsumer else {
            throw PostListingError.missingPickupInstructions
        }

        let instructionsPayload = ReservationCoordinationCodec.encode(pickupInstructions)
        let listingID = UUID()
        let payload = RemoteListingInsert(
            id: listingID,
            title: title,
            details: details,
            quantity: quantityLabel,
            category: category.rawValue,
            quantitySize: quantitySize.rawValue,
            pickupType: pickupType.rawValue,
            area: area,
            photoURL: nil,
            pickupAddress: pickupAddress,
            latitude: latitude,
            longitude: longitude,
            pickupDeadline: pickupDeadline,
            pickupNotes: pickupNotes,
            contactInstructions: instructionsPayload,
            status: ListingStatus.available.rawValue,
            postedBy: postedBy,
            pantryGCFDLocationID: pantryGCFDLocationID
        )

        let remote = try await SupabaseListingService.create(payload)

        var storedPhotoPath: String?
        storedPhotoPath = try await SupabasePhotoService.upload(
            listingID: listingID,
            userID: postedBy,
            data: photo
        )
        try await SupabaseListingService.updatePhotoURL(id: listingID, photoURL: storedPhotoPath!)
        try await SupabaseListingService.update(
            id: listingID,
            patch: RemoteListingUpdate(
                status: nil,
                photoURL: storedPhotoPath,
                claimedBy: nil,
                reservedUntil: nil,
                waitlistUserIDs: nil,
                contactInstructions: instructionsPayload,
                pickupDeadline: nil,
                details: nil,
                quantity: nil
            )
        )

        let listing = FoodListing(
            title: title,
            details: details,
            quantity: quantityLabel,
            category: category,
            quantitySize: quantitySize,
            pickupType: pickupType,
            area: area,
            photo: photo,
            photoURL: storedPhotoPath ?? remote.photoURL,
            pickupAddress: pickupAddress,
            latitude: latitude,
            longitude: longitude,
            pickupDeadline: pickupDeadline,
            pickupNotes: pickupNotes,
            contactInstructions: instructionsPayload,
            status: .available,
            createdAt: remote.createdAt,
            remoteID: remote.id.uuidString,
            postedByDeviceID: userID,
            dropOffRadiusMeters: dropOffRadiusMeters,
            packageCount: packageCount,
            maxPackagesPerBooking: cappedMax,
            packagesRemaining: packageCount,
            pantryGCFDLocationID: pantryGCFDLocationID
        )
        context.insert(listing)
        try? context.save()
        await NearbyAlertService.notifyListingPosted(listing)
        return listing
    }

    func reserve(_ listing: FoodListing, packageCount requestedPackages: Int = 1, dropOff: DropOffReservationDetails? = nil) async throws {
        guard SupabaseManager.client.auth.currentSession != nil else {
            throw PostListingError.notSignedIn
        }
        guard let userID = session.currentUserID else {
            throw PostListingError.notSignedIn
        }
        if listing.isExpired { throw ReserveError.expired }
        guard listing.effectiveStatus == .available else { throw ReserveError.notAvailable }

        let remaining = listing.effectivePackagesRemaining
        let maxAllowed = min(listing.effectiveMaxPerBooking, remaining)
        guard requestedPackages >= 1, requestedPackages <= maxAllowed else {
            throw ReserveError.invalidPackageCount
        }

        if listing.isDropOff {
            guard let dropOff else { throw ReserveError.missingDropOffAddress }
            let trimmed = dropOff.address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ReserveError.missingDropOffAddress }
            guard let radiusMeters = listing.dropOffRadiusMeters else {
                throw ReserveError.outsideDropOffRadius
            }

            let provider = CLLocation(latitude: listing.latitude, longitude: listing.longitude)
            let consumer = CLLocation(latitude: dropOff.latitude, longitude: dropOff.longitude)
            guard provider.distance(from: consumer) <= radiusMeters else {
                throw ReserveError.outsideDropOffRadius
            }

            var coordination = listing.coordination
            coordination.consumerDropOffAddress = trimmed
            coordination.consumerDropOffLatitude = dropOff.latitude
            coordination.consumerDropOffLongitude = dropOff.longitude
            coordination.reservedPackageCount = requestedPackages
            listing.contactInstructions = ReservationCoordinationCodec.encode(coordination)
        } else {
            var coordination = listing.coordination
            coordination.reservedPackageCount = requestedPackages
            listing.contactInstructions = ReservationCoordinationCodec.encode(coordination)
        }

        if listing.packageCount > 0 {
            listing.packagesRemaining = remaining - requestedPackages
            listing.refreshDetailsField()
            listing.quantity = FoodListing.quantityLabel(
                packageCount: listing.packageCount,
                maxPerBooking: listing.effectiveMaxPerBooking
            )
        }

        listing.status = .reserved
        listing.claimedByDeviceID = userID
        listing.reservedUntil = listing.pickupDeadline
        try? context.save()

        do {
            try await pushRemoteAndWait(listing)
        } catch {
            if listing.packageCount > 0 {
                listing.packagesRemaining = remaining
                listing.refreshDetailsField()
            }
            reopen(listing)
            var coordination = listing.coordination
            coordination.reservedPackageCount = nil
            if listing.isDropOff {
                coordination.clearConsumerDropOff()
            }
            listing.contactInstructions = ReservationCoordinationCodec.encode(coordination)
            try? context.save()
            throw SyncError.remoteUpdateFailed(error.localizedDescription)
        }

        if let remoteID = listing.remoteID {
            LocalNotice.post(.foodReserved(title: listing.title, listingRemoteID: remoteID))
        }
        await HandoffLiveUpdatesService.shared.refreshSubscriptions()
    }

    func releaseReservation(_ listing: FoodListing) async throws {
        let previousStatus = listing.status
        let previousClaimedBy = listing.claimedByDeviceID
        let previousReservedUntil = listing.reservedUntil
        let previousContactInstructions = listing.contactInstructions
        let previousPackagesRemaining = listing.packagesRemaining
        let previousWaitlist = listing.waitlistDeviceIDs

        let restoredPackages = listing.coordination.reservedPackageCount ?? 0
        var coordination = listing.coordination
        coordination.clearConsumerDropOff()
        coordination.reservedPackageCount = nil
        listing.contactInstructions = ReservationCoordinationCodec.encode(coordination)
        if listing.packageCount > 0, restoredPackages > 0 {
            listing.packagesRemaining = min(listing.packageCount, listing.packagesRemaining + restoredPackages)
            listing.refreshDetailsField()
        }
        reopen(listing)
        try? context.save()

        do {
            try await pushRemoteAndWait(listing)
        } catch {
            listing.status = previousStatus
            listing.claimedByDeviceID = previousClaimedBy
            listing.reservedUntil = previousReservedUntil
            listing.contactInstructions = previousContactInstructions
            listing.packagesRemaining = previousPackagesRemaining
            listing.waitlistDeviceIDs = previousWaitlist
            listing.refreshDetailsField()
            try? context.save()
            throw SyncError.remoteUpdateFailed(error.localizedDescription)
        }

        if let remoteID = listing.remoteID {
            LocalNotice.post(.reservationReleased(title: listing.title, listingRemoteID: remoteID))
        }
        await HandoffLiveUpdatesService.shared.refreshSubscriptions()
    }

    func cancelReservation(_ listing: FoodListing) async throws {
        try await releaseReservation(listing)
    }

    func saveCoordinationLocally(_ coordination: ReservationCoordination, for listing: FoodListing) {
        listing.contactInstructions = ReservationCoordinationCodec.encode(coordination)
        if listing.claimedByDeviceID != nil {
            listing.status = .reserved
            listing.reservedUntil = listing.pickupDeadline
        }
        try? context.save()
    }

    func publishCoordination(_ coordination: ReservationCoordination, for listing: FoodListing) async throws {
        var published = coordination
        published.instructionsPublished = true
        listing.contactInstructions = ReservationCoordinationCodec.encode(published)
        if listing.claimedByDeviceID != nil {
            listing.status = .reserved
            listing.reservedUntil = listing.pickupDeadline
        }
        try? context.save()
        try await pushRemoteAndWait(listing)
        notifyInstructionsPublished(listing: listing)
    }

    func markReady(_ listing: FoodListing) async throws {
        listing.status = .readyForPickup
        try? context.save()
        try await pushRemoteAndWait(listing)
    }

    func markPickedUp(_ listing: FoodListing) async throws {
        guard listing.canMarkPickedUp(for: session) else {
            throw SyncError.remoteUpdateFailed("This handoff can't be completed right now.")
        }
        guard let remoteID = listing.remoteID, let id = UUID(uuidString: remoteID) else {
            throw PostListingError.missingRemoteListing
        }

        let title = listing.title

        if listing.shouldReopenAfterHandoffCompletion {
            let previousContactInstructions = listing.contactInstructions
            let previousDetails = listing.details
            let previousQuantity = listing.quantity
            let previousStatus = listing.status
            let previousClaimedBy = listing.claimedByDeviceID
            let previousReservedUntil = listing.reservedUntil
            let previousWaitlist = listing.waitlistDeviceIDs

            let providerInstructions = listing.publishedPickupInstructions
            listing.contactInstructions = ReservationCoordinationCodec.encode(providerInstructions)
            listing.refreshDetailsField()
            listing.quantity = FoodListing.quantityLabel(
                packageCount: listing.packageCount,
                maxPerBooking: listing.effectiveMaxPerBooking
            )
            reopen(listing)
            try? context.save()

            do {
                try await SupabaseListingService.reopenAfterPartialHandoff(
                    id: id,
                    details: listing.details,
                    contactInstructions: listing.contactInstructions,
                    quantity: listing.quantity,
                    pickupDeadline: listing.pickupDeadline
                )
            } catch {
                listing.contactInstructions = previousContactInstructions
                listing.details = previousDetails
                listing.quantity = previousQuantity
                listing.status = previousStatus
                listing.claimedByDeviceID = previousClaimedBy
                listing.reservedUntil = previousReservedUntil
                listing.waitlistDeviceIDs = previousWaitlist
                try? context.save()
                throw SyncError.remoteUpdateFailed(error.localizedDescription)
            }

            LocalNotice.post(.nowAvailable(title: title))
            await HandoffLiveUpdatesService.shared.refreshSubscriptions()
            return
        }

        let expiredDeadline = Date().addingTimeInterval(-60)

        do {
            try await SupabaseListingService.markHandoffComplete(id: id, pickupDeadline: expiredDeadline)
        } catch {
            throw SyncError.remoteUpdateFailed(error.localizedDescription)
        }

        removeLocalListing(remoteID: remoteID)
        LocalNotice.post(.foodPickedUp(title: title, listingRemoteID: remoteID))
        await HandoffLiveUpdatesService.shared.refreshSubscriptions()
    }

    func joinWaitlist(_ listing: FoodListing) {
        guard !session.matches(listing.postedByDeviceID) else { return }
        guard let userID = session.currentUserID else { return }
        if !listing.waitlistDeviceIDs.contains(where: { $0.caseInsensitiveCompare(userID) == .orderedSame }) {
            listing.waitlistDeviceIDs.append(userID)
            try? context.save()
            pushRemote(listing)
        }
        LocalNotice.post(.waitlistJoined(title: listing.title))
    }

    func delete(_ listing: FoodListing) {
        if let remoteID = listing.remoteID, let id = UUID(uuidString: remoteID) {
            Task { try? await SupabaseListingService.delete(id: id) }
        }
        context.delete(listing)
        try? context.save()
    }

    func report(_ listing: FoodListing, reason: ReportReason, notes: String?) {
        let report = ReportRecord(
            listingID: listing.persistentModelID.storeIdentifier ?? UUID().uuidString,
            reason: reason,
            notes: notes,
            reportedByDeviceID: session.identity
        )
        context.insert(report)
        try? context.save()
    }

    // MARK: - Helpers

    /// Reopens a listing and notifies anyone on its waitlist.
    private func reopen(_ listing: FoodListing) {
        listing.status = .available
        listing.claimedByDeviceID = nil
        listing.reservedUntil = nil
        if !listing.waitlistDeviceIDs.isEmpty {
            LocalNotice.post(.nowAvailable(title: listing.title))
            listing.waitlistDeviceIDs.removeFirst()
        }
    }

    private func upsert(_ remote: RemoteListing) {
        let remoteID = remote.id.uuidString
        if let existing = listing(withRemoteID: remoteID) {
            apply(remote, to: existing)
            return
        }

        let listing = FoodListing(
            title: remote.title,
            details: remote.details,
            quantity: remote.quantity,
            category: FoodCategory(rawValue: remote.category) ?? .mixed,
            quantitySize: QuantitySize(rawValue: remote.quantitySize) ?? .feeds3to5,
            pickupType: PickupType(rawValue: remote.pickupType) ?? .meetOutside,
            area: remote.area,
            photoURL: remote.photoURL,
            pickupAddress: remote.pickupAddress,
            latitude: remote.latitude,
            longitude: remote.longitude,
            pickupDeadline: remote.pickupDeadline,
            pickupNotes: remote.pickupNotes,
            contactInstructions: remote.contactInstructions,
            status: ListingStatus.from(raw: remote.status),
            createdAt: remote.createdAt,
            remoteID: remoteID,
            postedByDeviceID: remote.postedBy.uuidString,
            claimedByDeviceID: remote.claimedBy?.uuidString,
            reservedUntil: remote.reservedUntil,
            waitlistDeviceIDs: remote.waitlistUserIDs.map(\.uuidString),
            dropOffRadiusMeters: ListingDetailsCodec.decode(remote.details).dropOffRadiusMeters,
            pantryGCFDLocationID: remote.pantryGCFDLocationID
        )
        listing.syncPackageFieldsFromDetails()
        context.insert(listing)
    }

    private func apply(_ remote: RemoteListing, to listing: FoodListing) {
        let previousClaimed = listing.claimedByDeviceID
        let previousCoord = listing.coordination
        let remoteStatus = ListingStatus.from(raw: remote.status)

        listing.title = remote.title
        listing.details = remote.details
        listing.quantity = remote.quantity
        listing.categoryRaw = remote.category
        listing.quantitySizeRaw = remote.quantitySize
        listing.pickupTypeRaw = remote.pickupType
        listing.area = remote.area
        listing.pickupAddress = remote.pickupAddress
        listing.latitude = remote.latitude
        listing.longitude = remote.longitude
        listing.pickupDeadline = remote.pickupDeadline
        listing.pickupNotes = remote.pickupNotes
        listing.createdAt = remote.createdAt
        listing.postedByDeviceID = remote.postedBy.uuidString
        listing.waitlistDeviceIDs = remote.waitlistUserIDs.map(\.uuidString)
        listing.remoteID = remote.id.uuidString
        listing.photoURL = remote.photoURL
        listing.syncPackageFieldsFromDetails()

        let involved = session.matches(listing.postedByDeviceID) || session.matches(listing.claimedByDeviceID)
        let localActiveHandoff = involved
            && (listing.status == .reserved || listing.status == .readyForPickup)
            && listing.claimedByDeviceID != nil
        let remoteStaleForLocalHandoff = remote.claimedBy == nil && remoteStatus == .available

        if remoteStatus == .pickedUp || remoteStatus == .expired {
            listing.contactInstructions = remote.contactInstructions
            listing.statusRaw = remote.status
            listing.claimedByDeviceID = remote.claimedBy?.uuidString
            listing.reservedUntil = remote.reservedUntil
        } else if localActiveHandoff && remoteStaleForLocalHandoff {
            if let remoteInstructions = remote.contactInstructions,
               !remoteInstructions.isEmpty,
               remoteInstructions != listing.contactInstructions {
                listing.contactInstructions = remoteInstructions
            }
        } else {
            listing.contactInstructions = remote.contactInstructions
            listing.statusRaw = remote.status
            listing.claimedByDeviceID = remote.claimedBy?.uuidString
            listing.reservedUntil = remote.reservedUntil
            if remote.claimedBy != nil, listing.status == .available {
                listing.status = .reserved
            }
        }

        notifyReservationChanges(
            listing: listing,
            previousClaimed: previousClaimed,
            previousCoord: previousCoord
        )
    }

    private func notifyInstructionsPublished(listing: FoodListing) {
        guard let remoteID = listing.remoteID else { return }
        guard listing.coordination.isReadyForConsumer else { return }
        if session.matches(listing.claimedByDeviceID) {
            LocalNotice.post(.instructionsUpdated(title: listing.title, listingRemoteID: remoteID))
        }
    }

    private func notifyReservationChanges(
        listing: FoodListing,
        previousClaimed: String?,
        previousCoord: ReservationCoordination
    ) {
        let isActive = listing.effectiveStatus == .reserved || listing.effectiveStatus == .readyForPickup

        if session.matches(listing.postedByDeviceID),
           previousClaimed == nil,
           listing.claimedByDeviceID != nil,
           isActive,
           let remoteID = listing.remoteID {
            LocalNotice.post(.yourListingWasReserved(title: listing.title, listingRemoteID: remoteID))
        }

        if session.matches(listing.claimedByDeviceID),
           !previousCoord.isReadyForConsumer,
           listing.coordination.isReadyForConsumer,
           let remoteID = listing.remoteID {
            LocalNotice.post(.instructionsUpdated(title: listing.title, listingRemoteID: remoteID))
        }
    }

    // MARK: - Realtime helpers

    func activeHandoffRemoteIDs(for identity: String) -> [UUID] {
        listings().compactMap { listing in
            guard let remoteID = listing.remoteID, let uuid = UUID(uuidString: remoteID) else { return nil }
            let isOwner = session.matches(listing.postedByDeviceID)
            let isClaimer = session.matches(listing.claimedByDeviceID)
            let status = listing.effectiveStatus

            if isClaimer && (status == .reserved || status == .readyForPickup) {
                return uuid
            }
            // Provider watches open listings so reservation + instruction requests arrive instantly.
            if isOwner && (status == .available || status == .reserved || status == .readyForPickup) {
                return uuid
            }
            return nil
        }
    }

    func applyRemoteListing(_ remote: RemoteListing) {
        let status = ListingStatus.from(raw: remote.status)
        let remoteID = remote.id.uuidString

        if status == .pickedUp {
            if let listing = listing(withRemoteID: remoteID) {
                let title = listing.title
                if session.matches(listing.claimedByDeviceID) || session.matches(listing.postedByDeviceID) {
                    LocalNotice.post(.foodPickedUp(title: title, listingRemoteID: remoteID))
                }
            }
            removeLocalListing(remoteID: remoteID)
            return
        }

        if status == .expired {
            removeLocalListing(remoteID: remoteID)
            return
        }

        upsert(remote)
        try? context.save()
    }

    func removeLocalListing(remoteID: String) {
        guard let listing = listing(withRemoteID: remoteID) else { return }
        context.delete(listing)
        try? context.save()
    }

    private func cachePhotoIfNeeded(for remote: RemoteListing) async {
        guard let urlString = remote.photoURL, !urlString.isEmpty else { return }
        guard let listing = listing(withRemoteID: remote.id.uuidString) else { return }
        if listing.photoURL == urlString, listing.photo != nil { return }

        guard let data = try? await SupabasePhotoService.download(storedValue: urlString) else { return }
        listing.photo = data
        listing.photoURL = urlString
        try? context.save()
    }

    private func listing(withRemoteID remoteID: String) -> FoodListing? {
        let descriptor = FetchDescriptor<FoodListing>(predicate: #Predicate { $0.remoteID == remoteID })
        return try? context.fetch(descriptor).first
    }

    private func pushRemoteAndWait(_ listing: FoodListing) async throws {
        guard let remoteID = listing.remoteID, let id = UUID(uuidString: remoteID) else {
            throw PostListingError.missingRemoteListing
        }
        let patch = RemoteListingUpdate(
            status: listing.status.supabaseRaw,
            photoURL: nil,
            claimedBy: listing.claimedByDeviceID.flatMap(UUID.init(uuidString:)),
            reservedUntil: listing.reservedUntil,
            waitlistUserIDs: listing.waitlistDeviceIDs.compactMap(UUID.init(uuidString:)),
            contactInstructions: listing.contactInstructions,
            pickupDeadline: listing.pickupDeadline,
            details: listing.details.isEmpty ? nil : listing.details,
            quantity: listing.quantity.isEmpty ? nil : listing.quantity
        )
        try await SupabaseListingService.update(id: id, patch: patch)
    }

    private func pushRemote(_ listing: FoodListing) {
        guard let remoteID = listing.remoteID, let id = UUID(uuidString: remoteID) else { return }
        let patch = RemoteListingUpdate(
            status: listing.status.supabaseRaw,
            photoURL: nil,
            claimedBy: listing.claimedByDeviceID.flatMap(UUID.init(uuidString:)),
            reservedUntil: listing.reservedUntil,
            waitlistUserIDs: listing.waitlistDeviceIDs.compactMap(UUID.init(uuidString:)),
            contactInstructions: listing.contactInstructions,
            pickupDeadline: listing.pickupDeadline,
            details: listing.details.isEmpty ? nil : listing.details,
            quantity: listing.quantity.isEmpty ? nil : listing.quantity
        )
        Task { try? await SupabaseListingService.update(id: id, patch: patch) }
    }

}
