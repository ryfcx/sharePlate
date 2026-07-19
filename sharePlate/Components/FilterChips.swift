//
//  FilterChips.swift
//  sharePlate
//

import SwiftUI

struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    var tint: Color = Theme.Palette.primaryGreen
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
            }
            .font(AppFont.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected ? tint : Theme.Palette.cardBackground,
                in: RoundedRectangle(cornerRadius: Theme.Radius.tag)
            )
            .foregroundStyle(isSelected ? Color.white : Theme.Palette.primaryText)
            .boxBorder(isSelected ? tint.opacity(0.4) : Theme.Palette.hairline, radius: Theme.Radius.tag)
        }
        .buttonStyle(.plain)
    }
}
