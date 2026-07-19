//
//  FontRegistrar.swift
//  sharePlate
//
//  Registers the bundled Manrope and Inter font files at launch so they are
//  available to `Font.custom`. If a file is missing, custom fonts gracefully
//  fall back to the system font.
//

import Foundation
import CoreText

enum FontRegistrar {
    static func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else {
            return
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
