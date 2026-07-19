//
//  SessionContext.swift
//  sharePlate
//
//  Lightweight stand-in for a future authenticated user. For now it holds a
//  stable per-device identifier so posting/claiming can be attributed locally.
//  When a real "universal login" backend is added, this is where the signed-in
//  user identity would live, leaving the views unchanged.
//

import Foundation
import SwiftUI

@Observable
final class SessionContext {
    /// Stable per-device fallback identifier (used before sign-in / for anonymous data).
    let deviceID: String

    /// Set by the auth service when a user signs in; cleared on sign out.
    var currentUserID: String?

    /// The identity that posts/claims are attributed to. Prefers the signed-in
    /// user, falling back to the device ID.
    var identity: String { currentUserID ?? deviceID }

    init() {
        let key = "sharePlate.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            deviceID = existing
        } else {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: key)
            deviceID = new
        }
    }

    /// Case-insensitive match for Supabase user ids (UUID strings may differ in casing).
    func matches(_ userID: String?) -> Bool {
        guard let userID else { return false }
        return identity.caseInsensitiveCompare(userID) == .orderedSame
    }
}
