//
//  RemoteListing.swift
//  sharePlate
//
//  Codable mirror of the Supabase `listings` table.
//

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
