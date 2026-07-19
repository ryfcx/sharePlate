//
//  ProviderListingManageView.swift
//  sharePlate
//
//  Provider dashboard for an unclaimed listing — not the public consumer view.
//

import SwiftUI

struct ProviderListingManageView: View {
    @Bindable var listing: FoodListing

    private var instructions: ReservationCoordination {
        listing.publishedPickupInstructions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ListingPhotoView(listing: listing, height: 200)

                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.title)
                        .font(AppFont.title2)
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text("Your listing · \(listing.postedRelativeText)")
                        .font(AppFont.caption)
                        .foregroundStyle(Theme.Palette.mutedText)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    StatusBadge(status: listing.effectiveStatus)
                    CountdownText(deadline: listing.pickupDeadline, live: true)
                        .font(AppFont.caption)
                }

                pickupDetailsCard
                listingFactsCard

                if !listing.waitlistDeviceIDs.isEmpty {
                    Label("\(listing.waitlistDeviceIDs.count) neighbor(s) on waitlist", systemImage: "bell.badge")
                        .font(AppFont.subheadlineMedium)
                        .foregroundStyle(Theme.Palette.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                }

                actionsCard
            }
            .padding(Theme.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("Manage listing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pickupDetailsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Pickup details you set")
                .font(AppFont.headline)

            detailLine("Meet at", instructions.meetupAddress)
            if let timeslot = instructions.timeslot {
                detailLine("Ready by", timeslot.formatted(date: .abbreviated, time: .shortened))
            }
            if let spot = instructions.handoffSpot {
                detailLine("Handoff", spot.displayName)
            }
            if !instructions.providerNote.isEmpty {
                detailLine("Note", instructions.providerNote)
            }
        }
        .cardStyle()
    }

    private var listingFactsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            detailLine("Packages", listing.packageSummaryLabel)
            detailLine("Type", listing.category.displayName)
            detailLine("Area", listing.areaLabel)
            detailLine("Deadline", listing.pickupDeadline.formatted(date: .abbreviated, time: .shortened))
        }
        .cardStyle()
    }

    private var actionsCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            if listing.effectiveStatus == .available {
                Text("Waiting for someone to reserve. Mark as picked up once the food is gone.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            CompleteHandoffButton(listing: listing)
        }
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(Theme.Palette.mutedText)
            Text(value)
                .font(AppFont.body)
                .foregroundStyle(Theme.Palette.primaryText)
        }
    }
}
