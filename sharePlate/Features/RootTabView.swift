//
//  RootTabView.swift
//  sharePlate
//

import SwiftUI
import Combine

struct RootTabView: View {
    @Environment(LocationManager.self) private var location
    @Environment(LocalDataStore.self) private var store
    @Environment(SessionContext.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: AppTab = .map
    @State private var loadedTabs: Set<AppTab> = [.map]
    @State private var notice = LocalNotice.shared

    private let maintenanceTimer = Timer.publish(every: 90, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if loadedTabs.contains(.map) {
                    HomeMapView()
                        .opacity(selectedTab == .map ? 1 : 0)
                        .allowsHitTesting(selectedTab == .map)
                        .accessibilityHidden(selectedTab != .map)
                }

                if loadedTabs.contains(.resources) {
                    ResourceDirectoryView()
                        .opacity(selectedTab == .resources ? 1 : 0)
                        .allowsHitTesting(selectedTab == .resources)
                        .accessibilityHidden(selectedTab != .resources)
                }

                if loadedTabs.contains(.freeFood) {
                    ListingsView()
                        .opacity(selectedTab == .freeFood ? 1 : 0)
                        .allowsHitTesting(selectedTab == .freeFood)
                        .accessibilityHidden(selectedTab != .freeFood)
                }

                if loadedTabs.contains(.activity) {
                    ActivityView()
                        .opacity(selectedTab == .activity ? 1 : 0)
                        .allowsHitTesting(selectedTab == .activity)
                        .accessibilityHidden(selectedTab != .activity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            AppTabBar(selection: $selectedTab)
        }
        .background(Theme.Palette.backgroundCream)
        .onChange(of: selectedTab) { _, tab in
            withoutAnimation { loadedTabs.insert(tab) }
        }
        .task {
            store.seedIfNeeded()
            store.runMaintenance()
            await store.syncListings(force: true)
            await store.syncPantryClaims()
            HandoffLiveUpdatesService.shared.start(store: store, session: session)
            ListingCatalogSyncService.shared.start(store: store, session: session, location: location)
            await PushNotificationService.shared.requestAuthorizationAndRegister()
            await PushNotificationService.shared.uploadTokenIfNeeded()
            location.bootstrapIfNeeded()

            // Silent background upgrade: if a fresher GCFD dataset is available,
            // pull it in and re-seed. Never blocks the UI above — users are
            // already browsing the bundled data by the time this resolves.
            if await GCFDDatabaseSyncService.refreshIfNeeded() {
                store.seedIfNeeded()
            }
        }
        .onReceive(maintenanceTimer) { _ in
            guard scenePhase == .active else { return }
            store.runMaintenance()
            Task { await store.syncListings() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                location.resumeIfAuthorized()
                store.runMaintenance()
                Task {
                    await store.syncListings(force: true)
                    await store.syncPantryClaims()
                    await HandoffLiveUpdatesService.shared.refreshSubscriptions()
                    ListingCatalogSyncService.shared.ensureConnected()
                    await PushNotificationService.shared.uploadTokenIfNeeded()
                }
            case .background:
                location.stopUpdating()
            default:
                break
            }
        }
        .onChange(of: notice.pendingHandoffListingRemoteID) { _, remoteID in
            guard remoteID != nil else { return }
            loadedTabs.insert(.map)
            loadedTabs.insert(.activity)
            if selectedTab != .map {
                selectedTab = .activity
            }
        }
    }
}
