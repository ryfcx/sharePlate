//
//  SupabasePhotoService.swift
//  sharePlate
//

import Foundation
import Supabase

enum SupabasePhotoService {
    private static let client = SupabaseManager.client
    static let bucket = "listing-photos"

    /// Uploads JPEG bytes and returns the storage path stored in `listings.photo_url`.
    static func upload(listingID: UUID, userID: UUID, data: Data) async throws -> String {
        let path = "\(userID.uuidString.lowercased())/\(listingID.uuidString.lowercased()).jpg"
        try await client.storage
            .from(bucket)
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        return path
    }

    /// Downloads using authenticated Storage API (works without a public bucket).
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
