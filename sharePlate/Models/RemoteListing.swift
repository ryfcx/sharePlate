// remote listing

import Foundation

struct RemoteListing: Codable, Identifiable {
    let id: UUID
    let title: String
    let details: String
    let quantity: String
    let category: String
    let quantitySize: String
    let pickupType: String
    let area: String
    let photoURL: String?
    let pickupAddress: String
    let latitude: Double
    let longitude: Double
    let pickupDeadline: Date
    let pickupNotes: String?
    let contactInstructions: String?
    let status: String
    let createdAt: Date
    let postedBy: UUID
    let claimedBy: UUID?
    let reservedUntil: Date?
    let waitlistUserIDs: [UUID]
    let pantryGCFDLocationID: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, details, quantity, category, area, latitude, longitude, status
        case quantitySize = "quantity_size"
        case pickupType = "pickup_type"
        case photoURL = "photo_url"
        case pickupAddress = "pickup_address"
        case pickupDeadline = "pickup_deadline"
        case pickupNotes = "pickup_notes"
        case contactInstructions = "contact_instructions"
        case createdAt = "created_at"
        case postedBy = "posted_by"
        case claimedBy = "claimed_by"
        case reservedUntil = "reserved_until"
        case waitlistUserIDs = "waitlist_user_ids"
        case pantryGCFDLocationID = "pantry_gcfd_location_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
        quantity = try container.decode(String.self, forKey: .quantity)
        category = try container.decode(String.self, forKey: .category)
        quantitySize = try container.decode(String.self, forKey: .quantitySize)
        pickupType = try container.decode(String.self, forKey: .pickupType)
        area = try container.decodeIfPresent(String.self, forKey: .area) ?? ""
        photoURL = try container.decodeIfPresent(String.self, forKey: .photoURL)
        pickupAddress = try container.decode(String.self, forKey: .pickupAddress)
        latitude = try Self.decodeDouble(from: container, forKey: .latitude)
        longitude = try Self.decodeDouble(from: container, forKey: .longitude)
        pickupDeadline = try container.decode(Date.self, forKey: .pickupDeadline)
        pickupNotes = try container.decodeIfPresent(String.self, forKey: .pickupNotes)
        contactInstructions = try container.decodeIfPresent(String.self, forKey: .contactInstructions)
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        postedBy = try container.decode(UUID.self, forKey: .postedBy)
        claimedBy = try container.decodeIfPresent(UUID.self, forKey: .claimedBy)
        reservedUntil = try container.decodeIfPresent(Date.self, forKey: .reservedUntil)
        waitlistUserIDs = Self.decodeUUIDArray(from: container, forKey: .waitlistUserIDs)
        pantryGCFDLocationID = try container.decodeIfPresent(Int.self, forKey: .pantryGCFDLocationID)
    }

    private static func decodeDouble(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Double {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? container.decode(String.self, forKey: key), let parsed = Double(value) {
            return parsed
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected a number for \(key.rawValue)"
        )
    }

    private static func decodeUUIDArray(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [UUID] {
        if let ids = try? container.decode([UUID].self, forKey: key) {
            return ids
        }
        if let values = try? container.decode([String].self, forKey: key) {
            return values.compactMap(UUID.init(uuidString:))
        }
        if let raw = try? container.decode(String.self, forKey: key) {
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
            guard !trimmed.isEmpty else { return [] }
            return trimmed
                .split(separator: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
        return []
    }
}

struct RemoteListingInsert: Encodable {
    let id: UUID
    let title: String
    let details: String
    let quantity: String
    let category: String
    let quantitySize: String
    let pickupType: String
    let area: String
    let photoURL: String?
    let pickupAddress: String
    let latitude: Double
    let longitude: Double
    let pickupDeadline: Date
    let pickupNotes: String?
    let contactInstructions: String?
    let status: String
    let postedBy: UUID
    let pantryGCFDLocationID: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, details, quantity, category, area, latitude, longitude, status
        case quantitySize = "quantity_size"
        case pickupType = "pickup_type"
        case photoURL = "photo_url"
        case pickupAddress = "pickup_address"
        case pickupDeadline = "pickup_deadline"
        case pickupNotes = "pickup_notes"
        case contactInstructions = "contact_instructions"
        case postedBy = "posted_by"
        case pantryGCFDLocationID = "pantry_gcfd_location_id"
    }
}

struct RemoteListingUpdate: Encodable {
    let status: String?
    let photoURL: String?
    let claimedBy: UUID?
    let reservedUntil: Date?
    let waitlistUserIDs: [UUID]?
    let contactInstructions: String?
    let pickupDeadline: Date?
    let details: String?
    let quantity: String?

    enum CodingKeys: String, CodingKey {
        case status
        case photoURL = "photo_url"
        case claimedBy = "claimed_by"
        case reservedUntil = "reserved_until"
        case waitlistUserIDs = "waitlist_user_ids"
        case contactInstructions = "contact_instructions"
        case pickupDeadline = "pickup_deadline"
        case details
        case quantity
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(photoURL, forKey: .photoURL)
        try container.encodeIfPresent(claimedBy, forKey: .claimedBy)
        try container.encodeIfPresent(reservedUntil, forKey: .reservedUntil)
        try container.encodeIfPresent(waitlistUserIDs, forKey: .waitlistUserIDs)
        try container.encodeIfPresent(contactInstructions, forKey: .contactInstructions)
        try container.encodeIfPresent(pickupDeadline, forKey: .pickupDeadline)
        try container.encodeIfPresent(details, forKey: .details)
        try container.encodeIfPresent(quantity, forKey: .quantity)
    }
}
