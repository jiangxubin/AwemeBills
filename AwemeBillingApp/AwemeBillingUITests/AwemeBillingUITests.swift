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

    func testScreenshotImportShowsSourcePickerBeforePhotos() throws {
        let app = launchApp()

        app.tabBars.buttons["导入"].tap()
        XCTAssertTrue(app.buttons["截图导入"].waitForExistence(timeout: 5))
        app.buttons["截图导入"].tap()

        XCTAssertTrue(app.navigationBars["截图来源"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["选择不选择"].exists)
        XCTAssertTrue(app.buttons["选择微信"].exists)
        XCTAssertTrue(app.buttons["选择支付宝"].exists)
        XCTAssertTrue(app.buttons["选择云闪付"].exists)

        app.buttons["选择微信"].tap()
        XCTAssertTrue(app.buttons["选择照片"].waitForExistence(timeout: 3))
    }

    func testImportModesExposeTextAndManualFlows() throws {
        let app = launchApp()

        app.tabBars.buttons["导入"].tap()
        XCTAssertTrue(app.buttons["文本解析"].waitForExistence(timeout: 5))

        app.buttons["文本解析"].tap()
        XCTAssertTrue(app.staticTexts["通知文本"].waitForExistence(timeout: 3))

        app.buttons["手动导入"].tap()
        XCTAssertTrue(app.buttons["打开手动导入"].waitForExistence(timeout: 3))
    }

    func testProfileExposesCategoryManagement() throws {
        let app = launchApp()

        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["消费类型管理"].waitForExistence(timeout: 5))
        app.buttons["消费类型管理"].tap()

        XCTAssertTrue(app.navigationBars["消费类型管理"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["餐饮"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["例如 咖啡、宠物、运动"].waitForExistence(timeout: 3))
    }

    func testProfileExposesPushSettingsNavigation() throws {
        let app = launchApp()

        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["消费记录推送设置"].waitForExistence(timeout: 5))
        app.buttons["消费记录推送设置"].tap()

        XCTAssertTrue(app.navigationBars["消费记录推送设置"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["保存并更新推送"].waitForExistence(timeout: 3))
    }

    func testProfileExposesOCRRecognitionStatistics() throws {
        let app = launchApp()

        app.tabBars.buttons["我的"].tap()
        let statisticsTitle = app.staticTexts["识别结果统计"]
        if !statisticsTitle.waitForExistence(timeout: 2) {
            app.swipeUp()
        }

        XCTAssertTrue(statisticsTitle.waitForExistence(timeout: 5))
    }

    func testProfileDarkAppearanceKeepsSettingsReachable() throws {
        let app = launchApp(arguments: ["-appearanceMode", "dark"])

        app.tabBars.buttons["我的"].tap()

        XCTAssertTrue(app.staticTexts["本机账本"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["消费类型管理"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["消费记录推送设置"].waitForExistence(timeout: 3))
    }

    func testDetailUsesMonthAndQuickFiltersOnly() throws {
        let app = launchApp()

        app.tabBars.buttons["明细"].tap()
        XCTAssertTrue(app.navigationBars["明细"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["月份筛选"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["筛选"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["聚合"].exists)
    }

    func testDetailFiltersUseCompactLabelsWithoutHelperCopy() throws {
        let app = launchApp(arguments: ["-ui-testing-with-samples"])

        app.tabBars.buttons["明细"].tap()
        XCTAssertTrue(app.buttons["月份筛选"].waitForExistence(timeout: 5))

        XCTAssertFalse(app.staticTexts["本月及历史"].exists)
        XCTAssertFalse(app.staticTexts["向下滚动查看历史"].exists)
        XCTAssertFalse(app.staticTexts["类型 / 场景 / 渠道"].exists)
    }

    func testDetailExposesBatchDeleteSelectionMode() throws {
        let app = launchApp(arguments: ["-ui-testing-with-samples"])

        app.tabBars.buttons["明细"].tap()
        XCTAssertTrue(app.navigationBars["明细"].waitForExistence(timeout: 5))

        let selectButton = app.buttons["选择多条记录"]
        XCTAssertTrue(selectButton.waitForExistence(timeout: 5))
        selectButton.tap()

        XCTAssertTrue(app.buttons["全选记录"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["批量删除"].waitForExistence(timeout: 3))

        app.buttons["完成选择"].tap()
    }

    func testOverviewOwnsSpendingStructureCharts() throws {
        let app = launchApp()

        if app.tabBars.buttons["总览"].exists {
            app.tabBars.buttons["总览"].tap()
        }

        XCTAssertTrue(app.buttons["查看周度消费柱状图"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["查看月度消费柱状图"].waitForExistence(timeout: 3))
        app.buttons["查看月度消费柱状图"].tap()

        let structureTitle = app.staticTexts["消费分析"]
        XCTAssertTrue(structureTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["查看柱状图"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["查看饼图"].waitForExistence(timeout: 3))
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        return app
    }

}
