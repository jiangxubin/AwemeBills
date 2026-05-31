import XCTest

final class AwemeBillingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOverviewPlusOpensManualImport() throws {
        let app = launchApp()

        let overviewPlus = app.buttons["从总览手动导入"]
        XCTAssertTrue(overviewPlus.waitForExistence(timeout: 8))
        overviewPlus.tap()

        XCTAssertTrue(app.tabBars.buttons["导入"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["手动导入"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["新增消费"].waitForExistence(timeout: 3))
    }

    func testDetailTabDoesNotExposeAddEntryButton() throws {
        let app = launchApp()

        app.tabBars.buttons["明细"].tap()

        XCTAssertTrue(app.navigationBars["明细"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["明细"].buttons["新增消费"].exists)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }
}
