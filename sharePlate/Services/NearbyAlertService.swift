//
//  NearbyAlertService.swift
//  sharePlate
//
//  Local notifications for "something opened up nearby" — a pantry's
//  scheduled opening, or a new food/pantry-surplus listing. These are
//  on-device UNUserNotificationCenter requests, not server push: the app
//  ships without APNs entitlements (see PushNotificationConfiguration),
//  since free Apple Developer teams can't use push. Calendar-triggered
//  local notifications still fire even with the app fully closed; the
//  new-listing check only fires while the app is running (foreground, or
//  briefly after backgrounding/on a background location wake).
//

import Foundation
import CoreLocation
import UserNotifications

@MainActor
enum NearbyAlertService {
    /// Matches HomeMapView's "near" radius so alerts line up with what the
    /// Nearby panel would already show.
    static let nearRadiusMeters: CLLocationDistance = 8046

    private static let pantryNotificationPrefix = "pantry-open-"
    private static let notifiedListingIDsKey = "nearbyAlert.notifiedListingIDs"
    private static let maxNotifiedListingIDs = 200
    private static let maxScheduledPantries = 15

    // MARK: - Pantry opening schedule

    /// Reschedules "this pantry just opened" local notifications for the
    /// closest open (non-claimed-closed) pantries. Safe to call often —
    /// it always clears its own prior requests first.
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
            content.title = "Opening nearby"
            content.body = "\(resource.name) opens at \(timeString(fromMinutes: interval.startMinutes))"
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

    /// The first weekly (non-monthly, non-biweekly) opening interval for a
    /// resource — used as its single representative "opens at" alert so
    /// scheduled notifications stay well under iOS's 64-pending-request cap.
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

    // MARK: - New nearby listings

    /// Checks listings created since the last check for ones nearby and not
    /// posted by this device, firing an immediate local notification for
    /// each. Call whenever the local listing catalog changes (Realtime
    /// insert/update or a periodic sync) while the app is running.
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
            guard listing.effectiveStatus == .available else { continue }
            guard let remoteID = listing.remoteID, !notifiedIDs.contains(remoteID) else { continue }
            guard listing.postedByDeviceID.caseInsensitiveCompare(excludingDeviceID) != .orderedSame else { continue }

            let distance = userLocation.distance(from: CLLocation(latitude: listing.latitude, longitude: listing.longitude))
            guard distance <= nearRadiusMeters else { continue }

            let content = UNMutableNotificationContent()
            content.title = listing.isPantryListing ? "New pantry food nearby" : "New food posted nearby"
            content.body = "\(listing.title) · \(listing.areaLabel)"
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

    // MARK: - Posting confirmation

    /// Fires an immediate local notification confirming a provider's own
    /// listing went live, with its reference number for easy lookup.
    static func notifyListingPosted(_ listing: FoodListing) async {
        let center = UNUserNotificationCenter.current()
        guard await hasNotificationPermission(center) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Listing posted"
        content.body = "\(listing.title) is live — Listing \(listing.listingNumber)"
        content.sound = .default
        content.userInfo = ["type": "listing_posted", "listing_id": listing.remoteID ?? ""]

        let request = UNNotificationRequest(
            identifier: "listing-posted-\(listing.remoteID ?? UUID().uuidString)",
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
