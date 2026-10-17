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

        let field = app.textFields["Address, lat, lng or map link"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("45.4642, 9.19\n")

        XCTAssertTrue(app.staticTexts[coordinates].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["From: Coordinates"].exists)
        attachScreenshot(app, "Send")

        // without a Mapbox token the route section offers the setup: own account, then the public token
        let setUpMapbox = app.buttons["Set up Mapbox"].firstMatch
        XCTAssertTrue(setUpMapbox.waitForExistence(timeout: 5))
        setUpMapbox.tap()
        XCTAssertTrue(app.buttons["Create a free Mapbox account"].waitForExistence(timeout: 5))
        attachScreenshot(app, "MapboxSetup")
        app.buttons["Cancel"].tap()

        // favorites live in the App Group storage and survive between runs
        let alreadyFavorite = app.buttons["Remove from favorites"]
        if alreadyFavorite.exists {
            alreadyFavorite.tap()
        }
        XCTAssertTrue(app.buttons["Add to favorites"].waitForExistence(timeout: 5))
        app.buttons["Add to favorites"].tap()
        XCTAssertTrue(app.buttons["Remove from favorites"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Favorites"].tap()
        let favorite = app.staticTexts[coordinates].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        attachScreenshot(app, "Favorites")

        // leave no favorite behind for the next run
        favorite.swipeLeft()
        app.buttons["Remove"].tap()
        XCTAssertTrue(app.staticTexts["No favorites yet"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Devices"].tap()
        // "Add token" on a fresh install, "Replace token" once a comma token is stored
        var tokenButton = app.buttons["Add token"]
        if !tokenButton.waitForExistence(timeout: 5) {
            tokenButton = app.buttons["Replace token"]
        }
        XCTAssertTrue(tokenButton.exists)
        attachScreenshot(app, "Devices")

        tokenButton.tap()
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
        XCTAssertTrue(app.staticTexts["From: Map link"].exists)
        attachScreenshot(app, "GeoLink")
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
