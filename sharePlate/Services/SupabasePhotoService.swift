//
// supabasephotoservice.swift
// shareplate
//

import Foundation
import Supabase

enum SupabasePhotoService {
    private static let client = SupabaseManager.client
    static let bucket = "listing-photos"

    // uploads jpeg bytes and returns storage path for listings photo url
    static func upload(listingID: UUID, userID: UUID, data: Data) async throws -> String {
        let path = "\(userID.uuidString.lowercased())/\(listingID.uuidString.lowercased()).jpg"
        try await client.storage
            .from(bucket)
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
        return path
    }

    static func removeUnattachedPhoto(path: String) async {
        _ = try? await client.storage.from(bucket).remove(paths: [path])
    }

    // downloads with authenticated storage api, works without public bucket
    static func download(storedValue: String) async throws -> Data {
        let path = storagePath(from: storedValue)
        return try await client.storage.from(bucket).download(path: path)
    }

    static func storagePath(from storedValue: String) -> String {
        let marker = "/storage/v1/object/"
        guard let range = storedValue.range(of: marker) else { return storedValue }
        var remainder = String(storedValue[range.upperBound...])
        for prefix in ["public/\(bucket)/", "authenticated/\(bucket)/", "\(bucket)/"] {
            if remainder.hasPrefix(prefix) {
                remainder = String(remainder.dropFirst(prefix.count))
                break
            }
        }
        return remainder
    }
}
