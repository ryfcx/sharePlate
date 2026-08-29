//
//  MapPlaceOpenStatus.swift
//  sharePlate
//
//  Wireframe Screen A — green / orange / red map pin states.
//

import SwiftUI

enum MapTimeWindow: String, CaseIterable, Identifiable {
    case near
    case today
    case tomorrow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .near: return String(localized: "Near")
        case .today: return String(localized: "Today")
        case .tomorrow: return String(localized: "Tomorrow")
        }
    }

    var systemImage: String {
        switch self {
        case .near: return "location.fill"
        case .today: return "sun.max.fill"
        case .tomorrow: return "sunrise.fill"
        }
    }
}

enum MapPlaceOpenStatus: Hashable {
    case open
    case closingSoon
    case closed

    var pinColor: Color {
        switch self {
        case .open: return Theme.Palette.primaryGreen
        case .closingSoon: return Theme.Palette.accentOrange
        case .closed: return Theme.Palette.urgentRed
        }
    }

    var legendLabel: String {
        switch self {
        case .open: return String(localized: "Open")
        case .closingSoon: return String(localized: "Closing soon")
        case .closed: return String(localized: "Closed")
        }
    }
}

enum MapBrowseLogic {
    static let closingSoonThreshold: TimeInterval = 60 * 60

    static func listingMatchesWindow(_ listing: FoodListing, window: MapTimeWindow, now: Date = Date()) -> Bool {
        guard listing.effectiveStatus == .available, !listing.isExpired else { return false }
        let calendar = Calendar.current
        switch window {
        case .near:
            return listing.pickupDeadline > now
        case .today:
            return calendar.isDateInToday(listing.pickupDeadline) && listing.pickupDeadline > now
        case .tomorrow:
            return calendar.isDateInTomorrow(listing.pickupDeadline)
        }
    }

    static func resourceMatches(_ resource: FoodResource, window: MapTimeWindow, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        switch window {
        case .near, .today:
            return resource.hasScheduledHours(on: now)
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
            return resource.hasScheduledHours(on: tomorrow)
        }
    }

    static func appliesNearRadius(_ window: MapTimeWindow) -> Bool {
        window == .near
    }
}

extension FoodResource {
    func hasScheduledHours(on date: Date, calendar: Calendar = .current) -> Bool {
        if hours.lowercased().contains("24") { return true }
        let evaluable = openingIntervals.filter { !$0.everyOtherWeek }
        guard !evaluable.isEmpty else { return false }
        let weekday = calendar.component(.weekday, from: date)
        let week = calendar.component(.weekOfMonth, from: date)
        return evaluable.contains { interval in
            guard interval.weekday == weekday else { return false }
            if !interval.weeksOfMonth.isEmpty {
                return interval.weeksOfMonth.contains(week)
            }
            return true
        }
    }

    func openStatus(at date: Date = Date(), calendar: Calendar = .current) -> MapPlaceOpenStatus {
        if isTemporarilyClosed { return .closed }
        if hours.lowercased().contains("24") { return .open }

        let evaluable = openingIntervals.filter { !$0.everyOtherWeek }
        guard !evaluable.isEmpty else { return .closed }

        if evaluable.contains(where: { $0.contains(date, calendar: calendar) }) {
            if let minutesLeft = minutesUntilCurrentWindowCloses(at: date, calendar: calendar),
               minutesLeft <= Int(MapBrowseLogic.closingSoonThreshold / 60) {
                return .closingSoon
            }
            return .open
        }

        return .closed
    }

    /// Preview status for a future day (e.g. Tomorrow tab) — open if hours exist that day.
    func openStatusPreview(on date: Date, calendar: Calendar = .current) -> MapPlaceOpenStatus {
        if isTemporarilyClosed { return .closed }
        if hours.lowercased().contains("24") { return .open }
        return hasScheduledHours(on: date, calendar: calendar) ? .open : .closed
    }

    private func minutesUntilCurrentWindowCloses(at date: Date, calendar: Calendar) -> Int? {
        let weekday = calendar.component(.weekday, from: date)
        let minutesNow = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        guard let interval = openingIntervals.first(where: {
            !$0.everyOtherWeek && $0.weekday == weekday && minutesNow >= $0.startMinutes && minutesNow < $0.endMinutes
        }) else { return nil }
        return interval.endMinutes - minutesNow
    }
}

extension FoodListing {
    var isClosingSoon: Bool {
        guard !isExpired else { return false }
        let remaining = pickupDeadline.timeIntervalSinceNow
        return remaining > 0 && remaining <= MapBrowseLogic.closingSoonThreshold
    }

    var mapOpenStatus: MapPlaceOpenStatus {
        if isExpired || pickupDeadline <= Date() { return .closed }
        if isClosingSoon { return .closingSoon }
        return .open
    }
}
