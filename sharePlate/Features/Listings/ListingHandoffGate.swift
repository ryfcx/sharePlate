//
//  ListingHandoffGate.swift
//  sharePlate
//
//  Routes between listing detail and the active handoff screen based on
//  live listing state — switches automatically after a successful reserve.
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
                // Also unlock if someone else now holds the claim — e.g. our hold
                // lapsed and another device reserved it before we re-synced. We're
                // no longer a participant in the current handoff, so don't stay
                // parked on (and able to cancel) someone else's reservation.
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
