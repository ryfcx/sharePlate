//
// activityview.swift
// shareplate
//

import SwiftUI
import SwiftData

struct ActivityView: View {
    @Environment(LocalDataStore.self) private var store
    @Environment(SessionContext.self) private var session
    @Environment(LocationManager.self) private var location
    @Query(sort: \FoodListing.createdAt, order: .reverse) private var listings: [FoodListing]

    @State private var navigationPath = NavigationPath()
    @State private var showSettings = false
    @State private var notice = LocalNotice.shared
    @State private var lastOpenedHandoffRemoteID: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    bookDetailsSection

                    activitySection("My Listings", systemImage: "tray.full.fill") {
                        if myAvailableListings.isEmpty {
                            emptyHint("Available food you post will appear here.")
                        }
                        ForEach(myAvailableListings) { listing in
                            listingRow(listing)
                        }
                    }

                    activitySection("History", systemImage: "clock.arrow.circlepath") {
                        if historyListings.isEmpty {
                            emptyHint("Food you post and reservations you make show up here.")
                        }
                        ForEach(historyListings) { listing in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(historyRole(for: listing))
                                    .font(AppFont.caption)
                                    .foregroundStyle(Theme.Palette.mutedText)
                                listingRow(listing)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .screenBackground()
            .navigationTitle("Book details")
            .navigationDestination(for: LocationDetail.self) { detail in
                LocationDetailScreen(detail: detail)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Theme.Spacing.md) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                        SharePlateLogoView()
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                Task { await openPendingHandoffIfNeeded() }
            }
            .onChange(of: notice.pendingHandoffListingRemoteID) { _, _ in
                Task { await openPendingHandoffIfNeeded() }
            }
        }
    }

    // bookings screen

    private var bookDetailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label("Active bookings", systemImage: "list.bullet.rectangle")
                .font(AppFont.title3)
                .foregroundStyle(Theme.Palette.primaryText)

            if activeBookings.isEmpty {
                emptyHint("When you reserve food or someone reserves yours, live status shows here — e.g. 1234: 2x [reserved].")
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(activeBookings) { listing in
                        Button {
                            navigationPath.append(LocationDetail.listing(listing.persistentModelID))
                        } label: {
                            BookingDashboardRow(
                                listing: listing,
                                isProvider: session.matches(listing.postedByDeviceID)
                            )
                        }
                        .buttonStyle(PlainRowButtonStyle())
                    }
                }
            }
        }
    }

    private func openPendingHandoffIfNeeded() async {
        guard let remoteID = notice.pendingHandoffListingRemoteID else { return }
        guard remoteID != lastOpenedHandoffRemoteID else { return }
        if listings.first(where: { $0.remoteID == remoteID }) == nil {
            await store.syncListing(remoteID: remoteID)
        }
        guard let listing = listings.first(where: { $0.remoteID == remoteID }) else { return }
        notice.pendingHandoffListingRemoteID = nil
        lastOpenedHandoffRemoteID = remoteID
        navigationPath.append(LocationDetail.listing(listing.persistentModelID))
    }

    private func activitySection<Content: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(title, systemImage: systemImage)
                .font(AppFont.title3)
                .foregroundStyle(Theme.Palette.primaryText)

            VStack(spacing: Theme.Spacing.md) {
                content()
            }
        }
    }

    private func emptyHint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.subheadline)
            .foregroundStyle(Theme.Palette.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
            .cardStyle(padding: 0)
    }

    private func listingRow(_ listing: FoodListing) -> some View {
        Button {
            navigationPath.append(LocationDetail.listing(listing.persistentModelID))
        } label: {
            ListingCard(
                listing: listing,
                distanceText: location.distanceText(to: listing.coordinate),
                showsBookingCode: true
            )
        }
        .buttonStyle(PlainRowButtonStyle())
    }

    private var activeBookings: [FoodListing] {
        listings
            .filter { listing in
                let involved = session.matches(listing.postedByDeviceID)
                    || session.matches(listing.claimedByDeviceID)
                guard involved else { return false }
                let status = listing.effectiveStatus
                return status == .reserved || status == .readyForPickup
            }
            .sorted { lhs, rhs in
                bookingActivityDate(for: lhs) > bookingActivityDate(for: rhs)
            }
    }

    private var myListings: [FoodListing] {
        listings.filter { session.matches($0.postedByDeviceID) }
    }

    private var myAvailableListings: [FoodListing] {
        myListings.filter { $0.effectiveStatus == .available }
    }

    private var historyListings: [FoodListing] {
        listings
            .filter { listing in
                session.matches(listing.postedByDeviceID) || session.matches(listing.claimedByDeviceID)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func historyRole(for listing: FoodListing) -> String {
        if session.matches(listing.postedByDeviceID) {
            return String(localized: "You posted this")
        }
        return String(localized: "You reserved this")
    }

    private func bookingActivityDate(for listing: FoodListing) -> Date {
        listing.reservedUntil ?? listing.createdAt
    }
}
