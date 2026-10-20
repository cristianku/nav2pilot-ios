import XCTest

/// Drives the real app in the simulator. No comma token and no network are needed:
/// coordinates and geo: links resolve locally.
final class Nav2PilotUITests: XCTestCase {
    private let coordinates = "45.464200, 9.190000"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTypedCoordinatesBecomeTheDestinationAndAFavorite() {
        let app = XCUIApplication()
        app.launch()

        // the search pill opens the search field
        let pill = app.buttons["Search a place"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15))
        attachScreenshot(app, "Map")
        pill.tap()
        let field = app.textFields["Search or paste a link"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("45.4642, 9.19\n")

        XCTAssertTrue(app.staticTexts[coordinates].waitForExistence(timeout: 5))
        // where the destination came from is folded under Details
        app.buttons["Details"].tap()
        XCTAssertTrue(app.staticTexts["From: Coordinates"].waitForExistence(timeout: 5))
        attachScreenshot(app, "Send")

        // a car without comma prime and no Mapbox token: the panel offers the setup (own account, public token)
        let setUpMapbox = app.buttons["Set up Mapbox"].firstMatch
        if setUpMapbox.waitForExistence(timeout: 5) {
            setUpMapbox.tap()
            XCTAssertTrue(app.buttons["Create a free Mapbox account"].waitForExistence(timeout: 5))
            attachScreenshot(app, "MapboxSetup")
            app.buttons["Cancel"].tap()
        }

        // favorites live in the App Group storage and survive between runs
        let alreadyFavorite = app.buttons["Remove from favorites"]
        if alreadyFavorite.exists {
            alreadyFavorite.tap()
        }
        XCTAssertTrue(app.buttons["Add to favorites"].waitForExistence(timeout: 5))
        app.buttons["Add to favorites"].tap()
        XCTAssertTrue(app.buttons["Remove from favorites"].waitForExistence(timeout: 5))

        // the favorites button is on the map only without a destination
        app.buttons["Clear destination"].tap()
        app.buttons["Favorites"].tap()
        let favorite = app.cells.containing(.staticText, identifier: coordinates).firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        attachScreenshot(app, "Favorites")

        // leave no favorite behind for the next run (other favorites of this simulator stay);
        // the sheet opens at half height, full height first so the row is not under the screen edge
        app.buttons["Sheet Grabber"].swipeUp()
        favorite.staticTexts.firstMatch.swipeLeft()
        app.buttons["Remove"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: favorite)
        waitForExpectations(timeout: 5)
        app.buttons["Done"].tap()

        app.buttons["Settings"].tap()
        // "Add token" on a fresh install, "Manage" > "Replace token" once a comma token is stored
        let addToken = app.buttons["Add token"]
        if addToken.waitForExistence(timeout: 5) {
            attachScreenshot(app, "Devices")
            addToken.tap()
        } else {
            let manage = app.buttons["Manage"]
            XCTAssertTrue(manage.exists)
            attachScreenshot(app, "Devices")
            manage.tap()
            app.buttons["Replace token"].tap()
        }
        XCTAssertTrue(app.secureTextFields["JWT"].waitForExistence(timeout: 5))
        attachScreenshot(app, "Token")
        app.buttons["Cancel"].tap()
    }

    func testGeoLinkOpensTheApp() {
        let app = XCUIApplication()
        app.launch()
        guard let url = URL(string: "geo:0,0?q=45.1,9.2(Garage)") else {
            return XCTFail("bad URL")
        }

        app.open(url)

        XCTAssertTrue(app.staticTexts["Garage"].waitForExistence(timeout: 10))
        app.buttons["Details"].tap()
        XCTAssertTrue(app.staticTexts["From: Map link"].waitForExistence(timeout: 5))
        attachScreenshot(app, "GeoLink")
    }

    /// The main screens with a destination and a car, for the README and visual checks.
    /// Needs a car in the simulator's storage (the comma account, or a demo device written into the
    /// App Group defaults); without one it is skipped. Nothing is sent: the test never taps Send.
    func testScreenshotTour() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Settings"].tap()
        let carActions = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Actions for ")).firstMatch
        if !carActions.waitForExistence(timeout: 3) {
            throw XCTSkip("no car stored in this simulator")
        }
        attachScreenshot(app, "Tour-Devices")
        app.buttons["Done"].tap()

        guard let url = URL(string: "geo:0,0?q=45.464211,9.191383(Duomo di Milano)") else {
            return XCTFail("bad URL")
        }
        app.open(url)
        XCTAssertTrue(app.staticTexts["Duomo di Milano"].waitForExistence(timeout: 10))
        attachScreenshot(app, "Tour-Send")
        app.buttons["Details"].tap()
        XCTAssertTrue(app.staticTexts["From: Map link"].waitForExistence(timeout: 5))
        attachScreenshot(app, "Tour-SendDetails")

        let alreadyFavorite = app.buttons["Remove from favorites"]
        if !alreadyFavorite.exists {
            app.buttons["Add to favorites"].tap()
        }
        app.buttons["Clear destination"].tap()
        app.buttons["Favorites"].tap()
        let favorite = app.staticTexts["Duomo di Milano"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        attachScreenshot(app, "Tour-Favorites")

        // the other tests expect no favorites
        favorite.swipeLeft()
        app.buttons["Remove"].tap()
        XCTAssertTrue(app.staticTexts["Your places, one tap away"].waitForExistence(timeout: 5))
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
