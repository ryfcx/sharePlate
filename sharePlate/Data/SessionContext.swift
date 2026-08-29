//
//  SessionContext.swift
//  sharePlate
//
//  Per-device identity. There's no login screen: `currentUserID` is populated
//  by a silent anonymous Supabase auth session (see SupabaseAuthService) so
//  Postgres RLS still has a stable auth.uid() to key off of, while `deviceID`
//  is a local fallback. `displayName` is a name the user picks in Settings —
//  it's not tied to any account, just a label attached to this device.
//

import Foundation
import SwiftUI

@Observable
final class SessionContext {
    /// Stable per-device fallback identifier (used before the anonymous session is ready).
    let deviceID: String

    /// Populated by SupabaseAuthService once the silent anonymous session is established.
    var currentUserID: String?

    /// The identity that posts/claims are attributed to. Prefers the anonymous
    /// auth user, falling back to the device ID.
    var identity: String { currentUserID ?? deviceID }

    private let displayNameKey = "sharePlate.displayName"

    /// Name the user set in Settings. Defaults to "Neighbor" until they change it.
    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: displayNameKey) }
    }

    init() {
        let key = "sharePlate.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            deviceID = existing
        } else {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: key)
            deviceID = new
        }
        displayName = UserDefaults.standard.string(forKey: displayNameKey) ?? "Neighbor"
    }

    /// Case-insensitive match for Supabase user ids (UUID strings may differ in casing).
    func matches(_ userID: String?) -> Bool {
        guard let userID else { return false }
        return identity.caseInsensitiveCompare(userID) == .orderedSame
    }
}
