//
//  AppAppearance.swift
//  sharePlate
//
//  Opaque, flat UIKit chrome — no translucency or glass effects.
//

import UIKit
import SwiftUI

enum AppAppearance {
    static func configure() {
        let cream = UIColor(Theme.Palette.backgroundCream)
        let primaryText = UIColor(Theme.Palette.primaryText)
        let green = UIColor(Theme.Palette.primaryGreen)
        let border = UIColor(Theme.Palette.hairline)

        // Navigation bar — solid cream, thin bottom line
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = cream
        nav.shadowColor = border

        if let large = UIFont(name: "Manrope-ExtraBold", size: 30) {
            nav.largeTitleTextAttributes = [.foregroundColor: primaryText, .font: large]
        } else {
            nav.largeTitleTextAttributes = [.foregroundColor: primaryText]
        }
        if let title = UIFont(name: "Manrope-Bold", size: 17) {
            nav.titleTextAttributes = [.foregroundColor: primaryText, .font: title]
        } else {
            nav.titleTextAttributes = [.foregroundColor: primaryText]
        }

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = nav
        navBar.scrollEdgeAppearance = nav
        navBar.compactAppearance = nav
        navBar.tintColor = green
        navBar.isTranslucent = false
    }
}
