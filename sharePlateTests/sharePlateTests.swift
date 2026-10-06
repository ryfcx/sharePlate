//
//  sharePlateTests.swift
//  sharePlateTests
//
//  Created by Ryan Gupta on 5/31/26.
//

import SwiftData
import XCTest
@testable import sharePlate

final class sharePlateTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testAlwaysOpenPantriesStayGreenThroughTheDayAndAfterRefresh() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!

        let weekdayHours = "Mon 9:00 AM – 5:00 PM"
        let weekdayIntervals = [
            OpeningInterval(weekday: 2, startMinutes: 9 * 60, endMinutes: 17 * 60)
        ]
        let checks: [(hour: Int, minute: Int, day: Int)] = [
            (0, 0, 5),
            (3, 30, 5),
            (8, 59, 5),
            (9, 0, 5),
            (12, 0, 5),
            (16, 15, 5),
            (18, 0, 5),
            (23, 59, 5),
            (12, 0, 6),
        ]

        for locationID in FoodResource.alwaysOpenLocationIDs {
            let firstImport = FoodResource.importedSchedule(
                locationID: locationID,
                hours: weekdayHours,
                intervals: weekdayIntervals,
                serviceHours: []
            )
            let refreshed = FoodResource.importedSchedule(
                locationID: locationID,
                hours: weekdayHours,
                intervals: weekdayIntervals,
                serviceHours: []
            )
            XCTAssertEqual(firstImport.hours, "Open 24 Hours")
            XCTAssertEqual(refreshed.hours, firstImport.hours)
            XCTAssertTrue(refreshed.intervals.isEmpty)
            XCTAssertTrue(refreshed.serviceHours.isEmpty)

            let pantry = FoodResource(
                name: "Lincoln Park pantry",
                address: "Chicago, IL",
                latitude: 41.9216,
                longitude: -87.6479,
                hours: refreshed.hours,
                summary: "Food assistance location.",
                type: .pantry,
                openingIntervals: refreshed.intervals,
                serviceHours: refreshed.serviceHours,
                gcfdLocationID: locationID
            )

            for check in checks {
                let moment = try XCTUnwrap(calendar.date(from: DateComponents(
                    year: 2026, month: 10, day: check.day, hour: check.hour, minute: check.minute
                )))
                XCTAssertEqual(pantry.openStatus(at: moment, calendar: calendar), .open)
                XCTAssertEqual(pantry.openStatus(at: moment, calendar: calendar).pinColor, Theme.Palette.primaryGreen)
                XCTAssertEqual(pantry.isOpen(at: moment), true)
                XCTAssertTrue(pantry.hasScheduledHours(on: moment, calendar: calendar))
                let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: moment))
                XCTAssertEqual(pantry.openStatusPreview(on: tomorrow, calendar: calendar), .open)
            }
        }

        let ordinary = FoodResource.importedSchedule(
            locationID: 1,
            hours: weekdayHours,
            intervals: weekdayIntervals,
            serviceHours: []
        )
        XCTAssertEqual(ordinary.hours, weekdayHours)
        let closedPantry = FoodResource(
            name: "Other pantry",
            address: "Chicago, IL",
            latitude: 41.88,
            longitude: -87.63,
            hours: ordinary.hours,
            summary: "Food assistance location.",
            type: .pantry,
            openingIntervals: ordinary.intervals,
            gcfdLocationID: 1
        )
        let earlyMorning = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 5, hour: 3, minute: 0
        )))
        XCTAssertEqual(closedPantry.openStatus(at: earlyMorning, calendar: calendar), .closed)
        XCTAssertEqual(closedPantry.openStatus(at: earlyMorning, calendar: calendar).pinColor, Theme.Palette.urgentRed)
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
            deadline: now.addingTimeInterval(3 * 3600),
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
        XCTAssertTrue(donorMeal.matches([.donorPickup]))
        XCTAssertTrue(permanent.matches([.storeGrocery, .donorPickup]))
        XCTAssertTrue(donorMeal.matches([.storeGrocery, .donorPickup]))

        let container = try ModelContainer(
            for: FoodResource.self,
            FoodListing.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = LocalDataStore(context: container.mainContext, session: SessionContext())
        for id in FoodResource.alwaysOpenLocationIDs {
            container.mainContext.insert(
                FoodResource(
                    name: "Store \(id)",
                    address: "1 Main St, Chicago, IL 60614",
                    latitude: 41.92,
                    longitude: -87.65,
                    hours: "Mon 9:00 AM – 5:00 PM",
                    summary: "Food assistance location.",
                    type: .pantry,
                    gcfdLocationID: id
                )
            )
        }
        container.mainContext.insert(donorMeal)
        container.mainContext.insert(expiredDonor)

        XCTAssertEqual(FoodResource.alwaysOpenLocationIDs, Set([823, 20947, 820]))
        XCTAssertFalse(FoodResource.alwaysOpenLocationIDs.contains(817))

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
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
