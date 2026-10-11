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
            if showHandoff {
                ActiveReservationView(listing: listing)
            } else if isOwner {
                ProviderListingManageView(listing: listing)
            } else {
                ListingDetailView(listing: listing)
            }
        }
        .animation(nil, value: showHandoff)
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
