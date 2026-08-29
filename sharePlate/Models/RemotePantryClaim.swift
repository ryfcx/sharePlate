//
//  RemotePantryClaim.swift
//  sharePlate
//
//  Codable mirror of the Supabase `pantry_claims` table.
//

import Foundation

struct RemotePantryClaim: Codable, Identifiable {
    var id: Int { gcfdLocationID }
    let gcfdLocationID: Int
    let pantryName: String
    let claimedBy: UUID
    let claimedAt: Date
    let isTemporarilyClosed: Bool
    let closedNote: String?

    enum CodingKeys: String, CodingKey {
        case gcfdLocationID = "gcfd_location_id"
        case pantryName = "pantry_name"
        case claimedBy = "claimed_by"
        case claimedAt = "claimed_at"
        case isTemporarilyClosed = "is_temporarily_closed"
        case closedNote = "closed_note"
    }
}

struct RemotePantryClaimInsert: Encodable {
    let gcfdLocationID: Int
    let pantryName: String
    let claimedBy: UUID

    enum CodingKeys: String, CodingKey {
        case gcfdLocationID = "gcfd_location_id"
        case pantryName = "pantry_name"
        case claimedBy = "claimed_by"
    }
}

struct RemotePantryClaimUpdate: Encodable {
    let isTemporarilyClosed: Bool
    let closedNote: String?

    enum CodingKeys: String, CodingKey {
        case isTemporarilyClosed = "is_temporarily_closed"
        case closedNote = "closed_note"
    }
}
