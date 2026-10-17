// food resource

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
    // weekly hours saved as json
    var hoursData: Data?
    // per program hours saved as json
    var serviceHoursData: Data?
    // gcfd id for this spot, used for claims
    var gcfdLocationID: Int?

// pantry manager overlay
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

    // checks if it is open at this time
    func isOpen(at date: Date = Date()) -> Bool? {
        if isTemporarilyClosed { return false }
        if hours.lowercased().contains("24") { return true }
        let evaluable = openingIntervals.filter { !$0.everyOtherWeek }
        guard !evaluable.isEmpty else { return nil }
        return evaluable.contains { $0.contains(date) }
    }

    var isOpenNow: Bool? { isOpen() }

    // preserve the source schedule as imported
    static func importedSchedule(
        hours: String,
        intervals: [OpeningInterval],
        serviceHours: [ServiceHours]
    ) -> (hours: String, intervals: [OpeningInterval], serviceHours: [ServiceHours]) {
        (hours, intervals, serviceHours)
    }
}
