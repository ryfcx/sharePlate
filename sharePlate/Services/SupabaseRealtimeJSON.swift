//
//  SupabaseRealtimeJSON.swift
//  sharePlate
//
//  Decoder for postgres_changes payloads. Must match PostgREST so fractional
//  timestamps and other Supabase date formats don't silently drop live updates.
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
