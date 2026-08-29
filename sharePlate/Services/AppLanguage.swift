//
//  AppLanguage.swift
//  sharePlate
//
//  In-app language override, independent of the device's iOS system
//  language. SwiftUI's `.environment(\.locale, ...)` only affects `Text`
//  views built from string literals — it does nothing for plain `String`
//  values (e.g. `FoodListing.postedRelativeText`, enum `displayName`
//  properties) that get built off the view hierarchy. To make *both* kinds
//  of content follow the in-app choice, this swaps which `.lproj` bundle
//  `Bundle.main` resolves strings from at the Bundle-lookup layer, which is
//  what both `Text(LocalizedStringKey)` and `String(localized:)` ultimately
//  query. This is the standard technique for a language switch that isn't
//  tied to Settings.app.
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
        case .system: return "System Default"
        case .english: return "English"
        case .spanish: return "Español"
        }
    }

    /// Applies this language to `Bundle.main` lookups app-wide. Call again
    /// whenever the stored preference changes — cheap, safe to call repeatedly.
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

    /// A `Locale` matching this choice, for `.environment(\.locale, ...)` —
    /// covers date/number formatting for code that reads locale from the
    /// SwiftUI environment.
    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .english, .spanish: return Locale(identifier: rawValue)
        }
    }
}

/// Subclass swapped onto `Bundle.main` by `AppLanguage.apply`. Redirects
/// string lookups to the chosen language's `.lproj` bundle when one is set;
/// otherwise behaves exactly like a normal bundle (system default).
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
