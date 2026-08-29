//
//  ListingCatalogSyncService.swift
//  sharePlate
//
//  Listens for listing status changes so picked-up food disappears on all
//  devices without waiting for the next poll.
//

import Foundation
import Supabase

@MainActor
final class ListingCatalogSyncService {
    static let shared = ListingCatalogSyncService()

    private var subscriptions: [RealtimeSubscription] = []
    private var channel: RealtimeChannelV2?
    private weak var store: LocalDataStore?

    private init() {}

    func start(store: LocalDataStore) {
        self.store = store
        Task { await subscribe() }
    }

    /// Re-establishes the channel on returning to foreground. The underlying
    /// socket doesn't reliably resubscribe after an extended background period,
    /// and a missed update here means someone can keep seeing already-reserved
    /// food as available and try to claim it.
    func ensureConnected() {
        Task { await resubscribe() }
    }

    func stop() {
        subscriptions.removeAll()
        let existing = channel
        channel = nil
        Task {
            if let existing {
                await SupabaseManager.client.realtimeV2.removeChannel(existing)
            }
        }
        store = nil
    }

    private func resubscribe() async {
        subscriptions.removeAll()
        let existing = channel
        channel = nil
        if let existing {
            await SupabaseManager.client.realtimeV2.removeChannel(existing)
        }
        await subscribe()
    }

    private func subscribe() async {
        guard store != nil else { return }
        if channel != nil { return }

        let client = SupabaseManager.client
        let channel = client.realtimeV2.channel("listing-catalog")

        let insertSub = channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "listings"
        ) { [weak self] insert in
            Task { @MainActor in
                guard let store = self?.store else { return }
                guard let remote = try? insert.decodeRecord(as: RemoteListing.self, decoder: SupabaseRealtimeJSON.decoder) else { return }
                store.applyRemoteListing(remote)
            }
        }

        let updateSub = channel.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "listings"
        ) { [weak self] update in
            Task { @MainActor in
                guard let store = self?.store else { return }
                guard let remote = try? update.decodeRecord(as: RemoteListing.self, decoder: SupabaseRealtimeJSON.decoder) else { return }
                store.applyRemoteListing(remote)
            }
        }

        let deleteSub = channel.onPostgresChange(
            DeleteAction.self,
            schema: "public",
            table: "listings"
        ) { [weak self] deletion in
            Task { @MainActor in
                guard let store = self?.store else { return }
                struct RowID: Decodable { let id: UUID }
                guard let row = try? deletion.decodeOldRecord(as: RowID.self, decoder: SupabaseRealtimeJSON.decoder) else { return }
                store.removeLocalListing(remoteID: row.id.uuidString)
            }
        }

        subscriptions.append(insertSub)
        subscriptions.append(updateSub)
        subscriptions.append(deleteSub)
        self.channel = channel
        try? await channel.subscribeWithError()
    }
}
