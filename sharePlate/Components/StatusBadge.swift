//
//  statusbadge.swift
//  shareplate
//

import SwiftUI

struct StatusBadge: View {
    let status: ListingStatus

    var body: some View {
        Text(status.displayName)
            .font(AppFont.captionBold)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.14))
            .foregroundStyle(status.tint)
            .boxBorder(status.tint.opacity(0.3))
    }
}

struct TypeBadge: View {
    let type: ResourceType

    var body: some View {
        Label(type.shortName, systemImage: type.symbol)
            .font(AppFont.captionBold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(type.tint.opacity(0.14))
            .foregroundStyle(type.tint)
            .boxBorder(type.tint.opacity(0.3))
    }
}
