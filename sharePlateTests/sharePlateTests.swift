// tests for the app

import SwiftData
import XCTest
@testable import sharePlate

final class sharePlateTests: XCTestCase {

    override func setUpWithError() throws {
        // setup before each test
    }

    override func tearDownWithError() throws {
        // cleanup after each test
    }

    func testImportedPantryHoursArePreservedAndDriveOpenStatus() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!

        let weekdayHours = "Mon 9:00 AM – 5:00 PM"
        let weekdayIntervals = [
            OpeningInterval(weekday: 2, startMinutes: 9 * 60, endMinutes: 17 * 60)
        ]
        let imported = FoodResource.importedSchedule(
            hours: weekdayHours,
            intervals: weekdayIntervals,
            serviceHours: []
        )
        XCTAssertEqual(imported.hours, weekdayHours)
        XCTAssertEqual(imported.intervals, weekdayIntervals)

        let pantry = FoodResource(
            name: "Lincoln Park pantry",
            address: "Chicago, IL",
            latitude: 41.9216,
            longitude: -87.6479,
            hours: imported.hours,
            summary: "Food assistance location.",
            type: .pantry,
            openingIntervals: imported.intervals
        )
        let beforeOpening = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5, hour: 3, minute: 0
        )))
        let duringHours = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5, hour: 12, minute: 0
        )))
        let afterClosing = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5, hour: 18, minute: 0
        )))
        XCTAssertEqual(pantry.openStatus(at: beforeOpening, calendar: calendar), .closed)
        XCTAssertEqual(pantry.openStatus(at: duringHours, calendar: calendar), .open)
        XCTAssertEqual(pantry.openStatus(at: afterClosing, calendar: calendar), .closed)
    }

    @MainActor
    func testPermanentStoresStayAvailableBesideDonorListings() throws {
        let now = Date()
        let permanent = makeListing(
            title: "Harvest Hub",
            category: .pantry,
            deadline: now.addingTimeInterval(-3600),
            poster: FoodListing.permanentPosterID,
            locationID: 823,
            permanent: true
        )
        let donorMeal = makeListing(
            title: "Extra pasta",
            category: .preparedMeals,
            deadline: now.addingTimeInterval(30 * 60),
            poster: "neighbor",
            remoteID: UUID().uuidString
        )
        let donorGroceries = makeListing(
            title: "Extra apples",
            category: .produce,
            deadline: now.addingTimeInterval(2 * 3600),
            poster: "neighbor",
            remoteID: UUID().uuidString
        )
        let expiredDonor = makeListing(
            title: "Yesterday's bread",
            category: .bakery,
            deadline: now.addingTimeInterval(-3600),
            poster: "neighbor",
            remoteID: UUID().uuidString
        )

        XCTAssertFalse(permanent.isExpired)
        XCTAssertEqual(permanent.effectiveStatus, .available)
        XCTAssertEqual(permanent.mapOpenStatus, .open)
        XCTAssertEqual(permanent.mapOpenStatus.pinColor, Theme.Palette.primaryGreen)
        XCTAssertTrue(expiredDonor.isExpired)
        XCTAssertEqual(expiredDonor.effectiveStatus, .expired)

        for window in MapTimeWindow.allCases {
            XCTAssertTrue(MapBrowseLogic.listingMatchesWindow(permanent, window: window, now: now))
        }
        let standing = makeListing(
            title: "Lincoln Park vegetables",
            category: .produce,
            deadline: now.addingTimeInterval(60 * 60 * 24 * 400),
            poster: "neighbor",
            remoteID: UUID().uuidString
        )
        XCTAssertFalse(donorMeal.revealsBookingCode)
        let reservedMeal = makeListing(
            title: "Reserved pasta",
            category: .preparedMeals,
            deadline: now.addingTimeInterval(3 * 3600),
            poster: "neighbor",
            remoteID: UUID().uuidString
        )
        reservedMeal.status = .reserved
        reservedMeal.claimedByDeviceID = "claimer"
        XCTAssertTrue(reservedMeal.revealsBookingCode)

        XCTAssertTrue(standing.isStandingLocation)
        XCTAssertFalse(standing.isExpired)
        XCTAssertEqual(standing.mapOpenStatus, .open)
        for window in MapTimeWindow.allCases {
            XCTAssertTrue(MapBrowseLogic.listingMatchesWindow(standing, window: window, now: now))
        }

        XCTAssertTrue(MapBrowseLogic.listingMatchesWindow(donorMeal, window: .near, now: now))
        XCTAssertFalse(MapBrowseLogic.listingMatchesWindow(donorMeal, window: .tomorrow, now: now))
        XCTAssertFalse(MapBrowseLogic.listingMatchesWindow(expiredDonor, window: .near, now: now))

        XCTAssertTrue(permanent.matches([]))
        XCTAssertTrue(donorMeal.matches([]))
        XCTAssertTrue(permanent.matches([.storeGrocery]))
        XCTAssertFalse(donorMeal.matches([.storeGrocery]))
        XCTAssertTrue(donorGroceries.matches([.storeGrocery]))
        XCTAssertFalse(permanent.matches([.donorPickup]))
        XCTAssertFalse(donorMeal.matches([.donorPickup]))
        XCTAssertTrue(donorMeal.matches([.storeRestaurant]))
        XCTAssertTrue(permanent.matches([.storeGrocery, .donorPickup]))
        XCTAssertFalse(donorMeal.matches([.storeGrocery, .donorPickup]))
        XCTAssertTrue(donorMeal.matches([.storeRestaurant, .donorPickup]))
        XCTAssertTrue(donorMeal.matches([.storeRestaurant, .donorDropOff, .pantryFood]))
        XCTAssertTrue(donorGroceries.matches([.donorPickup, .storeGrocery, .pantryFood]))
        XCTAssertTrue(donorGroceries.matches([.donorDropOff, .storeGrocery, .pantryFood]))
        let neighborDonation = makeListing(
            title: "Extra soup",
            category: .other,
            deadline: now.addingTimeInterval(2 * 3600),
            poster: "neighbor",
            remoteID: UUID().uuidString
        )
        XCTAssertTrue(neighborDonation.isIndividualDonation)
        XCTAssertTrue(neighborDonation.matches([.donorPickup, .storeGrocery, .storeRestaurant]))
        XCTAssertFalse(neighborDonation.matches([.storeGrocery, .storeRestaurant]))
        XCTAssertFalse(neighborDonation.matches([.donorDropOff, .storeGrocery]))

        let container = try ModelContainer(
            for: FoodResource.self,
            FoodListing.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = LocalDataStore(context: container.mainContext, session: SessionContext())
        container.mainContext.insert(donorMeal)
        container.mainContext.insert(expiredDonor)

        container.mainContext.insert(permanent)
        store.ensurePermanentStoreListings()
        XCTAssertTrue(store.listings().filter(\.isPermanent).isEmpty)

        store.runMaintenance()
        store.pruneListingsAbsentFromCatalog(remoteIDs: [donorMeal.remoteID ?? ""])

        let remaining = store.listings()
        XCTAssertNotNil(remaining.first { $0.remoteID == donorMeal.remoteID && $0.status == .available })
        XCTAssertNil(remaining.first { $0.remoteID == expiredDonor.remoteID })
    }

    private func makeListing(
        title: String,
        category: FoodCategory,
        deadline: Date,
        poster: String,
        remoteID: String? = nil,
        locationID: Int? = nil,
        permanent: Bool = false
    ) -> FoodListing {
        FoodListing(
            title: title,
            details: "",
            quantity: permanent ? "Open 24 Hours" : "1 package",
            category: category,
            pickupType: .meetOutside,
            area: "Lincoln Park",
            pickupAddress: "Chicago, IL",
            latitude: 41.92,
            longitude: -87.65,
            pickupDeadline: deadline,
            remoteID: remoteID,
            postedByDeviceID: poster,
            pantryGCFDLocationID: locationID,
            isPermanent: permanent
        )
    }

    func testPerformanceExample() throws {
        // speed test example
        self.measure {
            // put the timed code here
        }
    }

}
