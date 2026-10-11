//
//  resourcerow.swift
//  shareplate
//

import SwiftUI

struct ResourceRow: View {
    let resource: FoodResource
    var distanceText: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(resource.type.tint.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: resource.type.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(resource.type.tint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(resource.name)
                    .font(AppFont.headline)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                Text(resource.address)
                    .font(AppFont.subheadline)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(resource.type.shortName)
                        .foregroundStyle(resource.type.tint)
                    if let distanceText {
                        metaDot
                        Text(distanceText).foregroundStyle(Theme.Palette.mutedText)
                    }
                    let status = resource.openStatus()
                    metaDot
                    Text(status.legendLabel)
                        .foregroundStyle(status.pinColor)
                }
                .font(AppFont.caption)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .cardStyle(padding: 0)
        .browseRowStyle()
    }

    private var metaDot: some View {
        Text("·").foregroundStyle(Theme.Palette.mutedText)
    }
}
