//
// fontregistrar.swift
// shareplate
//
// registers bundled manrope and inter fonts at launch
// so they are available to font custom
// if a file is missing, falls back to system font
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
