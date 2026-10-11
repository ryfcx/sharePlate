//
//  shareplatelogoview.swift
//  shareplate
//

import SwiftUI

struct SharePlateLogoView: View {
    var size: CGFloat = 34

    var body: some View {
        Image("SharePlateLogo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(Theme.Palette.hairline.opacity(0.7), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}
