//
//  BookingDashboardRow.swift
//  sharePlate
//
//  Wireframe Screen E — compact booking row: `1234: 2x [on my way]`.
//

import SwiftUI

struct BookingDashboardRow: View {
    let listing: FoodListing
    let isProvider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                Text(listing.bookingCode)
                    .font(AppFont.headline.monospacedDigit())
                    .foregroundStyle(Theme.Palette.primaryText)
                    .frame(minWidth: 36, alignment: .leading)

                Text(":")
                    .font(AppFont.headline)
                    .foregroundStyle(Theme.Palette.mutedText)

                Text(listing.packagesShortLabel)
                    .font(AppFont.headline)
                    .foregroundStyle(Theme.Palette.primaryText)

                Spacer(minLength: Theme.Spacing.sm)

                statusTag
            }

            HStack(spacing: Theme.Spacing.sm) {
                Text(listing.title)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(isProvider ? "Giving" : "Getting")
                    .font(AppFont.captionBold)
                    .foregroundStyle(isProvider ? Theme.Palette.primaryGreen : Theme.Palette.mealBlue)
            }
        }
        .padding(Theme.Spacing.lg)
        .cardStyle(padding: 0)
    }

    @ViewBuilder
    private var statusTag: some View {
        if listing.effectiveStatus == .readyForPickup {
            Text("[ready]")
                .font(AppFont.captionBold)
                .foregroundStyle(Theme.Palette.mealBlue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.Palette.mealBlue.opacity(0.12))
                .boxBorder(Theme.Palette.mealBlue.opacity(0.35), radius: Theme.Radius.tag)
        } else {
            Text("[reserved]")
                .font(AppFont.captionBold)
                .foregroundStyle(Theme.Palette.accentOrange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.Palette.accentOrange.opacity(0.12))
                .boxBorder(Theme.Palette.accentOrange.opacity(0.35), radius: Theme.Radius.tag)
        }
    }
}
