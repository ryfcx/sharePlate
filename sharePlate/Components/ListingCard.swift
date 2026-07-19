//
//  ListingCard.swift
//  sharePlate
//

import SwiftUI

struct ListingCard: View {
    let listing: FoodListing
    var distanceText: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ListingPhotoView(listing: listing, thumbnailSize: 56)

            VStack(alignment: .leading, spacing: 5) {
                Text(listing.title)
                    .font(AppFont.headline)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(AppFont.subheadline)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    CountdownText(deadline: listing.pickupDeadline, live: false)
                    if let distanceText {
                        Text("•").foregroundStyle(Theme.Palette.mutedText)
                        Text(distanceText).foregroundStyle(Theme.Palette.mutedText)
                    }
                }
                .font(AppFont.caption)
            }

            Spacer(minLength: 0)

            if listing.effectiveStatus != .available {
                StatusBadge(status: listing.effectiveStatus)
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle(padding: 0)
        .browseRowStyle()
    }

    private var subtitle: String {
        let mode = listing.isDropOff ? "Drop off" : "Pickup"
        return "\(listing.packageSummaryLabel) · \(mode) · \(listing.areaLabel)"
    }
}
