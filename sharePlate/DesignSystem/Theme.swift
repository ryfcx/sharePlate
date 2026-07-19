//
//  Theme.swift
//  sharePlate
//
//  Flat, boxy design tokens — simple borders, square corners, no shadows.
//

import SwiftUI

// MARK: - Color from hex

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Palette

enum Theme {
    enum Palette {
        static let primaryGreen = Color(hex: 0x2E7D32)
        static let accentOrange = Color(hex: 0xF4A261)
        static let backgroundCream = Color(hex: 0xF7F4EA)
        static let cardBackground = Color(hex: 0xFFFFFF)
        static let primaryText = Color(hex: 0x1F2937)
        static let mutedText = Color(hex: 0x6B7280)

        // Map pin / category colors
        static let pantryGreen = Color(hex: 0x2E7D32)
        static let availableOrange = Color(hex: 0xF4A261)
        static let mealBlue = Color(hex: 0x2F80ED)
        static let fridgePurple = Color(hex: 0x8B5CF6)
        static let urgentRed = Color(hex: 0xE05549)
        static let mobileTeal = Color(hex: 0x14919B)
        static let limitedYellow = Color(hex: 0xD98A0B)

        // Borders / fills
        static let hairline = Color(hex: 0xCCCCCC)
        static let softFill = Color(hex: 0xEFEBDD)
    }

    /// Subtle corners — flat layout, not fully square.
    enum Radius {
        static let card: CGFloat = 8
        static let control: CGFloat = 6
        static let tag: CGFloat = 4
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

// MARK: - Typography (Manrope for headings/UI, Inter for body)

enum AppFont {
    private enum Manrope: String {
        case regular = "Manrope-Regular"
        case medium = "Manrope-Medium"
        case semibold = "Manrope-SemiBold"
        case bold = "Manrope-Bold"
        case extrabold = "Manrope-ExtraBold"
    }

    private enum Inter: String {
        case regular = "Inter-Regular"
        case medium = "Inter-Medium"
        case semibold = "Inter-SemiBold"
        case bold = "Inter-Bold"
    }

    private static func manrope(_ face: Manrope, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
        .custom(face.rawValue, size: size, relativeTo: style)
    }

    private static func inter(_ face: Inter, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
        .custom(face.rawValue, size: size, relativeTo: style)
    }

    static var largeTitle: Font { manrope(.extrabold, 30, .largeTitle) }
    static var title: Font { manrope(.bold, 24, .title) }
    static var title2: Font { manrope(.bold, 20, .title2) }
    static var title3: Font { manrope(.semibold, 18, .title3) }
    static var headline: Font { manrope(.semibold, 16, .headline) }
    static var button: Font { manrope(.semibold, 16, .body) }
    static var tabLabel: Font { manrope(.semibold, 11, .caption2) }

    static var body: Font { inter(.regular, 16, .body) }
    static var bodyMedium: Font { inter(.medium, 16, .body) }
    static var callout: Font { inter(.regular, 15, .callout) }
    static var subheadline: Font { inter(.regular, 14, .subheadline) }
    static var subheadlineMedium: Font { inter(.medium, 14, .subheadline) }
    static var footnote: Font { inter(.medium, 13, .footnote) }
    static var caption: Font { inter(.medium, 12, .caption) }
    static var captionBold: Font { inter(.semibold, 12, .caption) }
}
