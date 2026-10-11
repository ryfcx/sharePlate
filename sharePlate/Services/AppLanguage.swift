//
// applanguage.swift
// shareplate
//
// in app language override, independent of device language
// swiftui locale only affects text views from string literals
// it does nothing for plain string values built off view hierarchy
// like posted relative text or enum display names
// to make both kinds follow in app choice
// this swaps which lproj bundle main resolves strings from
// at the bundle lookup layer, which is what both kinds query
// this is the standard technique for a switch not tied to settings
//

import Foundation
import ObjectiveC

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case spanish = "es"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System Default")
        case .english: return String(localized: "English")
        case .spanish: return String(localized: "Español")
        }
    }

    // applies this language to main bundle lookups app wide
    // call again when stored preference changes, safe to repeat
    static func apply(_ language: AppLanguage) {
        if object_getClass(Bundle.main) != LanguageOverrideBundle.self {
            object_setClass(Bundle.main, LanguageOverrideBundle.self)
        }

        switch language {
        case .system:
            objc_setAssociatedObject(Bundle.main, &LanguageOverrideBundle.pathKey, nil, .OBJC_ASSOCIATION_RETAIN)
        case .english, .spanish:
            let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
            objc_setAssociatedObject(Bundle.main, &LanguageOverrideBundle.pathKey, path, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    // a locale matching this choice, for swiftui environment
    // covers date and number formatting from environment locale
    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .english, .spanish: return Locale(identifier: rawValue)
        }
    }
}

// subclass swapped onto main bundle by apply
// redirects string lookups to chosen language bundle when set
// otherwise behaves like a normal bundle with system default
private final class LanguageOverrideBundle: Bundle, @unchecked Sendable {
    fileprivate static var pathKey: UInt8 = 0

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let path = objc_getAssociatedObject(self, &Self.pathKey) as? String,
              let overrideBundle = Bundle(path: path) else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return overrideBundle.localizedString(forKey: key, value: value, table: tableName)
    }
}
