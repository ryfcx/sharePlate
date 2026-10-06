//
//  LocalNotice.swift
//  sharePlate
//
//  Opens the matching handoff when the user taps an Apple notification.
//  Alerts themselves are system notifications, not an in-app banner.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class LocalNotice {
    static let shared = LocalNotice()

    /// Opens the handoff screen for this listing after a notification tap.
    var pendingHandoffListingRemoteID: String?

    private init() {}

    func openHandoff(listingRemoteID: String) {
        pendingHandoffListingRemoteID = listingRemoteID
    }
}
