// ui tests for the app

import XCTest

final class sharePlateUITests: XCTestCase {

    override func setUpWithError() throws {
        // setup before each test
        // stop right away when something fails
        continueAfterFailure = false

        // set the starting state here
    }

    override func tearDownWithError() throws {
        // cleanup after each test
    }

    @MainActor
    func testExample() throws {
        // launch the app to test it
        let app = XCUIApplication()
        app.launch()

        // check the results here
    }

    @MainActor
    func testLaunchPerformance() throws {
        // check how fast the app launches
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
