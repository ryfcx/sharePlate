//
//  MapFilterOption.swift
//  sharePlate
//
//  Grouped map filters: Pantry, Donor, and Store each have sub-options.
//

import SwiftUI

enum MapFilterCategory: String, CaseIterable, Identifiable {
    case pantry
    case donor
    case store

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pantry: return "Pantry"
        case .donor: return "Donor"
        case .store: return "Store"
        }
    }

    var options: [MapFilterOption] {
        switch self {
        case .pantry: return [.pantryFood, .pantryDry]
        case .donor: return [.donorDropOff, .donorPickup]
        case .store: return [.storeGrocery, .storeRestaurant]
        }
    }
}

enum MapFilterOption: String, CaseIterable, Identifiable {
    case pantryFood
    case pantryDry
    case donorDropOff
    case donorPickup
    case storeGrocery
    case storeRestaurant

    var id: String { rawValue }

    var category: MapFilterCategory {
        switch self {
        case .pantryFood, .pantryDry: return .pantry
        case .donorDropOff, .donorPickup: return .donor
        case .storeGrocery, .storeRestaurant: return .store
        }
    }

    var displayName: String {
        switch self {
        case .pantryFood: return "Food"
        case .pantryDry: return "Dry"
        case .donorDropOff: return "Drop off"
        case .donorPickup: return "Pickup"
        case .storeGrocery: return "Grocery"
        case .storeRestaurant: return "Restaurant"
        }
    }

    var systemImage: String {
        switch self {
        case .pantryFood: return "carrot.fill"
        case .pantryDry: return "shippingbox.fill"
        case .donorDropOff: return "arrow.down.to.line"
        case .donorPickup: return "hand.wave.fill"
        case .storeGrocery: return "cart.fill"
        case .storeRestaurant: return "fork.knife"
        }
    }

    var tint: Color {
        switch category {
        case .pantry: return Theme.Palette.pantryGreen
        case .donor: return Theme.Palette.availableOrange
        case .store: return Theme.Palette.mealBlue
        }
    }
}

// MARK: - Filter engine

/// Shared map filter rules so resources and listings stay consistent.
enum MapFilterLogic {
    static func pantryFilters(in selected: Set<MapFilterOption>) -> Set<MapFilterOption> {
        selected.filter { $0.category == .pantry }
    }

    static func donorFilters(in selected: Set<MapFilterOption>) -> Set<MapFilterOption> {
        selected.filter { $0.category == .donor }
    }

    static func storeFilters(in selected: Set<MapFilterOption>) -> Set<MapFilterOption> {
        selected.filter { $0.category == .store }
    }

    /// GCFD resources — only shown when pantry filters are active (or nothing is selected).
    static func includesResources(selected: Set<MapFilterOption>) -> Bool {
        selected.isEmpty || !pantryFilters(in: selected).isEmpty
    }

    /// Neighbor listings — shown when donor/store filters are active (or nothing is selected).
    static func includesListings(selected: Set<MapFilterOption>) -> Bool {
        selected.isEmpty || !donorFilters(in: selected).isEmpty || !storeFilters(in: selected).isEmpty
    }

    static func openNowApplies(showOpenOnly: Bool, showAllLocations: Bool) -> Bool {
        showOpenOnly && !showAllLocations
    }
}

// MARK: - Matching

extension FoodResource {
    func matches(_ filters: Set<MapFilterOption>) -> Bool {
        guard MapFilterLogic.includesResources(selected: filters) else { return false }
        let pantry = MapFilterLogic.pantryFilters(in: filters)
        guard !pantry.isEmpty else { return true }
        return matchesPantryFilters(pantry)
    }

    func matchesPantryFilters(_ pantry: Set<MapFilterOption>) -> Bool {
        pantry.contains { option in
            switch option {
            case .pantryFood: return matchesPantryFood
            case .pantryDry: return matchesPantryDry
            default: return false
            }
        }
    }

    var matchesPantryFood: Bool {
        switch type {
        case .mealProgram, .mobileDistribution, .communityFridge:
            return true
        case .pantry:
            return !matchesPantryDryOnly
        }
    }

    var matchesPantryDry: Bool {
        type == .pantry
    }

    /// Pantry whose summary explicitly indicates shelf-stable / dry goods only.
    private var matchesPantryDryOnly: Bool {
        guard type == .pantry else { return false }
        let text = summary.lowercased()
        let drySignals = text.contains("shelf")
            || text.contains(" dry")
            || text.contains("dry ")
            || text.contains("non-perishable")
            || text.contains("non perishable")
        let freshSignals = text.contains("produce")
            || text.contains("fruit")
            || text.contains("vegetable")
            || text.contains("meat")
            || text.contains("dairy")
            || text.contains("prepared")
            || text.contains("meal")
            || text.contains("perishable")
            || text.contains("grab and go")
        return drySignals && !freshSignals
    }
}

extension FoodListing {
    func matches(_ filters: Set<MapFilterOption>) -> Bool {
        guard MapFilterLogic.includesListings(selected: filters) else { return false }
        let donor = MapFilterLogic.donorFilters(in: filters)
        let store = MapFilterLogic.storeFilters(in: filters)
        if donor.isEmpty && store.isEmpty { return true }

        var matched = false
        if !donor.isEmpty {
            matched = donor.contains { option in
                switch option {
                case .donorDropOff: return pickupType == .communityFridge
                case .donorPickup: return pickupType != .communityFridge
                default: return false
                }
            }
        }
        if !store.isEmpty {
            matched = matched || store.contains { option in
                switch option {
                case .storeGrocery:
                    return [.produce, .pantry, .bakery, .drinks, .mixed].contains(category)
                case .storeRestaurant:
                    return category == .preparedMeals
                default: return false
                }
            }
        }
        return matched
    }
}
