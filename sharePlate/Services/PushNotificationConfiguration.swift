//
//  PushNotificationConfiguration.swift
//  sharePlate
//
//  Personal/free Apple Developer teams cannot enable Push Notifications.
//  Realtime handoff updates work without push. When you enroll in the paid
//  Apple Developer Program ($99/yr):
//  1. Set `isEnabled = true` below
//  2. Add sharePlate.Push.entitlements to CODE_SIGN_ENTITLEMENTS in Xcode
//  3. Enable Push Notifications capability on the target
//  See supabase/README_PUSH.md for Supabase setup.
//

import Foundation

enum PushNotificationConfiguration {
    /// Flip to `true` only with a paid Apple Developer account + push entitlements.
    static let isEnabled = false
}
