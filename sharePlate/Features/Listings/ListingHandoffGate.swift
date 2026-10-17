//
// listinghandoffgate.swift
// shareplate
//
// routes between detail and handoff based on live state
// switches after a successful reserve
//

import SwiftUI

struct ListingHandoffGate: View {
    @Environment(SessionContext.self) private var session
    @Environment(LocalDataStore.self) private var store
    @Bindable var listing: FoodListing

    @State private var lockedInHandoff = false

    private var isHandoff: Bool {
        ActiveReservationView.isActiveParticipant(listing, session: session)
    }

    private var isOwner: Bool {
        session.matches(listing.postedByDeviceID)
    }

    private var showHandoff: Bool {
        lockedInHandoff || isHandoff
    }

    var body: some View {
        Group {
            if !listing.isApprovedForSharing {
                if isOwner {
                    ProviderListingManageView(listing: listing)
                } else {
                    ContentUnavailableView("Listing unavailable", systemImage: "hand.raised",
                        description: Text("This listing is not available for pickup."))
                }
            } else if showHandoff {
                ActiveReservationView(listing: listing)
            } else if isOwner {
                ProviderListingManageView(listing: listing)
            } else if store.isUserBlocked(listing.postedByDeviceID) {
                ContentUnavailableView("User blocked", systemImage: "person.crop.circle.badge.xmark",
                    description: Text("You can manage blocked users in Settings."))
            } else {
                ListingDetailView(listing: listing)
            }
        }
        .animation(nil, value: showHandoff)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ReportListingButton(listing: listing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                BlockUserButton(listing: listing)
            }
        }
        .onChange(of: isHandoff) { _, active in
            if active {
                lockedInHandoff = true
            } else if listing.effectiveStatus == .pickedUp
                        || listing.effectiveStatus == .expired
                        || listing.claimedByDeviceID == nil
                        || (!isOwner && !session.matches(listing.claimedByDeviceID)) {
                // unlock if someone else holds the claim now
                // our hold lapsed and another device reserved it
                // we are no longer part of this handoff
                // so do not stay on their reservation
                lockedInHandoff = false
            }
        }
        .onAppear {
            if isHandoff {
                lockedInHandoff = true
            }
        }
    }
}
