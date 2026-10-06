//
//  FoodResource.swift
//  sharePlate
//

import Foundation
import SwiftData
import CoreLocation

@Model
final class FoodResource {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var hours: String
    var phone: String?
    var summary: String
    var typeRaw: String
    /// JSON-encoded `[OpeningInterval]` describing the weekly opening hours.
    var hoursData: Data?
    /// JSON-encoded `[ServiceHours]` with per-program schedules and notes.
    var serviceHoursData: Data?
    /// GCFD's stable id for this location (nil for the curated fallback seed,
    /// which can't be claimed). Matches `PantryClaim.gcfdLocationID`.
    var gcfdLocationID: Int?

    /// Imported with "Open 24 Hours" so their pantry dots stay green.
    /// All three are in Lincoln Park.
    static let alwaysOpenLocationIDs: Set<Int> = [
        823,    // Harvest Hub Lincoln Park — 2145 N Halsted St
        20947,  // Care For Friends — 530 W Fullerton Pkwy
        820     // St. Teresa of Avila Parish — 1950 N Kenmore Ave
    ]

    // MARK: - Pantry-manager overlay
    // Denormalized from `PantryClaim` and reapplied after every dataset
    // resync (which wipes and reinserts this table) — see
    // `LocalDataStore.reapplyPantryClaimsToResources()`.
    var managedByUserID: String?
    var isTemporarilyClosed: Bool = false
    var pantryClosedNote: String?

    init(
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        hours: String,
        phone: String? = nil,
        summary: String,
        type: ResourceType,
        openingIntervals: [OpeningInterval] = [],
        serviceHours: [ServiceHours] = [],
        gcfdLocationID: Int? = nil
    ) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.hours = hours
        self.phone = phone
        self.summary = summary
        self.typeRaw = type.rawValue
        self.hoursData = openingIntervals.isEmpty ? nil : try? JSONEncoder().encode(openingIntervals)
        self.serviceHoursData = serviceHours.isEmpty ? nil : try? JSONEncoder().encode(serviceHours)
        self.gcfdLocationID = gcfdLocationID
    }

    var openingIntervals: [OpeningInterval] {
        guard let hoursData else { return serviceHours.flatMap(\.intervals) }
        return (try? JSONDecoder().decode([OpeningInterval].self, from: hoursData)) ?? serviceHours.flatMap(\.intervals)
    }

    var serviceHours: [ServiceHours] {
        guard let serviceHoursData else { return [] }
        return (try? JSONDecoder().decode([ServiceHours].self, from: serviceHoursData)) ?? []
    }

    var type: ResourceType {
        get { ResourceType(rawValue: typeRaw) ?? .pantry }
        set { typeRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Whether the resource is open at `date`.
    /// Uses the structured weekly schedule when available, falling back to a
    /// "24 hours" hint in the free-form `hours` string. Returns nil when the
    /// schedule is unknown (e.g. "call for hours").
    func isOpen(at date: Date = Date()) -> Bool? {
        if isTemporarilyClosed { return false }
        if hours.lowercased().contains("24") { return true }
        let evaluable = openingIntervals.filter { !$0.everyOtherWeek }
        guard !evaluable.isEmpty else { return nil }
        return evaluable.contains { $0.contains(date) }
    }

    var isOpenNow: Bool? { isOpen() }

    /// Schedule written on every import, including a later dataset refresh.
    /// Listed pantries always come back as Open 24 Hours so their status stays green.
    static func importedSchedule(
        locationID: Int,
        hours: String,
        intervals: [OpeningInterval],
        serviceHours: [ServiceHours]
    ) -> (hours: String, intervals: [OpeningInterval], serviceHours: [ServiceHours]) {
        guard alwaysOpenLocationIDs.contains(locationID) else {
            return (hours, intervals, serviceHours)
        }
        return ("Open 24 Hours", [], [])
    }
}
