//
//  SupabasePantryClaimService.swift
//  sharePlate
//

import Foundation
import Supabase

enum SupabasePantryClaimService {
    private static let client = SupabaseManager.client
    private static let table = "pantry_claims"

    static func fetchAll() async throws -> [RemotePantryClaim] {
        try await client
            .from(table)
            .select()
            .execute()
            .value
    }

    /// Fails (via the table's primary key on `gcfd_location_id`) if someone
    /// already claimed this pantry — first come, first served.
    static func claim(_ payload: RemotePantryClaimInsert) async throws -> RemotePantryClaim {
        try await client
            .from(table)
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    static func updateStatus(gcfdLocationID: Int, patch: RemotePantryClaimUpdate) async throws {
        try await client
            .from(table)
            .update(patch)
            .eq("gcfd_location_id", value: gcfdLocationID)
            .execute()
    }

    static func release(gcfdLocationID: Int) async throws {
        try await client
            .from(table)
            .delete()
            .eq("gcfd_location_id", value: gcfdLocationID)
            .execute()
    }
}
