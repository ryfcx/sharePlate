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

        subscriptions.append(insertSub)
        subscriptions.append(updateSub)
        subscriptions.append(deleteSub)

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

        let remote: RemoteListing
        if let decoded {
            remote = decoded
        } else if let recordID {
            do {
                remote = try await SupabaseListingService.fetch(id: recordID)
            } catch {
                return
            }
        } else {
            return
        }

        let existed = store.listings().contains { $0.remoteID == remote.id.uuidString }
        store.applyRemoteListing(remote)

        if notifyIfNew || !existed {
            await notifyConsumers(of: remote)
        }
    }

    private func notifyConsumers(of remote: RemoteListing) async {
        guard let store, let session, let location else { return }
        guard ListingStatus.from(raw: remote.status) == .available else { return }
        guard let listing = store.listings().first(where: { $0.remoteID == remote.id.uuidString }) else { return }
        await NearbyAlertService.checkForNewNearbyListings(
            [listing],
            near: location.mapCenter,
            excludingDeviceID: session.identity
        )
    }
}

private struct RowID: Decodable {
    let id: UUID
}
