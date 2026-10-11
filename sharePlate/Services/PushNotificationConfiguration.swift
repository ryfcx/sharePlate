//
// pushnotificationconfiguration.swift
// shareplate
//
// free apple teams cannot enable push notifications
// realtime handoff updates work without push
// to enable with paid program, flip flag below
// then add entitlements and capability in xcode
// see supabase push readme for supabase setup
//

import Foundation

enum PushNotificationConfiguration {
    // flip to true only with paid account plus push entitlements
    static let isEnabled = false
}
