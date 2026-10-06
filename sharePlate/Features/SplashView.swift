//
//  SplashView.swift
//  sharePlate
//
//  Branded startup screen shown after the system launch image while
//  anonymous auth finishes. Layout matches LaunchScreen.storyboard so
//  the handoff does not jump.
//

import SwiftUI

struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SharePlateLogoView(size: 120)
                .scaleEffect(appeared ? 1 : 0.88)
                .opacity(appeared ? 1 : 0.7)

            VStack(spacing: Theme.Spacing.sm) {
                Text("SharePlate")
                    .font(AppFont.largeTitle)
                    .foregroundStyle(Theme.Palette.primaryText)

                Text("Share extra food with your neighbors.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Theme.Palette.mutedText)
                    .multilineTextAlignment(.center)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.backgroundCream.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
