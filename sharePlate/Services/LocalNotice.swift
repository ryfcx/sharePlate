//
// localnotice.swift
// shareplate
//
// opens matching handoff when user taps a notification
// alerts are system notifications, not an in app banner
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class LocalNotice {
    static let shared = LocalNotice()

    // opens handoff screen for this listing after tap
    var pendingHandoffListingRemoteID: String?

    private init() {}

    func openHandoff(listingRemoteID: String) {
        pendingHandoffListingRemoteID = listingRemoteID
    }
}
