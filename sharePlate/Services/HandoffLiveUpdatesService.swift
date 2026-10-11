//
// handoffliveupdatesservice.swift
// shareplate
//
// realtime subscriptions for active handoffs
// instant listing updates without polling
//

import Foundation
import Supabase

@MainActor
final class HandoffLiveUpdatesService {
    static let shared = HandoffLiveUpdatesService()

    private var subscriptions: [RealtimeSubscription] = []
    private var channels: [RealtimeChannelV2] = []
    private var subscribedListingIDs: Set<UUID> = []
    private weak var store: LocalDataStore?
    private var session: SessionContext?
    private var refreshTask: Task<Void, Never>?

    private init() {}

    func start(store: LocalDataStore, session: SessionContext) {
        self.store = store
        self.session = session
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSubscriptions()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        Task { await unsubscribeAll() }
        store = nil
        session = nil
    }

    func refreshSubscriptions() async {
        guard let store, let session, session.currentUserID != nil else {
            await unsubscribeAll()
            return
        }

        let desired = Set(store.activeHandoffRemoteIDs(for: session.identity))
        guard desired != subscribedListingIDs else { return }

        await unsubscribeAll()

        for listingID in desired {
            await subscribe(to: listingID)
        }
        subscribedListingIDs = desired
    }

    // private helpers

    private func subscribe(to listingID: UUID) async {
        let client = SupabaseManager.client
        let channel = client.realtimeV2.channel("handoff:\(listingID.uuidString)")

        let listingSub = channel.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "listings",
            filter: .eq("id", value: listingID)
        ) { update in
            Task { @MainActor in
                guard let store = HandoffLiveUpdatesService.shared.store else { return }
                if let remote = try? update.decodeRecord(as: RemoteListing.self, decoder: SupabaseRealtimeJSON.decoder) {
                    store.applyRemoteListing(remote)
                    return
                }
                if let id = SupabaseRealtimeJSON.recordID(update.record) {
                    await store.syncListing(remoteID: id.uuidString)
                }
            }
        }

        subscriptions.append(listingSub)
        channels.append(channel)

        try? await channel.subscribeWithError()
    }

    private func unsubscribeAll() async {
        subscriptions.removeAll()
        subscribedListingIDs.removeAll()

        let toRemove = channels
        channels.removeAll()

        for channel in toRemove {
            await SupabaseManager.client.realtimeV2.removeChannel(channel)
        }
    }
}
