// local data store

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
    private var savedBlocks: [String: [BlockedUser]] = [:]
    private var blocksRevision = 0
    private let blockDefaults: UserDefaults
    private let blockedUsersKey = "sharePlate.blockedUsers"

    var blockedUsers: [BlockedUser] {
        savedBlocks[session.identity.lowercased()] ?? []
    }

    func isUserBlocked(_ userID: String?) -> Bool {
        guard let userID, let id = UUID(uuidString: userID) else { return false }
        return blockedUsers.contains { $0.id == id }
    }

    func syncBlockedUsers() async {
        guard session.allowsDataAccess else { return }
        do {
            let (_, owner) = try await authenticatedIdentity()
            let revision = blocksRevision
            let rows = try await UserBlockService.fetch()
            guard session.allowsDataAccess, revision == blocksRevision,
                  session.currentUserID?.lowercased() == owner.uuidString.lowercased() else { return }
            saveBlocks(rows, owner: owner)
        } catch {
            // keep saved blocks when offline
        }
    }

    func blockUser(_ userID: String, name: String) async throws {
        let (_, owner) = try await authenticatedIdentity()
        guard let target = UUID(uuidString: userID), target != owner else {
            throw ReserveError.notAvailable
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = try await UserBlockService.block(target,
            name: trimmed.isEmpty ? String(localized: "Neighbor") : String(trimmed.prefix(50)), owner: owner)
        var rows = savedBlocks[owner.uuidString.lowercased()] ?? []
        rows.removeAll { $0.id == target }
        rows.insert(row, at: 0)
        saveBlocks(rows, owner: owner)
        NearbyAlertService.removeListingAlerts(for: listings().filter {
            UUID(uuidString: $0.postedByDeviceID) == target
        })
    }

    func unblockUser(_ id: UUID) async throws {
        let (_, owner) = try await authenticatedIdentity()
        try await UserBlockService.unblock(id, owner: owner)
        let rows = (savedBlocks[owner.uuidString.lowercased()] ?? []).filter { $0.id != id }
        saveBlocks(rows, owner: owner)
        await syncListings(force: true)
    }

    private func saveBlocks(_ rows: [BlockedUser], owner: UUID) {
        blocksRevision += 1
        savedBlocks[owner.uuidString.lowercased()] = rows
        if let data = try? JSONEncoder().encode(savedBlocks) {
            blockDefaults.set(data, forKey: blockedUsersKey)
        }
    }

    // remembers which data we imported so we refresh when it changes
    private let resourceImportVersion = 8
    private let resourceImportVersionKey = "gcfdResourceImportVersion"
    private let seedSignatureKey = "gcfdDatasetSignature"

    init(context: ModelContext, session: SessionContext, blockDefaults: UserDefaults = .standard) {
        self.context = context
        self.session = session
        self.blockDefaults = blockDefaults
        if let data = blockDefaults.data(forKey: blockedUsersKey),
           let saved = try? JSONDecoder().decode([String: [BlockedUser]].self, from: data) {
            savedBlocks = saved
        }
    }

    func seedIfNeeded() {
        guard session.allowsDataAccess else { return }
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

// clear out the old list before adding the new one
        for resource in resources() {
            context.delete(resource)
        }

        let gcfd = GCFDDatabase.loadLocations()
        if gcfd.isEmpty {
// use the built in list if the database is missing
            for resource in SeedData.resources() {
                context.insert(resource)
            }
        } else {
            for location in gcfd {
                let schedule = FoodResource.importedSchedule(
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

    // drop old shop posts, keep pantry dots
    func ensurePermanentStoreListings() {
        let generated = listings().filter(\.isPermanent)
        guard !generated.isEmpty else { return }
        for listing in generated {
            context.delete(listing)
        }
        try? context.save()
    }

    // drop old donor posts, keep shop posts
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

    // keep your own posts in history
    private func remembersHistory(_ listing: FoodListing) -> Bool {
        session.matches(listing.postedByDeviceID) || session.matches(listing.claimedByDeviceID)
    }

    func runMaintenance() {
        guard session.allowsDataAccess else { return }
        if let lastMaintenanceRun, Date().timeIntervalSince(lastMaintenanceRun) < 45 {
            return
        }
        lastMaintenanceRun = Date()

        var changed = false
        for listing in listings() {
// only expire open posts, booked ones can still finish
            if listing.isPermanent { continue }
            if listing.status == .available, listing.isExpired {
                listing.status = .expired
                changed = true
                continue
            }
// free up holds nobody claimed
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
        guard session.allowsDataAccess else { return }
        let owner = session.identity
        guard let remoteID = listing.remoteID, let id = UUID(uuidString: remoteID) else { return }
        do {
            let remote = try await SupabaseListingService.fetch(id: id)
            guard session.allowsDataAccess, session.identity == owner else { return }
            applyRemoteListing(remote)
            try? context.save()
        } catch {
            // offline, keep what we have
        }
    }

    func syncListings() async {
        await syncListings(force: false)
    }

    func syncListings(force: Bool) async {
        guard session.allowsDataAccess else { return }
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
        guard session.allowsDataAccess else { return }
        let owner = session.identity
        guard let id = UUID(uuidString: remoteID) else { return }
        do {
            let remote = try await SupabaseListingService.fetch(id: id)
            guard session.allowsDataAccess, session.identity == owner else { return }
            applyRemoteListing(remote)
            try? context.save()
        } catch {
            // offline, keep what we have
        }
    }

    private let listingsSyncMinInterval: TimeInterval = 25
    private var lastListingsSync: Date?
    private var lastMaintenanceRun: Date?
    private var inFlightListingsSync: Task<Void, Never>?
    private var completedListingRemoteIDs: Set<String> = []

    private func performListingsSync() async {
        guard session.allowsDataAccess else { return }
        let owner = session.identity
        do {
            let allRemoteRows = try await SupabaseListingService.fetchActive()
            if let completedIDs = await SupabaseListingService.fetchCompletedListingIDs() {
                guard session.allowsDataAccess, session.identity == owner else { return }
                completedListingRemoteIDs = Set(completedIDs.map(\.uuidString))
            }
            guard session.allowsDataAccess, session.identity == owner else { return }
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
                        guard session.allowsDataAccess, session.identity == owner else { return }
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
            // offline, keep what we have
        }
    }

    func cachePhoto(_ listing: FoodListing, data: Data) {
        guard session.allowsDataAccess, listing.modelContext != nil else { return }
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

    func erasePersonalData() throws {
        inFlightListingsSync?.cancel()
        inFlightListingsSync = nil
        for listing in listings() { context.delete(listing) }
        for report in try context.fetch(FetchDescriptor<ReportRecord>()) { context.delete(report) }
        for claim in pantryClaims() { context.delete(claim) }
        try context.save()
        savedBlocks = [:]
        blocksRevision += 1
        blockDefaults.removeObject(forKey: blockedUsersKey)
        completedListingRemoteIDs = []
        lastListingsSync = nil
        lastMaintenanceRun = nil
        reapplyPantryClaimsToResources()
        ListingPhotoCache.clear()
        URLCache.shared.removeAllCachedResponses()
        UserDefaults.standard.removeObject(forKey: "nearbyAlert.notifiedListingIDs")
    }

// pantry manager

    func pantryClaims() -> [PantryClaim] {
        (try? context.fetch(FetchDescriptor<PantryClaim>())) ?? []
    }

    // the pantry this phone manages, if any
    func myPantryClaim() -> PantryClaim? {
        guard let userID = session.currentUserID else { return nil }
        return pantryClaims().first { $0.claimedByUserID.caseInsensitiveCompare(userID) == .orderedSame }
    }

    // pull fresh claims and update the local spots
    func syncPantryClaims() async {
        guard session.allowsDataAccess else { return }
        let owner = session.identity
        guard session.currentUserID != nil else { return }
        guard let remote = try? await SupabasePantryClaimService.fetchAll() else { return }
        guard session.allowsDataAccess, session.identity == owner else { return }

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

    // repaint the closed and managed flags on spots
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

    // sign in quietly again if launch login failed
    private func authenticatedIdentity() async throws -> (userID: String, uuid: UUID) {
        guard session.allowsDataAccess else { throw AccountDeletionError.unfinished }
        do {
            let authSession = try await SupabaseAuthService.ensureSession()
            guard session.allowsDataAccess else { throw AccountDeletionError.unfinished }
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

    // claim an open pantry for this phone
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

    // give up a pantry so it goes back to public
    func releasePantryClaim(_ claim: PantryClaim) async throws {
        try await SupabasePantryClaimService.release(gcfdLocationID: claim.gcfdLocationID)
        context.delete(claim)
        try? context.save()
        reapplyPantryClaimsToResources()
    }

    // mark your pantry open or closed with a note
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

    // live surplus posts from your pantry
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
        guard title.count <= 120, (pickupNotes?.count ?? 0) <= 1000,
              pickupInstructions.providerNote.count <= 1000, photo.count <= 5 * 1024 * 1024 else {
            throw ContentSubmissionError.contentTooLarge
        }

        let instructionsPayload = ReservationCoordinationCodec.encode(pickupInstructions)
        let listingID = UUID()
        let storedPhotoPath = try await SupabasePhotoService.upload(
            listingID: listingID, userID: postedBy, data: photo)
        let payload = RemoteListingInsert(
            id: listingID,
            title: title,
            details: details,
            quantity: quantityLabel,
            category: category.rawValue,
            quantitySize: quantitySize.rawValue,
            pickupType: pickupType.rawValue,
            area: area,
            photoURL: storedPhotoPath,
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

        let remote: RemoteListing
        do {
            remote = try await SupabaseListingService.create(payload)
        } catch {
            // a lost response may still have saved the listing
            if let saved = try? await SupabaseListingService.fetch(id: listingID) {
                remote = saved
            } else {
                await SupabasePhotoService.removeUnattachedPhoto(path: storedPhotoPath)
                throw error
            }
        }
        guard session.allowsDataAccess, session.matches(userID) else {
            throw ContentSubmissionError.sessionChanged
        }

        let listing = FoodListing(
            title: title,
            details: details,
            quantity: quantityLabel,
            category: category,
            quantitySize: quantitySize,
            pickupType: pickupType,
            area: area,
            photo: photo,
            photoURL: remote.photoURL,
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
            pantryGCFDLocationID: pantryGCFDLocationID,
            moderationStatus: remote.moderationStatus,
            moderationReason: remote.moderationReason
        )
        context.insert(listing)
        try? context.save()
        return listing
    }

    func reserve(_ listing: FoodListing, packageCount requestedPackages: Int = 1, dropOff: DropOffReservationDetails? = nil) async throws {
        guard listing.isApprovedForSharing else { throw ReserveError.notAvailable }
        guard !isUserBlocked(listing.postedByDeviceID) else { throw ReserveError.notAvailable }
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
        guard listing.isApprovedForSharing else { throw ReserveError.notAvailable }
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
// server reopens only if packs are left
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

    func report(_ listing: FoodListing, reason: ReportReason, notes: String?) async throws {
        guard let remoteID = listing.remoteID, let listingID = UUID(uuidString: remoteID) else {
            throw ReportSubmissionError.listingUnavailable
        }
        guard !session.matches(listing.postedByDeviceID) else { throw ReportSubmissionError.ownListing }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.unicodeScalars.count <= 1_000 else { throw ReportSubmissionError.notesTooLong }
        let (userID, _) = try await authenticatedIdentity()
        try await ListingReportService.submit(
            listingID: listingID, reason: reason, notes: trimmed.isEmpty ? nil : trimmed)

        // keep a local receipt only after the server accepts the report
        let report = ReportRecord(
            listingID: listingID.uuidString,
            reason: reason,
            notes: trimmed.isEmpty ? nil : trimmed,
            reportedByDeviceID: userID
        )
        context.insert(report)
        try? context.save()
    }

// helpers

    // reopen a post and tell the waitlist
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
            pantryGCFDLocationID: remote.pantryGCFDLocationID,
            moderationStatus: remote.moderationStatus,
            moderationReason: remote.moderationReason
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
        listing.moderationStatusRaw = remote.moderationStatus
        listing.moderationReason = remote.moderationReason
        listing.syncPackageFieldsFromDetails()

// online row wins for bookings
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

// realtime helpers

    func activeHandoffRemoteIDs(for identity: String) -> [UUID] {
        listings().compactMap { listing in
            guard let remoteID = listing.remoteID, let uuid = UUID(uuidString: remoteID) else { return nil }
            let isOwner = session.matches(listing.postedByDeviceID)
            let isClaimer = session.matches(listing.claimedByDeviceID)
            let status = listing.effectiveStatus

            if isClaimer && (status == .reserved || status == .readyForPickup) {
                return uuid
            }
// makers watch open posts so bookings ping fast
            if isOwner && (status == .available || status == .reserved || status == .readyForPickup) {
                return uuid
            }
            return nil
        }
    }

    func applyRemoteListing(_ remote: RemoteListing) {
        guard session.allowsDataAccess else { return }
        let status = ListingStatus.from(raw: remote.status)
        let remoteID = remote.id.uuidString
        if let existing = listing(withRemoteID: remoteID) {
            existing.moderationStatusRaw = remote.moderationStatus
            existing.moderationReason = remote.moderationReason
        }

        if completedListingRemoteIDs.contains(remoteID) {
            markListingCompletedLocally(remoteID: remoteID)
            return
        }

// hide it if the maker finished your share
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

    func applyModerationChange(remoteID: String, status: String) {
        guard session.allowsDataAccess, let listing = listing(withRemoteID: remoteID) else { return }
        listing.moderationStatusRaw = status
        if status != "approved", !session.matches(listing.postedByDeviceID) {
            listing.photo = nil
            NearbyAlertService.removeListingAlerts(for: [listing])
        }
        try? context.save()
    }

    // hide finished posts softly so open screens do not break
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
