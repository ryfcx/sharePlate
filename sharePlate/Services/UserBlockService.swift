import Foundation
import Supabase

nonisolated struct BlockedUser: Codable, Identifiable, Equatable {
    let blockedID: UUID
    let displayName: String
    let createdAt: Date

    var id: UUID { blockedID }

    enum CodingKeys: String, CodingKey {
        case blockedID = "blocked_id"
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

enum UserBlockService {
    static func fetch() async throws -> [BlockedUser] {
        try await SupabaseManager.client.from("user_blocks")
            .select("blocked_id, display_name, created_at")
            .order("created_at", ascending: false)
            .execute().value
    }

    static func block(_ target: UUID, name: String, owner: UUID) async throws -> BlockedUser {
        struct Payload: Encodable {
            let blocker_id: UUID
            let blocked_id: UUID
            let display_name: String
        }
        return try await SupabaseManager.client.from("user_blocks")
            .upsert(Payload(blocker_id: owner, blocked_id: target, display_name: name),
                    onConflict: "blocker_id,blocked_id")
            .select("blocked_id, display_name, created_at")
            .single().execute().value
    }

    static func unblock(_ target: UUID, owner: UUID) async throws {
        try await SupabaseManager.client.from("user_blocks")
            .delete().eq("blocker_id", value: owner.uuidString)
            .eq("blocked_id", value: target.uuidString).execute()
    }
}
