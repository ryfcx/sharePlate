//
//  maplegendview.swift
//  shareplate
//
//  pin color legend on the map
//

import SwiftUI

struct MapLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Map key")
                .font(AppFont.captionBold)
                .foregroundStyle(Theme.Palette.primaryText)

            legendRow(color: Theme.Palette.fridgePurple, label: "Neighbor")
            legendRow(color: Theme.Palette.primaryGreen, label: "Grocery or restaurant")

            ForEach([MapPlaceOpenStatus.open, .closingSoon, .closed], id: \.self) { status in
                legendRow(color: status.pinColor, label: status.legendLabel)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.cardBackground.opacity(0.94))
        .boxBorder(radius: Theme.Radius.control)
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(.white, lineWidth: 1))
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(Theme.Palette.mutedText)
        }
    }
}
