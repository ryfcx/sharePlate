//
//  Enums.swift
//  sharePlate
//

import SwiftUI

enum ResourceType: String, Codable, CaseIterable, Identifiable {
    case pantry
    case mealProgram
    case communityFridge
    case mobileDistribution

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pantry: return String(localized: "Food Pantry")
        case .mealProgram: return String(localized: "Meal Program")
        case .communityFridge: return String(localized: "Community Fridge")
        case .mobileDistribution: return String(localized: "Mobile Distribution")
        }
    }

    var shortName: String {
        switch self {
        case .pantry: return String(localized: "Pantry")
        case .mealProgram: return String(localized: "Meal Program")
        case .communityFridge: return String(localized: "Fridge")
        case .mobileDistribution: return String(localized: "Mobile")
        }
    }

    var symbol: String {
        switch self {
        case .pantry: return "bag.fill"
        case .mealProgram: return "fork.knife"
        case .communityFridge: return "refrigerator.fill"
        case .mobileDistribution: return "bus.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pantry: return Theme.Palette.pantryGreen
        case .mealProgram: return Theme.Palette.mealBlue
        case .communityFridge: return Theme.Palette.fridgePurple
        case .mobileDistribution: return Theme.Palette.mobileTeal
        }
    }
}

enum ListingStatus: String, Codable, CaseIterable, Identifiable {
    case available
    case reserved
    case readyForPickup
    case pickedUp
    case expired

    var id: String { rawValue }

    /// Maps a stored raw value to a status, tolerating legacy and snake_case values.
    static func from(raw: String) -> ListingStatus {
        if let value = ListingStatus(rawValue: raw) { return value }
        switch raw {
        case "collected", "picked_up": return .pickedUp
        case "ready_for_pickup": return .readyForPickup
        default: break
        }
        return .available
    }

    /// Listings with these statuses should not appear in the public browse catalog.
    static func isPubliclyVisible(_ status: ListingStatus) -> Bool {
        status == .available || status == .reserved || status == .readyForPickup
    }

    var isPubliclyVisible: Bool { Self.isPubliclyVisible(self) }

    /// Value stored in Supabase (snake_case where needed).
    var supabaseRaw: String {
        switch self {
        case .pickedUp: return "picked_up"
        case .readyForPickup: return "ready_for_pickup"
        default: return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .available: return String(localized: "Available")
        case .reserved: return String(localized: "Reserved")
        case .readyForPickup: return String(localized: "Ready for Pickup")
        case .pickedUp: return String(localized: "Picked Up")
        case .expired: return String(localized: "Expired")
        }
    }

    var tint: Color {
        switch self {
        case .available: return Theme.Palette.primaryGreen
        case .reserved: return Theme.Palette.accentOrange
        case .readyForPickup: return Theme.Palette.mealBlue
        case .pickedUp: return Theme.Palette.mutedText
        case .expired: return Theme.Palette.urgentRed
        }
    }
}

enum FoodCategory: String, Codable, CaseIterable, Identifiable {
    case preparedMeals
    case produce
    case bakery
    case pantry
    case drinks
    case mixed
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .preparedMeals: return String(localized: "Prepared Meals")
        case .produce: return String(localized: "Produce")
        case .bakery: return String(localized: "Bakery")
        case .pantry: return String(localized: "Pantry Items")
        case .drinks: return String(localized: "Drinks")
        case .mixed: return String(localized: "Mixed Food")
        case .other: return String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .preparedMeals: return "fork.knife"
        case .produce: return "carrot.fill"
        case .bakery: return "birthday.cake.fill"
        case .pantry: return "shippingbox.fill"
        case .drinks: return "cup.and.saucer.fill"
        case .mixed: return "takeoutbag.and.cup.and.straw.fill"
        case .other: return "ellipsis.circle"
        }
    }
}

enum QuantitySize: String, Codable, CaseIterable, Identifiable {
    case feeds1to2
    case feeds3to5
    case feeds10plus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .feeds1to2: return String(localized: "Feeds 1–2")
        case .feeds3to5: return String(localized: "Feeds 3–5")
        case .feeds10plus: return String(localized: "Feeds 10+")
        }
    }

    var shortName: String {
        switch self {
        case .feeds1to2: return String(localized: "Small")
        case .feeds3to5: return String(localized: "Medium")
        case .feeds10plus: return String(localized: "Large")
        }
    }

    /// Small portions are flagged as limited quantity (yellow indicator).
    var isLimited: Bool { self == .feeds1to2 }

    /// Rough package count shown on the active reservation screen.
    var packageCount: Int {
        switch self {
        case .feeds1to2: return 1
        case .feeds3to5: return 2
        case .feeds10plus: return 4
        }
    }

    var packagesLabel: String {
        let count = packageCount
        return count == 1 ? String(localized: "1 pack") : String(localized: "\(count) packs")
    }

    /// Wireframe-style quantity, e.g. `2x`.
    var packagesShortLabel: String {
        "\(packageCount)x"
    }

    static func from(packageCount: Int) -> QuantitySize {
        switch packageCount {
        case ...1: return .feeds1to2
        case 2...3: return .feeds3to5
        default: return .feeds10plus
        }
    }
}

enum PackageCountOption: Int, CaseIterable, Identifiable {
    case one = 1, two, three, four, five, six, seven, eight

    var id: Int { rawValue }

    static var postOptions: [PackageCountOption] { allCases }
}

enum HandoffSpot: String, CaseIterable, Identifiable, Codable {
    case curb
    case home
    case outside

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .curb: return String(localized: "Curb")
        case .home: return String(localized: "Home")
        case .outside: return String(localized: "Outside")
        }
    }

    var symbol: String {
        switch self {
        case .curb: return "car.fill"
        case .home: return "house.fill"
        case .outside: return "tree.fill"
        }
    }

    func displayName(isDropOff: Bool) -> String {
        guard isDropOff else { return displayName }
        switch self {
        case .curb: return String(localized: "Curbside")
        case .home: return String(localized: "At their door")
        case .outside: return String(localized: "Meet outside")
        }
    }
}

enum ReservationTimeslot: String, CaseIterable, Identifiable, Codable {
    case now
    case in15Minutes
    case in30Minutes
    case in1Hour

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .now: return String(localized: "Now")
        case .in15Minutes: return String(localized: "In 15 min")
        case .in30Minutes: return String(localized: "In 30 min")
        case .in1Hour: return String(localized: "In 1 hour")
        }
    }

    func date(from now: Date = Date()) -> Date {
        switch self {
        case .now: return now
        case .in15Minutes: return now.addingTimeInterval(15 * 60)
        case .in30Minutes: return now.addingTimeInterval(30 * 60)
        case .in1Hour: return now.addingTimeInterval(60 * 60)
        }
    }

    static func nearest(to date: Date, from now: Date = Date()) -> ReservationTimeslot? {
        allCases.min { abs($0.date(from: now).timeIntervalSince(date)) < abs($1.date(from: now).timeIntervalSince(date)) }
    }
}

/// How someone gets shared food from a neighbor listing.
enum DonorHandoffMode: String, CaseIterable, Identifiable {
    case pickup
    case dropOff

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pickup: return String(localized: "Pickup")
        case .dropOff: return String(localized: "Drop off")
        }
    }

    var symbol: String {
        switch self {
        case .pickup: return "hand.wave.fill"
        case .dropOff: return "arrow.down.to.line"
        }
    }

    var pickupType: PickupType {
        switch self {
        case .pickup: return .meetOutside
        case .dropOff: return .communityFridge
        }
    }
}

enum DropOffRadius: String, CaseIterable, Identifiable {
    case oneMile
    case threeMiles
    case fiveMiles
    case tenMiles

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneMile: return String(localized: "1 mi")
        case .threeMiles: return String(localized: "3 mi")
        case .fiveMiles: return String(localized: "5 mi")
        case .tenMiles: return String(localized: "10 mi")
        }
    }

    var meters: Double {
        switch self {
        case .oneMile: return 1_609
        case .threeMiles: return 1_609 * 3
        case .fiveMiles: return 1_609 * 5
        case .tenMiles: return 1_609 * 10
        }
    }

    static func nearest(to meters: Double) -> DropOffRadius? {
        allCases.min(by: { abs($0.meters - meters) < abs($1.meters - meters) })
    }
}

enum PickupType: String, Codable, CaseIterable, Identifiable {
    case porch
    case lobby
    case meetOutside
    case frontDesk
    case communityFridge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .porch: return String(localized: "Porch pickup")
        case .lobby: return String(localized: "Lobby pickup")
        case .meetOutside: return String(localized: "Meet outside")
        case .frontDesk: return String(localized: "Front desk pickup")
        case .communityFridge: return String(localized: "Drop off")
        }
    }

    var symbol: String {
        switch self {
        case .porch: return "house.fill"
        case .lobby: return "building.2.fill"
        case .meetOutside: return "figure.wave"
        case .frontDesk: return "bell.fill"
        case .communityFridge: return "refrigerator.fill"
        }
    }
}

/// Quick deadline presets for frictionless posting.
enum DeadlinePreset: String, CaseIterable, Identifiable {
    case thirtyMin
    case oneHour
    case tonight
    case tomorrowMorning

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thirtyMin: return String(localized: "30 min")
        case .oneHour: return String(localized: "1 hour")
        case .tonight: return String(localized: "Tonight")
        case .tomorrowMorning: return String(localized: "Tomorrow AM")
        }
    }

    func date(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .thirtyMin:
            return now.addingTimeInterval(30 * 60)
        case .oneHour:
            return now.addingTimeInterval(60 * 60)
        case .tonight:
            let eight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(3 * 3600)
            return eight > now ? eight : now.addingTimeInterval(3 * 3600)
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? now.addingTimeInterval(18 * 3600)
        }
    }
}

enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case spam
    case fake
    case unsafeFood
    case inappropriate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spam: return String(localized: "Spam")
        case .fake: return String(localized: "Fake Listing")
        case .unsafeFood: return String(localized: "Unsafe Food")
        case .inappropriate: return String(localized: "Inappropriate Content")
        }
    }
}
