//
// modelcontainerfactory.swift
// shareplate
//
// creates the swiftdata store
// if on disk schema is incompatible, wipes store and retries
// common during development when models change
//

import Foundation
import SwiftData

enum ModelContainerFactory {
    static let schema = Schema([
        FoodResource.self,
        FoodListing.self,
        ReportRecord.self,
        PantryClaim.self,
    ])

    static func make() throws -> ModelContainer {
        let storeURL = storeFileURL
        let config = ModelConfiguration(schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // prototype app, drops bad local data and recreates
            wipeStore(at: storeURL)
            wipeLegacyStores()
            return try ModelContainer(for: schema, configurations: [config])
        }
    }

    private static var storeFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appending(path: "SharePlate.store")
    }

    private static func wipeStore(at url: URL) {
        let fm = FileManager.default
        let base = url.path
        for path in [base, base + "-wal", base + "-shm"] {
            try? fm.removeItem(atPath: path)
        }
    }

    // removes default store name used before pinned url
    private static func wipeLegacyStores() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        wipeStore(at: support.appending(path: "default.store"))
    }
}
