//
//  SupabaseDeviceTokenService.swift
//  sharePlate
//
//  Stores APNs device tokens for push delivery. Run `supabase/device_tokens.sql`
//  in the Supabase SQL editor before first use.
//

import Foundation
import Supabase

enum SupabaseDeviceTokenService {
    private static let client = SupabaseManager.client
    private static let table = "device_tokens"

    static func upsert(userID: UUID, token: String) async throws {
        let payload = DeviceTokenUpsert(
            userID: userID,
            token: token,
            platform: "ios"
        )
        try await client
            .from(table)
            .upsert(payload, onConflict: "user_id,token")
            .execute()
    }

    static func remove(userID: UUID, token: String) async {
        _ = try? await client
            .from(table)
            .delete()
            .eq("user_id", value: userID.uuidString)
            .eq("token", value: token)
            .execute()
    }
}

private struct DeviceTokenUpsert: Encodable {
    let userID: UUID
    let token: String
    let platform: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case token, platform
        case userID = "user_id"
        case updatedAt = "updated_at"
    }

    init(userID: UUID, token: String, platform: String) {
        self.userID = userID
        self.token = token
        self.platform = platform
        self.updatedAt = Date()
    }
}
