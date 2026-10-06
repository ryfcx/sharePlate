//
//  BookingDashboardRow.swift
//  sharePlate
//
//  Active booking row with a large matching code and compact QR.
//

import SwiftUI

struct BookingDashboardRow: View {
    let listing: FoodListing
    let isProvider: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Booking")
                    .font(AppFont.captionBold)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .textCase(.uppercase)
                    .tracking(1.2)

                Text(listing.bookingCode)
                    .font(AppFont.largeTitle)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.primaryText)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                HStack(spacing: Theme.Spacing.sm) {
                    Text(listing.packagesShortLabel)
                        .font(AppFont.headline)
                        .foregroundStyle(Theme.Palette.primaryText)

                    statusTag

                    Spacer(minLength: 0)

                    Text(isProvider ? "Giving" : "Getting")
                        .font(AppFont.captionBold)
                        .foregroundStyle(isProvider ? Theme.Palette.primaryGreen : Theme.Palette.mealBlue)
                }

                Text(listing.title)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .lineLimit(1)
            }

            BookingQRMark(code: listing.bookingCode, size: 72)
        }
        .padding(Theme.Spacing.lg)
        .cardStyle(padding: 0)
    }

    @ViewBuilder
    private var statusTag: some View {
        let status = listing.effectiveStatus
        let label = status == .readyForPickup ? "[ready]" : "[reserved]"
        Text(label)
            .font(AppFont.captionBold)
            .foregroundStyle(status.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.12))
            .boxBorder(status.tint.opacity(0.35), radius: Theme.Radius.tag)
    }
}
