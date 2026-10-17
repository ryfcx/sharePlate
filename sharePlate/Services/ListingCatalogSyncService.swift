//
// listingcatalogsyncservice.swift
// shareplate
//
// listens for listing inserts and status changes
// new food shows on every open device without polling
//

import Foundation
import Supabase

@MainActor
final class ListingCatalogSyncService {
    static let shared = ListingCatalogSyncService()

    private var subscriptions: [RealtimeSubscription] = []
    private var channel: RealtimeChannelV2?
    private var workChain = Task<Void, Never> {}
    private weak var store: LocalDataStore?
    private weak var location: LocationManager?
    private var session: SessionContext?

    private init() {}

    func start(store: LocalDataStore, session: SessionContext, location: LocationManager) {
        self.store = store
        self.session = session
        self.location = location
        enqueue { await self.attachIfNeeded() }
    }

    // reattaches after foreground if socket dropped the channel
    // never adds callbacks to an already subscribed channel
    func ensureConnected() {
        enqueue { await self.attachIfNeeded() }
    }

    func stop() {
        enqueue {
            await self.detach()
            self.store = nil
            self.session = nil
            self.location = nil
        }
    }

    func stopAndWait() async {
        stop()
        await workChain.value
    }

    private func enqueue(_ work: @escaping () async -> Void) {
        let previous = workChain
        workChain = Task {
            await previous.value
            await work()
        }
    }

    private func attachIfNeeded() async {
        guard store != nil else { return }
        if let channel, channel.status == .subscribed || channel.status == .subscribing {
            return
        }

        await detach()

        let client = SupabaseManager.client
        let channel = client.realtimeV2.channel("listing-catalog")

        // channel reuses existing topic
        // adding more callbacks to a subscribed channel would crash
        if channel.status == .subscribed || channel.status == .subscribing {
            self.channel = channel
            return
        }

        let insertSub = channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "listings"
        ) { insert in
            Task { @MainActor in
                await ListingCatalogSyncService.shared.applyIncomingListing(
                    decoded: try? insert.decodeRecord(as: RemoteListing.self, decoder: SupabaseRealtimeJSON.decoder),
                    recordID: SupabaseRealtimeJSON.recordID(insert.record),
                    notifyIfNew: true
                )
            }
        }

        let updateSub = channel.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "listings"
        ) { update in
            Task { @MainActor in
                await ListingCatalogSyncService.shared.applyIncomingListing(
                    decoded: try? update.decodeRecord(as: RemoteListing.self, decoder: SupabaseRealtimeJSON.decoder),
                    recordID: SupabaseRealtimeJSON.recordID(update.record),
                    notifyIfNew: false
                )
            }
        }

        let deleteSub = channel.onPostgresChange(
            DeleteAction.self,
            schema: "public",
            table: "listings"
        ) { deletion in
            Task { @MainActor in
                guard let store = ListingCatalogSyncService.shared.store else { return }
                if let row = try? deletion.decodeOldRecord(as: RowID.self, decoder: SupabaseRealtimeJSON.decoder) {
                    store.removeLocalListing(remoteID: row.id.uuidString)
                    return
                }
                if let id = SupabaseRealtimeJSON.recordID(deletion.oldRecord) {
                    store.removeLocalListing(remoteID: id.uuidString)
                }
            }
        }

        let subscribingIdentity = session?.identity
        let visibilityInsertSub = channel.onPostgresChange(
            InsertAction.self, schema: "public", table: "listing_visibility"
        ) { change in
            guard let row = try? change.decodeRecord(as: ListingVisibility.self, decoder: SupabaseRealtimeJSON.decoder) else { return }
            Task { @MainActor in
                await ListingCatalogSyncService.shared.applyVisibility(row, identity: subscribingIdentity)
            }
        }
        let visibilityUpdateSub = channel.onPostgresChange(
            UpdateAction.self, schema: "public", table: "listing_visibility"
        ) { change in
            guard let row = try? change.decodeRecord(as: ListingVisibility.self, decoder: SupabaseRealtimeJSON.decoder) else { return }
            Task { @MainActor in
                await ListingCatalogSyncService.shared.applyVisibility(row, identity: subscribingIdentity)
            }
        }

        subscriptions.append(insertSub)
        subscriptions.append(updateSub)
        subscriptions.append(deleteSub)
        subscriptions.append(visibilityInsertSub)
        subscriptions.append(visibilityUpdateSub)

        do {
            try await channel.subscribeWithError()
            self.channel = channel
        } catch {
            subscriptions.removeAll()
            self.channel = nil
            await client.realtimeV2.removeChannel(channel)
        }
    }

    private func detach() async {
        subscriptions.removeAll()
        let existing = channel
        channel = nil
        if let existing {
            await SupabaseManager.client.realtimeV2.removeChannel(existing)
        }
    }

    private func applyIncomingListing(
        decoded: RemoteListing?,
        recordID: UUID?,
        notifyIfNew: Bool
    ) async {
        guard let store else { return }
        let owner = session?.identity

        let remote: RemoteListing
        if let recordID = recordID ?? decoded?.id {
            do {
                remote = try await SupabaseListingService.fetch(id: recordID)
            } catch {
                return
            }
        } else {
            return
        }

        guard session?.identity == owner, session?.allowsDataAccess == true else { return }
        let existed = store.listings().contains { $0.remoteID == remote.id.uuidString }
        store.applyRemoteListing(remote)

        if notifyIfNew || !existed {
            await notifyConsumers(of: remote)
        }
    }

    private func notifyConsumers(of remote: RemoteListing) async {
        guard let store, let session, let location else { return }
        guard remote.moderationStatus == "approved" else { return }
        guard ListingStatus.from(raw: remote.status) == .available else { return }
        guard let listing = store.listings().first(where: { $0.remoteID == remote.id.uuidString }) else { return }
        guard !store.isUserBlocked(listing.postedByDeviceID) else { return }
        await NearbyAlertService.checkForNewNearbyListings(
            [listing],
            near: location.mapCenter,
            excludingDeviceID: session.identity
        )
    }

    private func applyVisibility(_ row: ListingVisibility, identity: String?) async {
        guard session?.allowsDataAccess == true, session?.identity == identity, let store else { return }
        if row.status != "approved" {
            let cached = store.listings().first { $0.remoteID == row.listingID.uuidString }
            guard let cached else { return }
            store.applyModerationChange(remoteID: row.listingID.uuidString, status: row.status)
            guard session?.matches(cached.postedByDeviceID) == true
                    || session?.matches(cached.claimedByDeviceID) == true else { return }
        }
        // fetch only if rls allows this account to see the content
        await applyIncomingListing(decoded: nil, recordID: row.listingID, notifyIfNew: row.status == "approved")
    }
}

private nonisolated struct ListingVisibility: Decodable, Sendable {
    let listingID: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case listingID = "listing_id"
        case status = "moderation_status"
    }
}

private struct RowID: Decodable {
    let id: UUID
}
