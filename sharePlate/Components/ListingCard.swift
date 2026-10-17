//
//  listingcard.swift
//  shareplate
//

import SwiftUI

struct ListingCard: View {
    @Environment(SessionContext.self) private var session

    let listing: FoodListing
    var distanceText: String?
    var showsBookingCode = true

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ListingPhotoView(listing: listing, thumbnailSize: 56)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(listing.title)
                        .font(AppFont.headline)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(1)
                    if listing.isApprovedForSharing, showsBookingCode,
                       listing.revealsBookingCode || session.matches(listing.postedByDeviceID) {
                        Text(listing.bookingCode)
                            .font(AppFont.captionBold)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.primaryGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Palette.primaryGreen.opacity(0.12))
                            .boxBorder(Theme.Palette.primaryGreen.opacity(0.35), radius: Theme.Radius.tag)
                    }
                }

                Text(subtitle)
                    .font(AppFont.subheadline)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .lineLimit(1)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        availabilityText
                        if let distanceText {
                            Text("•").foregroundStyle(Theme.Palette.mutedText)
                            Text(distanceText).foregroundStyle(Theme.Palette.mutedText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        availabilityText
                        if let distanceText {
                            Text(distanceText).foregroundStyle(Theme.Palette.mutedText)
                        }
                    }
                }
                .font(AppFont.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if !listing.isApprovedForSharing {
                Text(listing.moderationLabel)
                    .font(AppFont.captionBold)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if listing.effectiveStatus != .available {
                StatusBadge(status: listing.effectiveStatus)
                    .fixedSize()
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle(padding: 0)
        .browseRowStyle()
    }

    private var subtitle: String {
        if listing.isPermanent {
            return String(localized: "Store · \(listing.areaLabel)")
        }
        let mode = listing.isDropOff ? String(localized: "Drop off") : String(localized: "Pickup")
        return String(localized: "\(listing.packageSummaryLabel) · \(mode) · \(listing.areaLabel)")
    }

    @ViewBuilder
    private var availabilityText: some View {
        if listing.isPermanent || listing.isStandingLocation {
            Text("Always available")
                .foregroundStyle(Theme.Palette.primaryGreen)
        } else {
            CountdownText(deadline: listing.pickupDeadline, live: false)
        }
    }
}
