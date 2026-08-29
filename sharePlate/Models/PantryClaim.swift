//
//  PantryClaim.swift
//  sharePlate
//
//  A pantry manager's claim on a GCFD directory entry — lets them post
//  surplus listings under that pantry's name and mark it temporarily
//  closed. Synced from the `pantry_claims` Supabase table; see
//  RemotePantryClaim and SupabasePantryClaimService.
//

import Foundation
import SwiftData

@Model
final class PantryClaim {
    @Attribute(.unique) var gcfdLocationID: Int
    var pantryName: String
    var claimedByUserID: String
    var claimedAt: Date
    var isTemporarilyClosed: Bool
    var closedNote: String?

    init(
        gcfdLocationID: Int,
        pantryName: String,
        claimedByUserID: String,
        claimedAt: Date = Date(),
        isTemporarilyClosed: Bool = false,
        closedNote: String? = nil
    ) {
        self.gcfdLocationID = gcfdLocationID
        self.pantryName = pantryName
        self.claimedByUserID = claimedByUserID
        self.claimedAt = claimedAt
        self.isTemporarilyClosed = isTemporarilyClosed
        self.closedNote = closedNote
    }
}
