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
        serviceHours: [ServiceHours] = []
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
        if hours.lowercased().contains("24") { return true }
        let evaluable = openingIntervals.filter { !$0.everyOtherWeek }
        guard !evaluable.isEmpty else { return nil }
        return evaluable.contains { $0.contains(date) }
    }

    var isOpenNow: Bool? { isOpen() }
}
