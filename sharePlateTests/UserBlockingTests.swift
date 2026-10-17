import Foundation
import SwiftData
import XCTest
@testable import sharePlate

final class UserBlockingTests: XCTestCase {
    @MainActor
    func testSavedBlocksSurviveRestartAndStayWithTheirAccount() throws {
        let suite = "shareplate-block-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = UUID()
        let target = UUID()
        let block = BlockedUser(blockedID: target, displayName: "User from bread", createdAt: Date())
        defaults.set(try JSONEncoder().encode([owner.uuidString.lowercased(): [block]]),
                     forKey: "sharePlate.blockedUsers")

        let container = try ModelContainer(for: FoodListing.self, FoodResource.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let session = SessionContext()
        session.currentUserID = owner.uuidString
        let store = LocalDataStore(context: container.mainContext, session: session, blockDefaults: defaults)
        XCTAssertTrue(store.isUserBlocked(target.uuidString.lowercased()))
        XCTAssertFalse(store.isUserBlocked(owner.uuidString))
        XCTAssertFalse(store.isUserBlocked(nil))

        let restarted = LocalDataStore(context: container.mainContext, session: session, blockDefaults: defaults)
        XCTAssertEqual(restarted.blockedUsers, [block])
        session.currentUserID = UUID().uuidString
        XCTAssertTrue(restarted.blockedUsers.isEmpty)
        XCTAssertFalse(restarted.isUserBlocked(target.uuidString))
    }

    @MainActor
    func testCannotReserveBlockedDonorWhileOffline() async throws {
        let suite = "shareplate-block-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = UUID()
        let target = UUID()
        defaults.set(try JSONEncoder().encode([
            owner.uuidString.lowercased(): [BlockedUser(blockedID: target, displayName: "Neighbor", createdAt: Date())]
        ]), forKey: "sharePlate.blockedUsers")
        let container = try ModelContainer(for: FoodListing.self, FoodResource.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let session = SessionContext()
        session.currentUserID = owner.uuidString
        let store = LocalDataStore(context: container.mainContext, session: session, blockDefaults: defaults)
        let listing = FoodListing(title: "Bread", details: "Bread", quantity: "1", category: .bakery,
            pickupAddress: "Chicago", latitude: 41.92, longitude: -87.65,
            pickupDeadline: Date().addingTimeInterval(3600), postedByDeviceID: target.uuidString)
        do {
            try await store.reserve(listing)
            XCTFail("blocked donor should not be reservable")
        } catch let error as ReserveError {
            guard case .notAvailable = error else { return XCTFail("unexpected reservation error") }
        }
    }
}
