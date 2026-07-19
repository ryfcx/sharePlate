//
//  MapLegendView.swift
//  sharePlate
//
//  Wireframe Screen A — pin color legend on the map.
//

import SwiftUI

struct MapLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Map key")
                .font(AppFont.captionBold)
                .foregroundStyle(Theme.Palette.primaryText)

            ForEach([MapPlaceOpenStatus.open, .closingSoon, .closed], id: \.self) { status in
                HStack(spacing: Theme.Spacing.sm) {
                    Circle()
                        .fill(status.pinColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1))
                    Text(status.legendLabel)
                        .font(AppFont.caption)
                        .foregroundStyle(Theme.Palette.mutedText)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.cardBackground.opacity(0.94))
        .boxBorder(radius: Theme.Radius.control)
    }
}
