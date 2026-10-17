// supabase listing service

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
        do {
            return try await client
                .from(table)
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
        } catch let error as PostgrestError {
            switch error.message {
            case "moderation_rate_limited": throw ContentSubmissionError.rateLimited
            case "moderation_content_too_large": throw ContentSubmissionError.contentTooLarge
            case "moderation_photo_required": throw ContentSubmissionError.photoRequired
            default: throw error
            }
        }
    }

    static func update(id: UUID, patch: RemoteListingUpdate) async throws {
// ask for rows back so we know the save worked
// without this a blocked save would still look fine
        let rows: [RemoteListing] = try await client
            .from(table)
            .update(patch)
            .eq("id", value: id.uuidString)
            .select()
            .execute()
            .value
        guard !rows.isEmpty else {
            throw SyncError.remoteUpdateFailed(
                String(localized: "This listing changed on the server — someone else may have claimed it.")
            )
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

    static func reserve(
        id: UUID,
        details: String,
        quantity: String,
        contactInstructions: String?,
        reservedUntil: Date,
        reserverName: String
    ) async throws {
        struct Params: Encodable {
            let p_listing_id: UUID
            let p_details: String
            let p_quantity: String
            let p_contact_instructions: String
            let p_reserved_until: Date
            let p_reserver_name: String
        }

        try await client
            .rpc("reserve_listing", params: Params(
                p_listing_id: id,
                p_details: details,
                p_quantity: quantity,
                p_contact_instructions: contactInstructions ?? "",
                p_reserved_until: reservedUntil,
                p_reserver_name: reserverName
            ))
            .execute()
    }

    // who booked it, only makers and bookers can see
    static func fetchReserverDisplayName(listingID: UUID) async -> String? {
        struct ReservationIdentity: Decodable {
            let reserverDisplayName: String

            enum CodingKeys: String, CodingKey {
                case reserverDisplayName = "reserver_display_name"
            }
        }

        do {
            let identity: ReservationIdentity = try await client
                .from("listing_reservations")
                .select("reserver_display_name")
                .eq("listing_id", value: listingID.uuidString)
                .single()
                .execute()
                .value
            return identity.reserverDisplayName
        } catch {
            return nil
        }
    }

    static func fetchCompletedListingIDs() async -> Set<UUID>? {
        struct Completion: Decodable {
            let listingID: UUID

            enum CodingKeys: String, CodingKey {
                case listingID = "listing_id"
            }
        }

        do {
            let rows: [Completion] = try await client
                .from("listing_completions")
                .select("listing_id")
                .execute()
                .value
            return Set(rows.map(\.listingID))
        } catch {
            return nil
        }
    }

    static func releaseReservation(
        id: UUID,
        details: String,
        quantity: String,
        contactInstructions: String?,
        waitlistUserIDs: [UUID]
    ) async throws {
        struct Params: Encodable {
            let p_listing_id: UUID
            let p_details: String
            let p_quantity: String
            let p_contact_instructions: String
            let p_waitlist_user_ids: [UUID]
        }

        try await client
            .rpc("release_listing_reservation", params: Params(
                p_listing_id: id,
                p_details: details,
                p_quantity: quantity,
                p_contact_instructions: contactInstructions ?? "",
                p_waitlist_user_ids: waitlistUserIDs
            ))
            .execute()
    }

    static func markHandoffComplete(id: UUID, pickupDeadline: Date) async throws {
        struct Params: Encodable {
            let p_listing_id: UUID
        }

        try await client
            .rpc("complete_listing_handoff", params: Params(p_listing_id: id))
            .execute()
    }

    // reopens a post when packs are left
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
