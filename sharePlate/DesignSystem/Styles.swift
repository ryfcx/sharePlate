//
//  Styles.swift
//  sharePlate
//
//  Flat view modifiers and button styles — borders, no shadows, no rounding.
//

import SwiftUI

// MARK: - Screen background

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.Palette.backgroundCream.ignoresSafeArea())
    }
}

extension View {
    func screenBackground() -> some View {
        modifier(ScreenBackground())
    }

    func boxBorder(_ color: Color = Theme.Palette.hairline, radius: CGFloat = Theme.Radius.control) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius).stroke(color, lineWidth: 1))
    }

    /// Disables implicit SwiftUI animations for snappier tab/filter transitions.
    func withoutAnimation(_ action: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, action)
    }
}

func withoutAnimation(_ action: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, action)
}

// MARK: - Card

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.Palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .boxBorder(radius: Theme.Radius.card)
    }
}

extension View {
    func cardStyle(padding: CGFloat = Theme.Spacing.lg) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Standard tappable browse row (listings, resources, nearby).
    func browseRowStyle() -> some View {
        contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.primaryGreen
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.button)
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 48)
            .padding(.horizontal, 16)
            .background(configuration.isPressed ? tint.opacity(0.88) : tint, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.primaryGreen
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.button)
            .foregroundStyle(tint)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 48)
            .padding(.horizontal, 16)
            .background(
                configuration.isPressed ? tint.opacity(0.08) : Theme.Palette.cardBackground,
                in: RoundedRectangle(cornerRadius: Theme.Radius.control)
            )
            .boxBorder(tint.opacity(0.35), radius: Theme.Radius.control)
    }
}

struct PlainRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
