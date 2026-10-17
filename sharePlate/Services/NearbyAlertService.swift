//
// nearbyalertservice.swift
// shareplate
//
// local notifications for nearby food and pantry openings
// scheduled openings or new food listings
// on device notifications only, not server push
// app ships without push entitlements
// pantry alerts can fire when app is fully closed
// local notifications still fire even with app closed
// new listing check only runs while app is running
// briefly after backgrounding or on location wake
//

import Foundation
import CoreLocation
import UserNotifications

@MainActor
enum NearbyAlertService {
    // matches home map near radius so alerts line up with nearby panel
    static let nearRadiusMeters: CLLocationDistance = 8046

    private static let pantryNotificationPrefix = "pantry-open-"
    private static let notifiedListingIDsKey = "nearbyAlert.notifiedListingIDs"
    private static let maxNotifiedListingIDs = 200
    private static let maxScheduledPantries = 15

    // pantry opening schedule

    // refreshes pantry open alerts for closest open pantries
    // safe to call often, clears old requests first
    static func refreshPantryOpenSchedule(resources: [FoodResource], near coordinate: CLLocationCoordinate2D) async {
        let center = UNUserNotificationCenter.current()
        guard await hasNotificationPermission(center) else { return }

        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(pantryNotificationPrefix) }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        }

        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearby = resources
            .filter { !$0.isTemporarilyClosed }
            .compactMap { resource -> (FoodResource, CLLocationDistance)? in
                let distance = userLocation.distance(from: CLLocation(latitude: resource.latitude, longitude: resource.longitude))
                guard distance <= nearRadiusMeters else { return nil }
                return (resource, distance)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(maxScheduledPantries)

        for (resource, _) in nearby {
            guard let interval = primaryWeeklyOpening(for: resource) else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Opening nearby")
            content.body = String(localized: "\(resource.name) opens at \(timeString(fromMinutes: interval.startMinutes))")
            content.sound = .default
            content.userInfo = ["type": "pantry_open"]

            var comps = DateComponents()
            comps.weekday = interval.weekday
            comps.hour = interval.startMinutes / 60
            comps.minute = interval.startMinutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

            let identifier = "\(pantryNotificationPrefix)\(resource.gcfdLocationID ?? resource.name.hashValue)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    // first weekly opening used as the single opens at alert
    // keeps scheduled count well under the system limit
    private static func primaryWeeklyOpening(for resource: FoodResource) -> OpeningInterval? {
        resource.openingIntervals.first { !$0.everyOtherWeek && $0.weeksOfMonth.isEmpty }
    }

    private static func timeString(fromMinutes minutes: Int) -> String {
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        let calendar = Calendar.current
        guard let date = calendar.date(from: comps) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    // new nearby listings

    static func removeListingAlerts(for listings: [FoodListing]) {
        let ids = listings.compactMap { $0.remoteID.map { "new-listing-\($0)" } }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // checks recent listings for nearby ones not posted by this device
    // sends a notification for each match
    // call when local catalog changes while app is running
    static func checkForNewNearbyListings(
        _ listings: [FoodListing],
        near coordinate: CLLocationCoordinate2D,
        excludingDeviceID: String
    ) async {
        let center = UNUserNotificationCenter.current()
        guard await hasNotificationPermission(center) else { return }

        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var notifiedIDs = Set(UserDefaults.standard.stringArray(forKey: notifiedListingIDsKey) ?? [])

        for listing in listings {
            guard listing.isApprovedForSharing, listing.effectiveStatus == .available else { continue }
            guard let remoteID = listing.remoteID, !notifiedIDs.contains(remoteID) else { continue }
            guard listing.postedByDeviceID.caseInsensitiveCompare(excludingDeviceID) != .orderedSame else { continue }

            let distance = userLocation.distance(from: CLLocation(latitude: listing.latitude, longitude: listing.longitude))
            guard distance <= nearRadiusMeters else { continue }

            let content = UNMutableNotificationContent()
            content.title = listing.isPantryListing
                ? String(localized: "New pantry food nearby")
                : String(localized: "New food posted nearby")
            content.body = String(localized: "\(listing.title) · \(listing.areaLabel)")
            content.sound = .default
            content.userInfo = ["type": "new_listing", "listing_id": remoteID]

            let request = UNNotificationRequest(identifier: "new-listing-\(remoteID)", content: content, trigger: nil)
            try? await center.add(request)

            notifiedIDs.insert(remoteID)
        }

        if notifiedIDs.count > maxNotifiedListingIDs {
            notifiedIDs = Set(notifiedIDs.suffix(maxNotifiedListingIDs))
        }
        UserDefaults.standard.set(Array(notifiedIDs), forKey: notifiedListingIDsKey)
    }

    // posting confirmation

    // confirms own listing went live with its reference number
    static func notifyListingPosted(_ listing: FoodListing) async {
        let center = UNUserNotificationCenter.current()
        guard await hasNotificationPermission(center) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Listing posted")
        content.body = String(localized: "\(listing.title) is live — Listing \(listing.listingNumber)")
        content.sound = .default
        content.userInfo = ["type": "listing_posted", "listing_id": listing.remoteID ?? ""]

        let request = UNNotificationRequest(
            identifier: "listing-posted-\(listing.remoteID ?? UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    // provider reservation alert

    // alerts provider when one of their listings gets reserved
    // works while app is running or briefly in background
    static func notifyListingReserved(_ listing: FoodListing) async {
        guard let remoteID = listing.remoteID else { return }
        let center = UNUserNotificationCenter.current()
        guard await hasNotificationPermission(center) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Food reserved")
        content.body = String(localized: "\(listing.packagesLabel) reserved from \(listing.title) · Booking \(listing.bookingCode)")
        content.sound = .default
        content.userInfo = [
            "type": "listing_reserved",
            "listing_id": remoteID,
            "listing_title": listing.title,
        ]

        let reservationID = listing.claimedByDeviceID ?? UUID().uuidString
        let request = UNNotificationRequest(
            identifier: "listing-reserved-\(remoteID)-\(reservationID)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private static func hasNotificationPermission(_ center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
}
