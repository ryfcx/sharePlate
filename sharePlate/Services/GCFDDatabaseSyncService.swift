// gcfd database sync service
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

    // checks for new data and grabs it if there is any
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

    // quick check so a bad file never swaps in
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
