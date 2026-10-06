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
    private let resourceImportVersion = 7
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
        guard needsImport else {
            ensurePermanentStoreListings()
            return
        }

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
                let schedule = FoodResource.importedSchedule(
                    locationID: location.locationID,
                    hours: location.hours,
                    intervals: location.intervals,
                    serviceHours: location.serviceHours
                )
                context.insert(
                    FoodResource(
                        name: location.name,
                        address: location.address,
                        latitude: location.latitude,
                        longitude: location.longitude,
                        hours: schedule.hours,
                        phone: location.phone,
                        summary: location.summary,
                        type: location.type,
                        openingIntervals: schedule.intervals,
                        serviceHours: schedule.serviceHours,
                        gcfdLocationID: location.locationID
                    )
                )
            }
        }
        try? context.save()
        UserDefaults.standard.set(currentSignature, forKey: seedSignatureKey)
        UserDefaults.standard.set(resourceImportVersion, forKey: resourceImportVersionKey)
        reapplyPantryClaimsToResources()
        ensurePermanentStoreListings()
    }

    /// Removes pantry listings that were drawn with a cart pin.
    /// The always-open sites stay on the map as the normal green pantry dots.
    func ensurePermanentStoreListings() {
        let generated = listings().filter(\.isPermanent)
        guard !generated.isEmpty else { return }
        for listing in generated {
            context.delete(listing)
        }
        try? context.save()
    }

    /// Drops donor listings that expiration or a catalog refresh has finished.
    /// Permanent store listings stay even when their deadline is in the past or they have no remote row.
    func pruneListingsAbsentFromCatalog(remoteIDs: Set<String>) {
        for listing in listings() {
            if listing.isPermanent { continue }
            guard let remoteID = listing.remoteID else { continue }
            if remoteIDs.contains(remoteID) { continue }
            if remembersHistory(listing) {
                if listing.status == .available {
                    listing.status = .expired
                }
                continue
            }
            context.delete(listing)
        }
        try? context.save()
    }

    /// Posts and reservations this device made stay on the Activity history
    /// after they leave the live catalog.
    private func remembersHistory(_ listing: FoodListing) -> Bool {
        session.matches(listing.postedByDeviceID) || session.matches(listing.claimedByDeviceID)
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
            if listing.isPermanent { continue }
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
    private var completedListingRemoteIDs: Set<String> = []

    private func performListingsSync() async {
        do {
            let allRemoteRows = try await SupabaseListingService.fetchActive()
            if let completedIDs = await SupabaseListingService.fetchCompletedListingIDs() {
                completedListingRemoteIDs = Set(completedIDs.map(\.uuidString))
            }
            let remoteRows = allRemoteRows.filter {
                !completedListingRemoteIDs.contains($0.id.uuidString)
            }
            var remoteIDs = Set(remoteRows.map { $0.id.uuidString })

            for remote in remoteRows {
                applyRemoteListing(remote)
            }

            for listing in listings() {
                if listing.isPermanent { continue }
                guard let remoteID = listing.remoteID, let id = UUID(uuidString: remoteID) else { continue }
                if completedListingRemoteIDs.contains(remoteID) {
                    if remembersHistory(listing) {
                        listing.status = .pickedUp
                    } else {
                        context.delete(listing)
                    }
                    continue
                }
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

            pruneListingsAbsentFromCatalog(remoteIDs: remoteIDs)

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

    /// Re-establishes anonymous auth when launch-time authentication failed
    /// (for example, because the device was briefly offline).
    private func authenticatedIdentity() async throws -> (userID: String, uuid: UUID) {
        do {
            let authSession = try await SupabaseAuthService.ensureSession()
            let uuid = authSession.user.id
            let userID = uuid.uuidString
            let identityChanged = session.currentUserID?.caseInsensitiveCompare(userID) != .orderedSame
            session.currentUserID = userID
            if identityChanged {
                await PushNotificationService.shared.uploadTokenIfNeeded()
                await HandoffLiveUpdatesService.shared.refreshSubscriptions()
            }
            return (userID, uuid)
        } catch {
            throw PostListingError.notSignedIn
        }
    }

    /// Claims an unclaimed pantry from the GCFD directory on behalf of this
    /// device's identity. Fails if someone already claimed it first.
    func claimPantry(_ resource: FoodResource) async throws {
        guard let locationID = resource.gcfdLocationID else {
            throw PantryClaimError.notClaimable
        }
        let (_, claimedBy) = try await authenticatedIdentity()

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
        listings().filter {
            $0.pantryGCFDLocationID == claim.gcfdLocationID && !$0.isPermanent && $0.effectiveStatus != .pickedUp
        }
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

        let (userID, postedBy) = try await authenticatedIdentity()
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
        if listing.isPermanent { throw ReserveError.notAvailable }
        let (userID, _) = try await authenticatedIdentity()
        guard let remoteID = listing.remoteID, let listingID = UUID(uuidString: remoteID) else {
            throw PostListingError.missingRemoteListing
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
            try await SupabaseListingService.reserve(
                id: listingID,
                details: listing.details,
                quantity: listing.quantity,
                contactInstructions: listing.contactInstructions,
                reservedUntil: listing.reservedUntil ?? listing.pickupDeadline,
                reserverName: session.displayName
            )
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

        await HandoffLiveUpdatesService.shared.refreshSubscriptions()
    }

    func releaseReservation(_ listing: FoodListing) async throws {
        guard let remoteID = listing.remoteID, let listingID = UUID(uuidString: remoteID) else {
            throw PostListingError.missingRemoteListing
        }
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
            try await SupabaseListingService.releaseReservation(
                id: listingID,
                details: listing.details,
                quantity: listing.quantity,
                contactInstructions: listing.contactInstructions,
                waitlistUserIDs: listing.waitlistDeviceIDs.compactMap(UUID.init(uuidString:))
            )
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
    }

    func markReady(_ listing: FoodListing) async throws {
        listing.status = .readyForPickup
        try? context.save()
        try await pushRemoteAndWait(listing)
    }

    func markPickedUp(_ listing: FoodListing) async throws {
        guard listing.canMarkPickedUp(for: session) else {
            throw SyncError.remoteUpdateFailed(String(localized: "This handoff can't be completed right now."))
        }
        guard let remoteID = listing.remoteID, let id = UUID(uuidString: remoteID) else {
            throw PostListingError.missingRemoteListing
        }

        let completedByThisConsumer = session.matches(listing.claimedByDeviceID)

        if listing.shouldReopenAfterHandoffCompletion {
            let previousContactInstructions = listing.contactInstructions
            let previousStatus = listing.status
            let previousClaimedBy = listing.claimedByDeviceID
            let previousReservedUntil = listing.reservedUntil

            var providerInstructions = listing.publishedPickupInstructions
            providerInstructions.clearConsumerDropOff()
            providerInstructions.reservedPackageCount = nil

            if completedByThisConsumer {
                completedListingRemoteIDs.insert(remoteID)
            }

            do {
                // The server records the completed consumer and atomically
                // reopens only when its authoritative remaining count is > 0.
                try await SupabaseListingService.markHandoffComplete(
                    id: id,
                    pickupDeadline: listing.pickupDeadline
                )
            } catch {
                completedListingRemoteIDs.remove(remoteID)
                listing.contactInstructions = previousContactInstructions
                listing.status = previousStatus
                listing.claimedByDeviceID = previousClaimedBy
                listing.reservedUntil = previousReservedUntil
                try? context.save()
                throw SyncError.remoteUpdateFailed(error.localizedDescription)
            }

            if completedByThisConsumer {
                markListingCompletedLocally(remoteID: remoteID)
            } else {
                listing.contactInstructions = ReservationCoordinationCodec.encode(providerInstructions)
                listing.status = .available
                listing.claimedByDeviceID = nil
                listing.reservedUntil = nil
                try? context.save()
            }
            await HandoffLiveUpdatesService.shared.refreshSubscriptions()
            return
        }

        let expiredDeadline = Date().addingTimeInterval(-60)

        do {
            try await SupabaseListingService.markHandoffComplete(id: id, pickupDeadline: expiredDeadline)
        } catch {
            throw SyncError.remoteUpdateFailed(error.localizedDescription)
        }

        markListingCompletedLocally(remoteID: remoteID)
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

        // The database RPCs make reservation transitions atomic, so the remote
        // row is authoritative. In particular, a partial completion changes
        // reserved → available and must not be mistaken for a stale update.
        listing.contactInstructions = remote.contactInstructions
        listing.statusRaw = remote.status
        listing.claimedByDeviceID = remote.claimedBy?.uuidString
        listing.reservedUntil = remote.reservedUntil
        if remote.claimedBy != nil, listing.status == .available {
            listing.status = .reserved
        }

        notifyReservationChanges(
            listing: listing,
            previousClaimed: previousClaimed
        )
    }

    private func notifyReservationChanges(
        listing: FoodListing,
        previousClaimed: String?
    ) {
        let isActive = listing.effectiveStatus == .reserved || listing.effectiveStatus == .readyForPickup

        if session.matches(listing.postedByDeviceID),
           previousClaimed == nil,
           listing.claimedByDeviceID != nil,
           isActive,
           listing.remoteID != nil {
            Task {
                await NearbyAlertService.notifyListingReserved(listing)
            }
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

        if completedListingRemoteIDs.contains(remoteID) {
            markListingCompletedLocally(remoteID: remoteID)
            return
        }

        // A reserved listing becoming available while this device was the
        // claimer means that allocation was completed by the provider. Hide it
        // immediately here; the completion-history sync makes this persistent.
        if status == .available,
           remote.claimedBy == nil,
           let existing = listing(withRemoteID: remoteID),
           session.matches(existing.claimedByDeviceID) {
            completedListingRemoteIDs.insert(remoteID)
            markListingCompletedLocally(remoteID: remoteID)
            return
        }

        if status == .pickedUp {
            markListingCompletedLocally(remoteID: remoteID)
            return
        }

        if status == .expired {
            if let listing = listing(withRemoteID: remoteID), remembersHistory(listing) {
                listing.status = .expired
                try? context.save()
            } else {
                removeLocalListing(remoteID: remoteID)
            }
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

    /// Hide a completed listing without deleting a model that an active
    /// navigation destination may still be observing. Normal sync removes the
    /// tombstone after the detail screen has had time to dismiss.
    private func markListingCompletedLocally(remoteID: String) {
        guard let listing = listing(withRemoteID: remoteID) else { return }
        listing.status = .pickedUp
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
