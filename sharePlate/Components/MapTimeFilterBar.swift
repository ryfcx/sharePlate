//
//  MapTimeFilterBar.swift
//  sharePlate
//
//  Wireframe Screen A — Near / Today / Tomorrow tabs.
//

import SwiftUI

struct MapTimeFilterBar: View {
    @Binding var selection: MapTimeWindow

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(MapTimeWindow.allCases) { window in
                let isSelected = selection == window
                Button {
                    withoutAnimation { selection = window }
                } label: {
                    Label(window.displayName, systemImage: window.systemImage)
                        .font(AppFont.footnote)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isSelected ? Theme.Palette.primaryGreen : Theme.Palette.cardBackground)
                        .foregroundStyle(isSelected ? Color.white : Theme.Palette.primaryText)
                        .boxBorder(isSelected ? Theme.Palette.primaryGreen.opacity(0.5) : Theme.Palette.hairline)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
