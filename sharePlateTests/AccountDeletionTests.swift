import Foundation
import SwiftData
import XCTest
@testable import sharePlate

final class AccountDeletionTests: XCTestCase {
    @MainActor
    func testLocalCleanupRemovesPersonalDataAndKeepsPantryDirectory() throws {
        let suite = "shareplate-deletion-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: FoodResource.self, FoodListing.self, ReportRecord.self, PantryClaim.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let session = SessionContext(defaults: defaults)
        session.currentUserID = UUID().uuidString
        session.displayName = "Test neighbor"
        let oldDevice = session.deviceID
        let owner = session.identity
        let block = BlockedUser(blockedID: UUID(), displayName: "Neighbor", createdAt: Date())
        defaults.set(try JSONEncoder().encode([owner.lowercased(): [block]]), forKey: "sharePlate.blockedUsers")
        let store = LocalDataStore(context: container.mainContext, session: session, blockDefaults: defaults)
        let resource = FoodResource(name: "Pantry", address: "Chicago", latitude: 41.92, longitude: -87.65,
            hours: "Monday 9–12", summary: "Food pantry", type: .pantry, gcfdLocationID: 823)
        container.mainContext.insert(resource)
        container.mainContext.insert(PantryClaim(gcfdLocationID: 823, pantryName: "Pantry", claimedByUserID: owner,
            isTemporarilyClosed: true, closedNote: "Private manager note"))
        container.mainContext.insert(FoodListing(title: "Food", details: "Food", quantity: "1",
            pickupAddress: "Private address", latitude: 41.92, longitude: -87.65,
            pickupDeadline: Date().addingTimeInterval(3600), postedByDeviceID: owner))
        container.mainContext.insert(ReportRecord(listingID: UUID().uuidString, reason: .spam, reportedByDeviceID: owner))
        try container.mainContext.save()
        store.reapplyPantryClaimsToResources()
        XCTAssertTrue(resource.isTemporarilyClosed)
        XCTAssertEqual(store.blockedUsers.count, 1)

        session.isDeletingData = true
        try store.erasePersonalData()
        session.resetPersonalIdentity()
        session.hasDeletedData = true
        session.isDeletingData = false
        XCTAssertTrue(store.listings().isEmpty)
        XCTAssertTrue(store.pantryClaims().isEmpty)
        XCTAssertTrue(store.blockedUsers.isEmpty)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ReportRecord>()), 0)
        XCTAssertEqual(store.resources().count, 1)
        XCTAssertFalse(resource.isTemporarilyClosed)
        XCTAssertNil(resource.managedByUserID)
        XCTAssertNil(resource.pantryClosedNote)
        XCTAssertNil(defaults.data(forKey: "sharePlate.blockedUsers"))
        XCTAssertNotEqual(session.deviceID, oldDevice)
        XCTAssertNil(session.currentUserID)
        XCTAssertNotEqual(session.displayName, "Test neighbor")

        let relaunched = SessionContext(defaults: defaults)
        XCTAssertTrue(relaunched.hasDeletedData)
        XCTAssertFalse(relaunched.allowsDataAccess)
    }

    @MainActor
    func testPendingDeletionSurvivesRestartWithoutAllowingAppRequests() throws {
        let suite = "shareplate-deletion-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = SessionContext(defaults: defaults)
        XCTAssertTrue(session.allowsDataAccess)
        session.deletionPending = true
        XCTAssertFalse(session.allowsDataAccess)
        let relaunched = SessionContext(defaults: defaults)
        XCTAssertTrue(relaunched.deletionPending)
        XCTAssertFalse(relaunched.allowsDataAccess)
        XCTAssertFalse(relaunched.hasDeletedData)
        XCTAssertNil(relaunched.currentUserID)
        // completion wins if the app stopped between saving the two flags
        defaults.set(true, forKey: AccountDeletionStorage.deletedKey)
        let completed = SessionContext(defaults: defaults)
        XCTAssertTrue(completed.hasDeletedData)
        XCTAssertFalse(completed.deletionPending)
        XCTAssertFalse(completed.allowsDataAccess)
    }
}
