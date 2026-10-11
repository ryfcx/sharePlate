// reservation coordination

import Foundation
import CoreLocation

struct ReservationCoordination: Codable, Equatable {
    var meetupAddress: String = ""
    var handoffSpot: HandoffSpot?
    var timeslot: Date?
    var meetupLatitude: Double?
    var meetupLongitude: Double?
    var providerNote: String = ""
    // where to drop the food for dropoff posts
    var consumerDropOffAddress: String = ""
    var consumerDropOffLatitude: Double?
    var consumerDropOffLongitude: Double?
    // true means the picker can see the notes
    var instructionsPublished: Bool = false
    // packs claimed in this booking
    var reservedPackageCount: Int?

    var consumerDropOffCoordinate: CLLocationCoordinate2D? {
        guard let lat = consumerDropOffLatitude, let lon = consumerDropOffLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var consumerDropOffComplete: Bool {
        !consumerDropOffAddress.trimmingCharacters(in: .whitespaces).isEmpty && consumerDropOffCoordinate != nil
    }

    mutating func clearConsumerDropOff() {
        consumerDropOffAddress = ""
        consumerDropOffLatitude = nil
        consumerDropOffLongitude = nil
    }

    var hasMeetupPin: Bool {
        meetupLatitude != nil && meetupLongitude != nil
    }

    var meetupCoordinate: CLLocationCoordinate2D? {
        guard let lat = meetupLatitude, let lon = meetupLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var addressStepComplete: Bool {
        !meetupAddress.trimmingCharacters(in: .whitespaces).isEmpty || hasMeetupPin
    }

    var timeslotStepComplete: Bool { timeslot != nil }
    var handoffStepComplete: Bool { handoffSpot != nil }

    var providerSetupComplete: Bool {
        addressStepComplete && timeslotStepComplete && handoffStepComplete
    }

    var isReadyForConsumer: Bool {
        instructionsPublished && providerSetupComplete
    }

    // notes set when posting, seen after booking
    static func publishedAtPost(
        meetupAddress: String,
        handoffSpot: HandoffSpot,
        readyBy: ReservationTimeslot,
        providerNote: String = "",
        latitude: Double,
        longitude: Double
    ) -> ReservationCoordination {
        var coordination = ReservationCoordination()
        coordination.meetupAddress = meetupAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        coordination.handoffSpot = handoffSpot
        coordination.timeslot = readyBy.date()
        coordination.meetupLatitude = latitude
        coordination.meetupLongitude = longitude
        coordination.providerNote = providerNote.trimmingCharacters(in: .whitespacesAndNewlines)
        coordination.instructionsPublished = true
        return coordination
    }
}

enum ReservationCoordinationCodec {
    static func encode(_ coordination: ReservationCoordination) -> String? {
        guard coordination != ReservationCoordination() else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(coordination) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from contactInstructions: String?) -> ReservationCoordination {
        guard let contactInstructions,
              !contactInstructions.isEmpty,
              let data = contactInstructions.data(using: .utf8) else {
            return ReservationCoordination()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ReservationCoordination.self, from: data)) ?? ReservationCoordination()
    }
}
