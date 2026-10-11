//
// supabaserealtimejson.swift
// shareplate
//
// decoder for realtime payloads
// must match postgrest so dates do not drop live updates
//

import Foundation
import Supabase

enum SupabaseRealtimeJSON {
    static let decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder

    static func recordID(_ record: [String: AnyJSON]) -> UUID? {
        switch record["id"] {
        case .string(let value):
            return UUID(uuidString: value)
        default:
            return nil
        }
    }
}
