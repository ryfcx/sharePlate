//
//  GCFDDatabaseSyncService.swift
//  sharePlate
//
//  Checks Supabase Storage for a fresher GCFD food-locations database than
//  the one bundled with the app (refreshed daily by foodAPI/gcfd_food_sync.py
//  via GitHub Actions) and downloads it into Application Support so installed
//  apps pick up new pantry data without an App Store update. Read side is
//  GCFDDatabase.activeDatabaseURL, which already prefers a downloaded copy.
//

import Foundation
import SQLite3

enum GCFDDatabaseSyncService {
    private static let remoteURL = URL(
        string: "\(SupabaseConfig.projectURL.absoluteString)/storage/v1/object/public/app-data/gcfd_food.db"
    )!
    private static let etagDefaultsKey = "gcfdRemoteDatabaseETag"

    private static var destinationURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appending(path: "gcfd_food.db")
    }

    /// Checks for a newer database and downloads it if one exists. Cheap to
    /// call on every launch — it's a HEAD request unless the data changed.
    /// Returns true when a new database was installed and the caller should
    /// re-run `seedIfNeeded()` to import it.
    static func refreshIfNeeded() async -> Bool {
        guard let remoteETag = await fetchRemoteETag() else { return false }
        let knownETag = UserDefaults.standard.string(forKey: etagDefaultsKey)
        guard remoteETag != knownETag else { return false }

        guard await download(to: destinationURL) else { return false }
        UserDefaults.standard.set(remoteETag, forKey: etagDefaultsKey)
        return true
    }

    private static func fetchRemoteETag() async -> String? {
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return http.value(forHTTPHeaderField: "ETag")
    }

    private static func download(to destination: URL) async -> Bool {
        guard let (tempURL, response) = try? await URLSession.shared.download(from: remoteURL),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return false
        }
        guard isValidSQLiteDatabase(at: tempURL) else {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }

        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: destination)
            }
            return true
        } catch {
            try? fileManager.removeItem(at: tempURL)
            return false
        }
    }

    /// Sanity check before swapping in a downloaded file: it must open as
    /// SQLite and contain at least one active location, so a truncated or
    /// unexpected response body can never replace a working local database.
    private static func isValidSQLiteDatabase(at url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return false
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM locations WHERE is_active = 1;", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return false }
        return sqlite3_column_int64(statement, 0) > 0
    }
}
