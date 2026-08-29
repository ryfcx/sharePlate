//
//  ModelContainerFactory.swift
//  sharePlate
//
//  Creates the SwiftData store. If the on-disk schema is incompatible (common
//  during development when models change), wipes the local store and retries.
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
            // Prototype app: drop incompatible local data and recreate.
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

    /// Removes the default store name used before we pinned an explicit URL.
    private static func wipeLegacyStores() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        wipeStore(at: support.appending(path: "default.store"))
    }
}
