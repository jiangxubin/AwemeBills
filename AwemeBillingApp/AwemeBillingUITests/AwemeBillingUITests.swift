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
        let pushSettings = app.buttons["消费记录推送设置"]
        reveal(pushSettings, in: app)
        XCTAssertTrue(pushSettings.waitForExistence(timeout: 5))
        pushSettings.tap()

        XCTAssertTrue(app.navigationBars["消费记录推送设置"].waitForExistence(timeout: 3))
        let saveButton = app.buttons["保存并更新推送"]
        reveal(saveButton, in: app)
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
    }

    func testProfileExposesPrivacyAndVersionHistory() throws {
        let app = launchApp()

        app.tabBars.buttons["我的"].tap()
        let privacyTitle = app.staticTexts["识别与隐私"]
        reveal(privacyTitle, in: app)
        XCTAssertTrue(privacyTitle.waitForExistence(timeout: 5))

        let versionHistory = app.buttons["查看全部版本变化"]
        reveal(versionHistory, in: app, attempts: 4)
        XCTAssertTrue(versionHistory.waitForExistence(timeout: 5))
        versionHistory.tap()
        XCTAssertTrue(app.navigationBars["版本变化"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1.0.1"].waitForExistence(timeout: 3))
    }

    func testProfileDarkAppearanceKeepsSettingsReachable() throws {
        let app = launchApp(arguments: ["-appearanceMode", "dark"])

        app.tabBars.buttons["我的"].tap()

        XCTAssertTrue(app.staticTexts["本机账本"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["消费类型管理"].waitForExistence(timeout: 3))
        let pushSettings = app.buttons["消费记录推送设置"]
        reveal(pushSettings, in: app)
        XCTAssertTrue(pushSettings.waitForExistence(timeout: 3))
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

    func testDetailSearchFindsMerchant() throws {
        let app = launchApp(arguments: ["-ui-testing-with-samples"])

        app.tabBars.buttons["明细"].tap()
        XCTAssertTrue(app.navigationBars["明细"].waitForExistence(timeout: 5))

        let searchField = app.searchFields["搜索商户、分类或备注"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("盒马")

        XCTAssertTrue(app.staticTexts["盒马"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["咖啡店"].exists)
    }

    func testOverviewShowsFocusedStatusWithoutChartControls() throws {
        let app = launchApp(arguments: ["-ui-testing-with-samples"])

        if app.tabBars.buttons["总览"].exists {
            app.tabBars.buttons["总览"].tap()
        }

        XCTAssertTrue(app.staticTexts["本月支出"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["预算"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["最近记录"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["总览记一笔"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["查看柱状图"].exists)
        XCTAssertFalse(app.buttons["查看饼图"].exists)
    }

    func testImportKeepsPendingReviewBeforeNewImport() throws {
        let app = launchApp()

        app.tabBars.buttons["导入"].tap()

        let reviewTitle = app.staticTexts["待复核"]
        let importTitle = app.staticTexts["新增导入"]
        XCTAssertTrue(reviewTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(importTitle.waitForExistence(timeout: 5))
        XCTAssertLessThan(reviewTitle.frame.minY, importTitle.frame.minY)
    }

    func testReportTabRestoresPeriodReviewFlow() throws {
        let app = launchApp(arguments: ["-ui-testing-with-samples"])

        app.tabBars.buttons["报告"].tap()

        XCTAssertTrue(app.navigationBars["报告"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["报告中心"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.segmentedControls.buttons["每月"].waitForExistence(timeout: 3))
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 3) {
        for _ in 0..<attempts where !element.exists {
            app.swipeUp()
        }
    }

}
