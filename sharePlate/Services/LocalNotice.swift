//
//  LocalNotice.swift
//  sharePlate
//
//  In-app notice center for handoff events. Works alongside APNs — when the app
//  is open, Realtime updates the UI and a banner gives a tap-to-open shortcut.
//

import Foundation
import SwiftUI

enum LocalNoticeEvent {
    case foodReserved(title: String, listingRemoteID: String)
    case yourListingWasReserved(title: String, listingRemoteID: String)
    case reservationReleased(title: String, listingRemoteID: String)
    case waitlistJoined(title: String)
    case nowAvailable(title: String)
    case foodPickedUp(title: String, listingRemoteID: String)
    case listingExpired(title: String)
    case quickUpdate(text: String, listingRemoteID: String)
    case instructionsUpdated(title: String, listingRemoteID: String)

    var message: String {
        switch self {
        case .foodReserved(let title, _):
            return "\"\(title)\" is reserved. Open it for pickup details."
        case .yourListingWasReserved(let title, _):
            return "Someone reserved \"\(title)\". Tap to view the handoff."
        case .reservationReleased(let title, _):
            return "Reservation for \"\(title)\" was released."
        case .waitlistJoined(let title):
            return "You'll be notified if \"\(title)\" reopens."
        case .nowAvailable(let title):
            return "\"\(title)\" is available again."
        case .foodPickedUp(let title, _):
            return "\"\(title)\" was marked picked up."
        case .listingExpired(let title):
            return "\"\(title)\" has expired."
        case .quickUpdate(let text, _):
            return text
        case .instructionsUpdated(let title, _):
            return "Pickup details for \"\(title)\" are ready."
        }
    }

    var symbol: String {
        switch self {
        case .foodReserved: return "lock.open.fill"
        case .yourListingWasReserved: return "bell.badge.fill"
        case .reservationReleased: return "arrow.uturn.backward.circle.fill"
        case .waitlistJoined: return "bell.badge.fill"
        case .nowAvailable: return "checkmark.circle.fill"
        case .foodPickedUp: return "checkmark.seal.fill"
        case .listingExpired: return "clock.badge.xmark.fill"
        case .quickUpdate: return "bubble.left.fill"
        case .instructionsUpdated: return "list.bullet.clipboard.fill"
        }
    }

    var listingRemoteID: String? {
        switch self {
        case .foodReserved(_, let remoteID): return remoteID
        case .yourListingWasReserved(_, let remoteID): return remoteID
        case .reservationReleased(_, let remoteID): return remoteID
        case .foodPickedUp(_, let remoteID): return remoteID
        case .quickUpdate(_, let remoteID): return remoteID
        case .instructionsUpdated(_, let remoteID): return remoteID
        default: return nil
        }
    }
}

@MainActor
@Observable
final class LocalNotice {
    static let shared = LocalNotice()

    private(set) var current: (id: UUID, event: LocalNoticeEvent)?
    /// Opens the handoff screen for this listing when the user taps the banner.
    var pendingHandoffListingRemoteID: String?

    private init() {}

    static func post(_ event: LocalNoticeEvent) {
        shared.show(event)
    }

    /// Maps APNs payload from the Edge Function into an in-app banner.
    static func postFromPush(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }
        let title = userInfo["listing_title"] as? String ?? "Food"
        let listingID = userInfo["listing_id"] as? String ?? ""

        let event: LocalNoticeEvent? = switch type {
        case "listing_reserved":
            .yourListingWasReserved(title: title, listingRemoteID: listingID)
        case "instructions_updated":
            .instructionsUpdated(title: title, listingRemoteID: listingID)
        case "message":
            if let body = userInfo["body"] as? String, !listingID.isEmpty {
                .quickUpdate(text: "\(body) — \(title)", listingRemoteID: listingID)
            } else {
                nil
            }
        case "ready_for_pickup":
            .quickUpdate(text: "Food is ready for pickup — \(title)", listingRemoteID: listingID)
        case "picked_up":
            .foodPickedUp(title: title, listingRemoteID: listingID)
        case "reservation_released":
            .reservationReleased(title: title, listingRemoteID: listingID)
        default:
            nil
        }

        if let event {
            shared.show(event)
        }
    }

    func show(_ event: LocalNoticeEvent) {
        let id = UUID()
        current = (id, event)
        Task {
            try? await Task.sleep(for: .seconds(6))
            if self.current?.id == id {
                self.current = nil
            }
        }
    }

    func dismiss() {
        current = nil
    }

    func openHandoff(listingRemoteID: String) {
        pendingHandoffListingRemoteID = listingRemoteID
        dismiss()
    }
}
