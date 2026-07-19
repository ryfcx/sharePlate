//
//  SupabaseRealtimeJSON.swift
//  sharePlate
//

import Foundation

enum SupabaseRealtimeJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
