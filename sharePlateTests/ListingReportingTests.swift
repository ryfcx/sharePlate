import Foundation
import SwiftData
import XCTest
@testable import sharePlate

final class ListingReportingTests: XCTestCase {
    @MainActor
    func testUnsyncedListingCannotCreateAReportReceipt() async throws {
        let container = try ModelContainer(for: FoodListing.self, ReportRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LocalDataStore(context: container.mainContext, session: SessionContext())
        let listing = makeListing(remoteID: nil)
        do {
            try await store.report(listing, reason: .spam, notes: nil)
            XCTFail("an unsynced listing should not be reported")
        } catch let error as ReportSubmissionError {
            guard case .listingUnavailable = error else { return XCTFail("unexpected report error") }
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ReportRecord>()), 0)
    }

    @MainActor
    func testOversizedNotesCannotCreateAReportReceipt() async throws {
        let container = try ModelContainer(for: FoodListing.self, ReportRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LocalDataStore(context: container.mainContext, session: SessionContext())
        let listing = makeListing(remoteID: UUID().uuidString)
        // combining characters count the same way as the database
        let notes = String(repeating: "e\u{301}", count: 501)
        do {
            try await store.report(listing, reason: .unsafeFood, notes: notes)
            XCTFail("oversized notes should be rejected before sending")
        } catch let error as ReportSubmissionError {
            guard case .notesTooLong = error else { return XCTFail("unexpected report error") }
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ReportRecord>()), 0)
    }

    @MainActor
    func testOwnListingCannotBeReported() async throws {
        let container = try ModelContainer(for: FoodListing.self, ReportRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let session = SessionContext()
        session.currentUserID = UUID().uuidString
        let store = LocalDataStore(context: container.mainContext, session: session)
        let listing = makeListing(remoteID: UUID().uuidString)
        listing.postedByDeviceID = session.identity.lowercased()
        do {
            try await store.report(listing, reason: .fake, notes: nil)
            XCTFail("own listings should not be reported")
        } catch let error as ReportSubmissionError {
            guard case .ownListing = error else { return XCTFail("unexpected report error") }
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ReportRecord>()), 0)
    }

    @MainActor
    private func makeListing(remoteID: String?) -> FoodListing {
        FoodListing(title: "Bread", details: "Bread", quantity: "1", category: .bakery,
            pickupAddress: "Chicago", latitude: 41.92, longitude: -87.65,
            pickupDeadline: Date().addingTimeInterval(3600), remoteID: remoteID,
            postedByDeviceID: UUID().uuidString)
    }
}
