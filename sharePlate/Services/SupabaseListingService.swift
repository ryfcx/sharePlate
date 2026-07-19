//
//  SupabaseListingService.swift
//  sharePlate
//

import Foundation
import Supabase

enum SupabaseListingService {
    private static let client = SupabaseManager.client
    private static let table = "listings"

    static func fetch(id: UUID) async throws -> RemoteListing {
        try await client
            .from(table)
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    static func fetchActive() async throws -> [RemoteListing] {
        let now = ISO8601DateFormatter().string(from: Date())
        return try await client
            .from(table)
            .select()
            .gt("pickup_deadline", value: now)
            .neq("status", value: ListingStatus.pickedUp.rawValue)
            .neq("status", value: "picked_up")
            .neq("status", value: "collected")
            .neq("status", value: ListingStatus.expired.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func create(_ payload: RemoteListingInsert) async throws -> RemoteListing {
        try await client
            .from(table)
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    static func update(id: UUID, patch: RemoteListingUpdate) async throws {
        // `.select()` forces PostgREST to return the rows it actually updated.
        // Without it, an update blocked by RLS (e.g. someone else already claimed
        // this listing) still returns 200 with zero rows changed — the caller
        // would otherwise treat that as success.
        let rows: [RemoteListing] = try await client
            .from(table)
            .update(patch)
            .eq("id", value: id.uuidString)
            .select()
            .execute()
            .value
        guard !rows.isEmpty else {
            throw SyncError.remoteUpdateFailed("This listing changed on the server — someone else may have claimed it.")
        }
    }

    static func updatePhotoURL(id: UUID, photoURL: String) async throws {
        try await update(id: id, patch: RemoteListingUpdate(
            status: nil,
            photoURL: photoURL,
            claimedBy: nil,
            reservedUntil: nil,
            waitlistUserIDs: nil,
            contactInstructions: nil,
            pickupDeadline: nil,
            details: nil,
            quantity: nil
        ))
    }

    static func markHandoffComplete(id: UUID, pickupDeadline: Date) async throws {
        struct Params: Encodable {
            let p_listing_id: UUID
        }

        try await client
            .rpc("complete_listing_handoff", params: Params(p_listing_id: id))
            .execute()
    }

    /// Reopens a listing when packages remain after a partial handoff.
    static func reopenAfterPartialHandoff(
        id: UUID,
        details: String,
        contactInstructions: String?,
        quantity: String,
        pickupDeadline: Date
    ) async throws {
        struct Params: Encodable {
            let p_listing_id: UUID
            let p_details: String
            let p_quantity: String
            let p_contact_instructions: String?
            let p_pickup_deadline: Date
        }

        let params = Params(
            p_listing_id: id,
            p_details: details,
            p_quantity: quantity,
            p_contact_instructions: contactInstructions,
            p_pickup_deadline: pickupDeadline
        )

        try await client
            .rpc("reopen_listing_after_partial_handoff", params: params)
            .execute()
    }

    static func delete(id: UUID) async throws {
        try await client
            .from(table)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}
