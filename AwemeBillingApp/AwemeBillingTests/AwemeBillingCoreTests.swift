import XCTest
import SwiftData
import SwiftUI
import UIKit
@testable import AwemeBillingApp

final class AwemeBillingCoreTests: XCTestCase {
    func testAppThemeBackgroundAndInkAdaptToDarkAppearance() {
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)
        let darkTrait = UITraitCollection(userInterfaceStyle: .dark)

        let lightBackground = UIColor(AppTheme.background).resolvedColor(with: lightTrait)
        let darkBackground = UIColor(AppTheme.background).resolvedColor(with: darkTrait)
        let lightInk = UIColor(AppTheme.ink).resolvedColor(with: lightTrait)
        let darkInk = UIColor(AppTheme.ink).resolvedColor(with: darkTrait)

        XCTAssertGreaterThan(relativeLuminance(lightBackground), 0.75)
        XCTAssertLessThan(relativeLuminance(darkBackground), 0.20)
        XCTAssertLessThan(relativeLuminance(lightInk), 0.25)
        XCTAssertGreaterThan(relativeLuminance(darkInk), 0.75)
    }

    func testMerchantLogoStyleUsesMerchantPlatformInsteadOfPaymentChannel() {
        let meituan = MerchantLogoStyle.resolve(
            merchant: "美团",
            category: .dining,
            rawText: "支付宝 · 餐饮美食 · 待复核"
        )
        let dianping = MerchantLogoStyle.resolve(
            merchant: "大众点评团购",
            category: .dining,
            rawText: "微信支付"
        )
        let tmall = MerchantLogoStyle.resolve(
            merchant: "天猫 Apple/苹果 Mac Studio",
            category: .shopping,
            rawText: "支付宝"
        )
        let fallback = MerchantLogoStyle.resolve(
            merchant: "小区咖啡",
            category: .dining,
            rawText: "微信支付"
        )

        XCTAssertEqual(meituan.kind, .meituan)
        XCTAssertEqual(dianping.kind, .dianping)
        XCTAssertEqual(tmall.kind, .tmall)
        XCTAssertEqual(fallback.kind, .category)
        XCTAssertNotEqual(meituan.label, "支")
        XCTAssertNotEqual(dianping.label, "微")
    }

    func testDailyCompletedPeriodUsesPreviousDayBoundary() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 25, hour: 10)))
        let interval = try XCTUnwrap(BillingAnalytics.completedPeriodInterval(for: .day, before: now))

        XCTAssertEqual(calendar.component(.day, from: interval.start), 24)
        XCTAssertEqual(calendar.component(.day, from: interval.end), 25)
    }

    func testNextFireDateKeepsTodayWhenTimeHasNotPassed() throws {
        let calendar = Calendar(identifier: .gregorian)
        let schedule = ArchiveSchedule(period: .day, hour: 10, minute: 0)
        let beforeFire = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 25, hour: 8)))
        let afterFire = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 25, hour: 10, minute: 1)))

        let todayFire = BillingAnalytics.nextFireDate(for: schedule, from: beforeFire)
        let tomorrowFire = BillingAnalytics.nextFireDate(for: schedule, from: afterFire)

        XCTAssertEqual(calendar.component(.day, from: todayFire), 25)
        XCTAssertEqual(calendar.component(.hour, from: todayFire), 10)
        XCTAssertEqual(calendar.component(.day, from: tomorrowFire), 26)
        XCTAssertEqual(calendar.component(.hour, from: tomorrowFire), 10)
    }

    func testDeduplicationRejectsSamePaymentMinute() {
        let date = Date(timeIntervalSince1970: 1_769_184_000)
        let existing = ExpenseRecord(
            amount: 38.5,
            merchant: "咖啡店",
            category: .dining,
            scene: "早餐",
            channel: .alipay,
            occurredAt: date
        )
        let duplicate = ParsedPayment(
            amount: 38.5,
            merchant: " 咖啡店 ",
            channel: .alipay,
            note: "",
            occurredAt: date,
            category: .dining
        )

        XCTAssertTrue(ExpenseRecordMaintenance.uniquePayments([duplicate], existing: [existing]).isEmpty)
    }

    func testPaymentTextParserFindsSimpleNotification() {
        let payments = PaymentTextParser.parseAll("支付宝通知：你向咖啡店支付 38.50 元")

        XCTAssertEqual(payments.first?.merchant, "咖啡店")
        XCTAssertEqual(payments.first?.channel, .alipay)
        XCTAssertEqual(payments.first?.category, .dining)
    }

    func testPaymentTextParserFindsMerchantFromPaymentToPattern() throws {
        let payments = PaymentTextParser.parseAll("微信支付凭证：已付款给 上海真如山姆会员店 ￥277.97")

        let payment = try XCTUnwrap(payments.first)
        XCTAssertEqual(payment.merchant, "上海真如山姆会员店")
        XCTAssertEqual(payment.channel, .wechat)
        XCTAssertEqual(payment.category, .shopping)
        XCTAssertEqual((payment.amount as NSDecimalNumber).doubleValue, 277.97, accuracy: 0.001)
    }

    @MainActor
    func testAutomationTextImportAutoAcceptsHighConfidenceText() async throws {
        let context = try makeInMemoryContext()

        let summary = await AutomationTextImportService.importText(
            "支付宝通知：你向咖啡店支付 38.50 元",
            context: context,
            refreshAfterAccept: false
        )

        XCTAssertEqual(summary.parsedCount, 1)
        XCTAssertEqual(summary.acceptedCount, 1)
        XCTAssertEqual(summary.pendingReviewCount, 0)

        let records = try context.fetch(FetchDescriptor<ExpenseRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.merchant, "咖啡店")
    }

    @MainActor
    func testAutomationTextImportKeepsLowConfidenceTextForReview() async throws {
        let context = try makeInMemoryContext()

        let summary = await AutomationTextImportService.importText(
            "支付提醒：你向未知商户支付 12.00 元",
            context: context,
            refreshAfterAccept: false
        )

        XCTAssertEqual(summary.parsedCount, 1)
        XCTAssertEqual(summary.acceptedCount, 0)
        XCTAssertEqual(summary.pendingReviewCount, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExpenseRecord>()).isEmpty)
    }

    func testOCRTextSelectionPrefersTencentResult() throws {
        let payments = ReceiptImageParser.parseOCRTexts(
            tencentText: "支付宝通知：你向腾讯识别商户支付 66.00 元",
            visionText: "支付宝通知：你向本机识别商户支付 22.00 元"
        )

        let payment = try XCTUnwrap(payments.first)
        XCTAssertEqual(payment.merchant, "腾讯识别商户")
        XCTAssertEqual(payment.channel, .alipay)
        XCTAssertEqual((payment.amount as NSDecimalNumber).doubleValue, 66.0, accuracy: 0.001)
    }

    func testOCRTextSelectionFallsBackToVisionResult() throws {
        let payments = ReceiptImageParser.parseOCRTexts(
            tencentText: "未识别到账单金额",
            visionText: "支付宝通知：你向本机识别商户支付 22.00 元"
        )

        let payment = try XCTUnwrap(payments.first)
        XCTAssertEqual(payment.merchant, "本机识别商户")
        XCTAssertEqual(payment.channel, .alipay)
        XCTAssertEqual((payment.amount as NSDecimalNumber).doubleValue, 22.0, accuracy: 0.001)
    }

    func testOCRTextSelectionFallsBackToOCRSpaceBeforeVision() throws {
        let payments = ReceiptImageParser.parseOCRTexts(
            glmText: "没有交易",
            tencentText: "未识别到账单金额",
            ocrSpaceText: "支付宝通知：你向备用识别商户支付 33.00 元",
            visionText: "支付宝通知：你向本机识别商户支付 22.00 元"
        )

        let payment = try XCTUnwrap(payments.first)
        XCTAssertEqual(payment.merchant, "备用识别商户")
        XCTAssertEqual(payment.channel, .alipay)
        XCTAssertEqual((payment.amount as NSDecimalNumber).doubleValue, 33.0, accuracy: 0.001)
    }

    func testOCRTextSelectionPrefersGLMStructuredPayload() throws {
        let payments = ReceiptImageParser.parseOCRTexts(
            glmText: """
            {"source":"微信支付","payments":[{"merchant":"生活缴费","amount":"-55.10","channel":"微信支付","category":"居家","occurredAt":"2026-06-06 10:24","note":"微信账单"}]}
            """,
            tencentText: "支付宝通知：你向腾讯识别商户支付 66.00 元",
            visionText: "支付宝通知：你向本机识别商户支付 22.00 元"
        )

        let payment = try XCTUnwrap(payments.first)
        XCTAssertEqual(payment.merchant, "生活缴费")
        XCTAssertEqual(payment.channel, .wechat)
        XCTAssertEqual(payment.category, .housing)
        XCTAssertEqual((payment.amount as NSDecimalNumber).doubleValue, 55.1, accuracy: 0.001)
    }

    func testReceiptImageParserFallsBackWhenGLMProviderFails() async throws {
        let payments = try await ReceiptImageParser.parseAll(
            image: UIImage(),
            preferredChannel: .wechat,
            providers: [
                StubReceiptOCRProvider(result: .failure(StubReceiptOCRError.failed)),
                StubReceiptOCRProvider(result: .success([
                    ReceiptOCRTextCandidate(source: "tencent", text: "微信支付凭证：已付款给 上海真如山姆会员店 ￥277.97")
                ]))
            ]
        )

        let payment = try XCTUnwrap(payments.first)
        XCTAssertEqual(payment.merchant, "上海真如山姆会员店")
        XCTAssertEqual(payment.channel, .wechat)
        XCTAssertEqual((payment.amount as NSDecimalNumber).doubleValue, 277.97, accuracy: 0.001)
    }

    func testReceiptImageParserAggregatesSegmentedProviderCandidates() async throws {
        let payments = try await ReceiptImageParser.parseAll(
            image: UIImage(),
            preferredChannel: .alipay,
            providers: [
                StubReceiptOCRProvider(result: .success([
                    ReceiptOCRTextCandidate(source: "segment-1", text: "支付宝通知：你向咖啡店支付 38.50 元"),
                    ReceiptOCRTextCandidate(source: "segment-2", text: "支付宝通知：你向书店支付 66.00 元")
                ]))
            ]
        )

        XCTAssertEqual(payments.count, 2)
        XCTAssertTrue(payments.contains { $0.merchant == "咖啡店" && double($0.amount) == 38.50 })
        XCTAssertTrue(payments.contains { $0.merchant == "书店" && double($0.amount) == 66.00 })
    }

    func testWeChatBillListTextParsesAllVisibleRows() throws {
        let referenceDate = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 6, hour: 22)))
        let payments = PaymentTextParser.parseAll(
            """
            账单
            全部账单
            查找交易
            2026年6月
            生活缴费
            6月6日 10:24
            -55.10
            上海耀汇充科技有限公司-退款
            6月5日 22:49
            +86.59
            上海耀汇充科技有限公司
            6月5日 22:19
            -99.00
            已退款(¥86.59)
            城置美宿
            6月3日 00:17
            -4842.00
            """,
            preferredChannel: .wechat,
            referenceDate: referenceDate
        )

        XCTAssertEqual(payments.count, 4)
        XCTAssertTrue(payments.contains { $0.merchant == "生活缴费" && double($0.amount) == 55.10 })
        XCTAssertTrue(payments.contains { $0.merchant == "上海耀汇充科技有限公司-退款" && double($0.amount) == 86.59 })
        XCTAssertTrue(payments.contains { $0.merchant == "上海耀汇充科技有限公司" && double($0.amount) == 99.00 })
        XCTAssertTrue(payments.contains { $0.merchant == "城置美宿" && double($0.amount) == 4842.00 })
    }

    func testAlipayBillListTextKeepsUnsignedIncomeRows() throws {
        let referenceDate = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 23, hour: 22)))
        let payments = PaymentTextParser.parseAll(
            """
            搜索交易记录
            收支分析
            5月
            大润发（长阳店）
            日用百货
            今天 21:24
            -134.32
            余额宝-收益发放
            投资理财
            今天 03:49
            0.29
            成都你六姐上海长阳合乐里店
            餐饮美食
            昨天 20:20
            2.00
            退款
            """,
            preferredChannel: .alipay,
            referenceDate: referenceDate
        )

        XCTAssertEqual(payments.count, 3)
        XCTAssertTrue(payments.contains { $0.merchant.contains("大润发") && double($0.amount) == 134.32 })
        XCTAssertTrue(payments.contains { $0.merchant.contains("余额宝") && double($0.amount) == 0.29 })
        XCTAssertTrue(payments.contains { $0.merchant.contains("成都你六姐") && double($0.amount) == 2.00 })
        XCTAssertEqual(payments.first(where: { $0.merchant.contains("大润发") })?.categoryRaw, "日用百货")
        XCTAssertEqual(payments.first(where: { $0.merchant.contains("成都你六姐") })?.categoryRaw, "餐饮美食")
        XCTAssertEqual(payments.first(where: { $0.merchant.contains("余额宝") })?.categoryRaw, "投资理财")
    }

    func testAlipayBillListPreservesPlatformCategoryForReview() throws {
        let referenceDate = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 23, hour: 22)))
        let payments = PaymentTextParser.parseAll(
            """
            搜索交易记录
            收支分析
            5月
            Apple Store
            数码电器
            今天 16:08
            -8999.00
            """,
            preferredChannel: .alipay,
            referenceDate: referenceDate
        )

        let payment = try XCTUnwrap(payments.first)
        XCTAssertEqual(payment.channel, .alipay)
        XCTAssertEqual(payment.category, .shopping)
        XCTAssertEqual(payment.categoryRaw, "数码电器")
        XCTAssertEqual(double(payment.amount), 8999.0, accuracy: 0.001)
    }

    func testAlipayTencentOCRStyleRowsUseForwardCategoryAndVisibleDate() throws {
        let referenceDate = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 7, hour: 16)))
        let payments = PaymentTextParser.parseAll(
            """
            搜索交易记录
            收支分析
            5
            月
            ETC通行费
            -67.06
            爱车养车
            自动扣款成功
            05-31 21:50
            国际会议中心洲际酒店
            -1,000.00
            酒店旅游
            已全额退款
            05-31 19:27
            """,
            preferredChannel: .alipay,
            referenceDate: referenceDate
        )

        let calendar = Calendar(identifier: .gregorian)
        let etcPayment = try XCTUnwrap(payments.first { $0.merchant == "ETC通行费" })
        XCTAssertEqual(etcPayment.categoryRaw, "爱车养车")
        XCTAssertEqual(calendar.component(.year, from: try XCTUnwrap(etcPayment.occurredAt)), 2026)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(etcPayment.occurredAt)), 5)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(etcPayment.occurredAt)), 31)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(etcPayment.occurredAt)), 21)
        XCTAssertEqual(calendar.component(.minute, from: try XCTUnwrap(etcPayment.occurredAt)), 50)

        let hotelPayment = try XCTUnwrap(payments.first { $0.merchant == "国际会议中心洲际酒店" })
        XCTAssertEqual(hotelPayment.categoryRaw, "酒店旅游")
        XCTAssertEqual(double(hotelPayment.amount), 1000.0, accuracy: 0.001)
    }

    func testStructuredPayloadCorrectsHallucinatedYearWhenRawTextHasOnlyMonthDay() throws {
        let referenceDate = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 7, hour: 16)))
        let payments = PaymentTextParser.parseAll(
            """
            {"source":"支付宝","payments":[
            {"merchant":"ETC通行费","amount":"-67.06","channel":"支付宝","category":"爱车养车","occurredAt":"2024-05-31 21:50","rawText":"ETC通行费\\n爱车养车\\n05-31 21:50\\n-67.06"}
            ]}
            """,
            preferredChannel: .alipay,
            referenceDate: referenceDate
        )

        let payment = try XCTUnwrap(payments.first)
        let occurredAt = try XCTUnwrap(payment.occurredAt)
        let calendar = Calendar(identifier: .gregorian)
        XCTAssertEqual(calendar.component(.year, from: occurredAt), 2026)
        XCTAssertEqual(calendar.component(.month, from: occurredAt), 5)
        XCTAssertEqual(calendar.component(.day, from: occurredAt), 31)
        XCTAssertEqual(calendar.component(.hour, from: occurredAt), 21)
        XCTAssertEqual(calendar.component(.minute, from: occurredAt), 50)
    }

    func testTencentOCRTextRepairSortsTextByVisualRows() {
        let text = TencentOCRTextRepair.repairedText(
            from: [
                TencentOCRTextDetection(text: "-67.06", centerX: 850, centerY: 300),
                TencentOCRTextDetection(text: "05-31 21:50", centerX: 220, centerY: 380),
                TencentOCRTextDetection(text: "爱车养车", centerX: 220, centerY: 340),
                TencentOCRTextDetection(text: "ETC通行费", centerX: 220, centerY: 300),
                TencentOCRTextDetection(text: "国际会议中心洲际酒店", centerX: 220, centerY: 440),
                TencentOCRTextDetection(text: "-1,000.00", centerX: 850, centerY: 440)
            ]
        )

        XCTAssertEqual(
            text.components(separatedBy: .newlines).prefix(6).joined(separator: "|"),
            "ETC通行费|-67.06|爱车养车|05-31 21:50|国际会议中心洲际酒店|-1,000.00"
        )
    }

    func testWeChatBillListAutoSelectsWechatParser() throws {
        let referenceDate = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 6, hour: 22)))
        let payments = PaymentTextParser.parseAll(
            """
            账单
            全部账单
            查找交易
            2026年6月
            生活缴费
            6月6日 10:24
            -55.10
            群收款-来自何忠恒
            6月5日 13:02
            +187.80
            """,
            referenceDate: referenceDate
        )

        XCTAssertEqual(payments.count, 2)
        XCTAssertTrue(payments.allSatisfy { $0.channel == .wechat })
        XCTAssertTrue(payments.contains { $0.merchant.contains("群收款") && double($0.amount) == 187.80 })
    }

    func testPaymentScreenshotFixturesUseStructuredRecognitionExpectations() async throws {
        for fixture in PaymentScreenshotFixture.all {
            let imageURL = try XCTUnwrap(fixtureImageURL(named: fixture.filename), "Missing fixture \(fixture.filename)")
            let image = try XCTUnwrap(UIImage(contentsOfFile: imageURL.path), "Unreadable fixture \(fixture.filename)")
            let payments = try await ReceiptImageParser.parseAll(
                image: image,
                preferredChannel: fixture.channel,
                providers: [
                    StubReceiptOCRProvider(result: .success([
                        ReceiptOCRTextCandidate(source: "fixture-glm", text: fixture.structuredPayload)
                    ]))
                ]
            )

            XCTAssertGreaterThanOrEqual(payments.count, fixture.minimumCount, fixture.filename)
            XCTAssertGreaterThanOrEqual(
                payments.filter { $0.merchantLogoPNGData != nil }.count,
                min(2, fixture.minimumCount),
                "Expected structured import to attach merchant logos for \(fixture.filename)"
            )
            let calendar = Calendar(identifier: .gregorian)
            for expected in fixture.expectedPayments {
                XCTAssertTrue(
                    payments.contains {
                        $0.merchant.contains(expected.merchantFragment)
                            && abs(double($0.amount) - expected.amount) < 0.001
                            && $0.channel == fixture.channel
                            && expected.matchesCategory($0)
                            && expected.matchesTime($0, calendar: calendar)
                    },
                    "Expected \(expected.debugDescription) in \(fixture.filename), got \(payments.map { "\($0.merchant):\($0.amount):\($0.categoryRaw):\($0.occurredAt?.description ?? "nil")" })"
                )
            }
        }
    }

    func testPaymentScreenshotFixturesExtractMerchantLogoData() throws {
        for fixture in PaymentScreenshotFixture.all {
            let imageURL = try XCTUnwrap(fixtureImageURL(named: fixture.filename), "Missing fixture \(fixture.filename)")
            let image = try XCTUnwrap(UIImage(contentsOfFile: imageURL.path), "Unreadable fixture \(fixture.filename)")
            let logos = ReceiptImageSegmenter.merchantLogoData(
                from: image.awemeBillingPreparedForOCR(),
                preferredChannel: fixture.channel
            )

            XCTAssertGreaterThanOrEqual(logos.count, min(2, fixture.minimumCount), fixture.filename)
            XCTAssertTrue(logos.allSatisfy { $0.count > 300 }, fixture.filename)
        }
    }

    func testLatestAlipayScreenshotExtractsVisibleMerchantLogosWhenAvailable() throws {
        let imageURL = URL(fileURLWithPath: "/Users/augustus/Downloads/IMG_5121.PNG")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: imageURL.path), "Current user screenshot is not available")
        let image = try XCTUnwrap(UIImage(contentsOfFile: imageURL.path))
        let logos = ReceiptImageSegmenter.merchantLogoData(
            from: image.awemeBillingPreparedForOCR(),
            preferredChannel: .alipay
        )

        XCTAssertGreaterThanOrEqual(logos.count, 4)
        XCTAssertTrue(logos.allSatisfy { $0.count > 300 })
    }

    @MainActor
    func testImportPipelineStagesPendingAndDuplicateCandidates() throws {
        let context = try makeInMemoryContext()
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 26, hour: 9, minute: 30)))
        let payment = ParsedPayment(
            amount: 18.5,
            merchant: "早餐店",
            channel: .wechat,
            note: "微信支付 18.50 元",
            occurredAt: date,
            category: .dining
        )

        let candidates = ImportPipeline.createBatch(
            source: .paste,
            rawText: "微信支付 18.50 元",
            payments: [payment, payment],
            scene: "文本解析",
            context: context
        )

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.filter { $0.status == .pendingReview }.count, 1)
        XCTAssertEqual(candidates.filter { $0.status == .duplicate }.count, 1)

        let batch = try XCTUnwrap(try context.fetch(FetchDescriptor<ImportBatch>()).first)
        XCTAssertEqual(batch.status, .pendingReview)
        XCTAssertEqual(batch.duplicateCount, 1)
    }

    @MainActor
    func testImportPipelinePreservesMerchantLogoDataThroughAcceptance() throws {
        let context = try makeInMemoryContext()
        let logoData = makeTestLogoPNGData()
        let payment = ParsedPayment(
            amount: 50,
            merchant: "澳白JPBAKERY",
            channel: .alipay,
            note: "截图解析",
            occurredAt: Date(timeIntervalSince1970: 1_769_184_000),
            category: .dining,
            merchantLogoPNGData: logoData
        )

        let candidates = ImportPipeline.createBatch(
            source: .screenshot,
            rawText: payment.note,
            payments: [payment],
            scene: "截图解析",
            context: context
        )
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.merchantLogoPNGData, logoData)

        let record = try XCTUnwrap(ImportPipeline.accept(candidate, context: context))
        XCTAssertEqual(record.merchantLogoPNGData, logoData)
    }

    @MainActor
    func testImportPipelineAcceptsCandidateOnceAndUpdatesBatch() throws {
        let context = try makeInMemoryContext()
        let candidate = try XCTUnwrap(makeSingleCandidate(in: context))

        let record = try XCTUnwrap(ImportPipeline.accept(candidate, context: context))
        try context.save()

        XCTAssertEqual(record.merchant, "咖啡店")
        XCTAssertEqual(record.channel, .alipay)
        XCTAssertEqual(candidate.status, .accepted)
        XCTAssertNil(ImportPipeline.accept(candidate, context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExpenseRecord>()).count, 1)

        let batch = try XCTUnwrap(try context.fetch(FetchDescriptor<ImportBatch>()).first)
        XCTAssertEqual(batch.status, .accepted)
        XCTAssertEqual(batch.acceptedCount, 1)
    }

    @MainActor
    func testImportPipelineIgnoreUpdatesBatchWithoutCreatingRecord() throws {
        let context = try makeInMemoryContext()
        let candidate = try XCTUnwrap(makeSingleCandidate(in: context))

        ImportPipeline.ignore(candidate, context: context)
        try context.save()

        XCTAssertEqual(candidate.status, .ignored)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExpenseRecord>()).count, 0)

        let batch = try XCTUnwrap(try context.fetch(FetchDescriptor<ImportBatch>()).first)
        XCTAssertEqual(batch.status, .ignored)
    }

    @MainActor
    func testManualExpenseImportCreatesRecord() async throws {
        let context = try makeInMemoryContext()
        let occurredAt = Date(timeIntervalSince1970: 1_769_184_000)
        let draft = ManualExpenseDraft(
            amount: 68.8,
            merchant: "  手动咖啡店  ",
            categoryRaw: ExpenseCategory.dining.rawValue,
            scene: "",
            channel: .wechat,
            note: "手动补录",
            occurredAt: occurredAt
        )

        let result = await ManualExpenseImportService.save(
            draft: draft,
            context: context,
            refreshAfterSave: false
        )

        guard case .created(let record) = result else {
            return XCTFail("Expected manual import to create a record")
        }
        XCTAssertEqual(record.merchant, "手动咖啡店")
        XCTAssertEqual(record.scene, ExpenseCategory.dining.rawValue)
        XCTAssertEqual(record.channel, .wechat)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExpenseRecord>()).count, 1)
    }

    @MainActor
    func testManualExpenseImportRejectsDuplicateRecord() async throws {
        let context = try makeInMemoryContext()
        let occurredAt = Date(timeIntervalSince1970: 1_769_184_000)
        let draft = ManualExpenseDraft(
            amount: 68.8,
            merchant: "手动咖啡店",
            categoryRaw: ExpenseCategory.dining.rawValue,
            scene: "早餐",
            channel: .wechat,
            note: "",
            occurredAt: occurredAt
        )

        _ = await ManualExpenseImportService.save(
            draft: draft,
            context: context,
            refreshAfterSave: false
        )
        let duplicate = await ManualExpenseImportService.save(
            draft: draft,
            context: context,
            refreshAfterSave: false
        )

        guard case .duplicate = duplicate else {
            return XCTFail("Expected duplicate manual import to be rejected")
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExpenseRecord>()).count, 1)
    }

    @MainActor
    func testManualExpenseImportPreservesCustomCategory() async throws {
        let context = try makeInMemoryContext()
        let draft = ManualExpenseDraft(
            amount: 26,
            merchant: "小区咖啡",
            categoryRaw: "咖啡",
            scene: "",
            channel: .wechat,
            note: "",
            occurredAt: Date(timeIntervalSince1970: 1_769_184_000)
        )

        let result = await ManualExpenseImportService.save(
            draft: draft,
            context: context,
            refreshAfterSave: false
        )

        guard case .created(let record) = result else {
            return XCTFail("Expected manual import to create a custom-category record")
        }
        XCTAssertEqual(record.categoryRaw, "咖啡")
        XCTAssertEqual(record.scene, "咖啡")
        XCTAssertEqual(record.category, .other)
    }

    @MainActor
    func testCategoryCatalogSeedsDefaultsAndRejectsDuplicateNames() throws {
        let context = try makeInMemoryContext()
        let profiles = ExpenseCategoryCatalog.ensureDefaults(profiles: [], context: context)

        XCTAssertEqual(profiles.count, ExpenseCategory.allCases.count)
        XCTAssertFalse(ExpenseCategoryCatalog.canCreate(" 餐饮 ", in: profiles))
        XCTAssertTrue(ExpenseCategoryCatalog.canCreate("咖啡", in: profiles))
    }

    @MainActor
    func testBuiltInCategoryRenameDoesNotRecreateDefaultName() throws {
        let context = try makeInMemoryContext()
        let profiles = ExpenseCategoryCatalog.ensureDefaults(profiles: [], context: context)
        let dining = try XCTUnwrap(profiles.first { $0.semanticRawName == ExpenseCategory.dining.rawValue })
        dining.name = "吃饭"
        try context.save()

        let refreshed = ExpenseCategoryCatalog.ensureDefaults(profiles: profiles, context: context)

        XCTAssertEqual(refreshed.filter(\.isBuiltIn).count, ExpenseCategory.allCases.count)
        XCTAssertFalse(refreshed.contains { $0.name == ExpenseCategory.dining.rawValue })
        XCTAssertEqual(
            ExpenseCategoryCatalog.displayName(forSemanticRawName: ExpenseCategory.dining.rawValue, in: refreshed),
            "吃饭"
        )
        XCTAssertFalse(ExpenseCategoryCatalog.canCreate("餐饮", in: refreshed))
    }

    @MainActor
    func testImportPipelineMapsBuiltInSemanticCategoryToRenamedDisplayName() throws {
        let context = try makeInMemoryContext()
        let profiles = ExpenseCategoryCatalog.ensureDefaults(profiles: [], context: context)
        let dining = try XCTUnwrap(profiles.first { $0.semanticRawName == ExpenseCategory.dining.rawValue })
        dining.name = "吃饭"
        try context.save()

        let payment = ParsedPayment(
            amount: 38.5,
            merchant: "咖啡店",
            channel: .alipay,
            note: "",
            occurredAt: Date(timeIntervalSince1970: 1_769_184_000),
            category: .dining,
            categoryRaw: ExpenseCategory.dining.rawValue
        )

        let candidates = ImportPipeline.createBatch(
            source: .paste,
            rawText: "支付宝通知：你向咖啡店支付 38.50 元",
            payments: [payment],
            scene: "",
            context: context
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.categoryRaw, "吃饭")
        XCTAssertEqual(candidate.scene, "吃饭")
    }

    func testOCRRecognitionStatisticsCountsProviderResults() throws {
        let suiteName = "AwemeBilling.OCRStats.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            OCRRecognitionStatistics.reset(defaults: defaults)
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        OCRRecognitionStatistics.reset(defaults: defaults)
        OCRRecognitionStatistics.recordAttempt(.glm, defaults: defaults)
        OCRRecognitionStatistics.recordRecognitionSuccess(.glm, defaults: defaults)
        OCRRecognitionStatistics.recordParsedSuccess(.glm, defaults: defaults)
        OCRRecognitionStatistics.recordAttempt(.tencent, defaults: defaults)
        OCRRecognitionStatistics.recordFailure(.tencent, defaults: defaults)

        let snapshot = OCRRecognitionStatistics.snapshot(defaults: defaults)
        let glm = try XCTUnwrap(snapshot.first { $0.provider == .glm })
        let tencent = try XCTUnwrap(snapshot.first { $0.provider == .tencent })
        XCTAssertEqual(glm.attempts, 1)
        XCTAssertEqual(glm.recognitionSuccesses, 1)
        XCTAssertEqual(glm.parsedSuccesses, 1)
        XCTAssertEqual(glm.failures, 0)
        XCTAssertEqual(tencent.attempts, 1)
        XCTAssertEqual(tencent.failures, 1)
    }

    @MainActor
    private func makeSingleCandidate(in context: ModelContext) -> ParsedPaymentCandidate? {
        let payment = ParsedPayment(
            amount: 38.5,
            merchant: "咖啡店",
            channel: .alipay,
            note: "支付宝通知：你向咖啡店支付 38.50 元",
            occurredAt: Date(timeIntervalSince1970: 1_769_184_000),
            category: .dining
        )
        return ImportPipeline.createBatch(
            source: .paste,
            rawText: payment.note,
            payments: [payment],
            scene: "文本解析",
            context: context
        ).first
    }

    @MainActor
    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            ExpenseRecord.self,
            ExpenseCategoryProfile.self,
            ArchiveSchedule.self,
            ArchiveReport.self,
            ImportBatch.self,
            ParsedPaymentCandidate.self,
            PaymentRule.self,
            BudgetPlan.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func double(_ amount: Decimal) -> Double {
        (amount as NSDecimalNumber).doubleValue
    }

    private func relativeLuminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private func makeTestLogoPNGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        return renderer.image { context in
            UIColor.systemOrange.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 8, y: 7, width: 8, height: 10))
        }.pngData() ?? Data([0x89, 0x50, 0x4e, 0x47])
    }

    private func fixtureImageURL(named filename: String) -> URL? {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let appRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return appRoot.appendingPathComponent(filename)
    }
}

private enum StubReceiptOCRError: Error {
    case failed
}

private struct StubReceiptOCRProvider: ReceiptOCRProvider {
    let result: Result<[ReceiptOCRTextCandidate], Error>

    var displayName: String { "stub" }

    func recognizeTextCandidates(from image: UIImage, preferredChannel: PaymentChannel?) async throws -> [ReceiptOCRTextCandidate] {
        try result.get()
    }
}

private struct PaymentScreenshotFixture {
    let filename: String
    let channel: PaymentChannel
    let minimumCount: Int
    let expectedPayments: [ExpectedPayment]
    let structuredPayload: String

    static let all: [PaymentScreenshotFixture] = [
        PaymentScreenshotFixture(
            filename: "支付宝消费.PNG",
            channel: .alipay,
            minimumCount: 6,
            expectedPayments: [
                ExpectedPayment("大润发", 134.32),
                ExpectedPayment("中海环宇城MAX停车场", 10.00),
                ExpectedPayment("上海真如山姆会员店", 277.97),
                ExpectedPayment("余额宝", 0.29),
                ExpectedPayment("成都你六姐", 84.65)
            ],
            structuredPayload: """
            {"source":"支付宝","payments":[
            {"merchant":"大润发（长阳店）","amount":"-134.32","channel":"支付宝","category":"购物","occurredAt":"2026-05-23 21:24","note":"日用百货"},
            {"merchant":"沪AH96185-中海环宇城MAX停车场","amount":"-10.00","channel":"支付宝","category":"交通","occurredAt":"2026-05-23 20:15","note":"爱车养车"},
            {"merchant":"上海真如山姆会员店","amount":"-277.97","channel":"支付宝","category":"购物","occurredAt":"2026-05-23 19:03","note":"日用百货"},
            {"merchant":"余额宝-收益发放","amount":"0.29","channel":"支付宝","category":"转账","occurredAt":"2026-05-23 03:49","note":"投资理财 收入"},
            {"merchant":"成都你六姐上海长阳合乐里店","amount":"2.00","channel":"支付宝","category":"餐饮","occurredAt":"2026-05-22 20:20","note":"退款"},
            {"merchant":"成都你六姐上海长阳合乐里店","amount":"-84.65","channel":"支付宝","category":"餐饮","occurredAt":"2026-05-22 20:12","note":"已退款(¥2.00)"}
            ]}
            """
        ),
        PaymentScreenshotFixture(
            filename: "支付宝消费1.PNG",
            channel: .alipay,
            minimumCount: 6,
            expectedPayments: [
                ExpectedPayment("成都你六姐", 56.37),
                ExpectedPayment("上海申创智停车场", 20.00),
                ExpectedPayment("大米先生", 37.70),
                ExpectedPayment("余额宝", 0.24),
                ExpectedPayment("停车费用", 17.50)
            ],
            structuredPayload: """
            {"source":"支付宝","payments":[
            {"merchant":"成都你六姐上海长阳合乐里店","amount":"-56.37","channel":"支付宝","category":"餐饮","occurredAt":"2026-05-23 20:46","note":"餐饮美食"},
            {"merchant":"上海申创智停车场","amount":"-20.00","channel":"支付宝","category":"交通","occurredAt":"2026-05-23 15:03","note":"爱车养车"},
            {"merchant":"大米先生新鲜现炒（长阳创谷店）","amount":"-37.70","channel":"支付宝","category":"娱乐","occurredAt":"2026-05-23 11:48","note":"文化休闲"},
            {"merchant":"余额宝-收益发放","amount":"0.24","channel":"支付宝","category":"转账","occurredAt":"2026-05-23 03:43","note":"投资理财 收入"},
            {"merchant":"余额宝-收益发放","amount":"0.24","channel":"支付宝","category":"转账","occurredAt":"2026-05-22 03:34","note":"投资理财 收入"},
            {"merchant":"停车费用","amount":"-17.50","channel":"支付宝","category":"交通","occurredAt":"2026-05-22 21:16","note":"底部可见记录"}
            ]}
            """
        ),
        PaymentScreenshotFixture(
            filename: "支付宝消费2.PNG",
            channel: .alipay,
            minimumCount: 6,
            expectedPayments: [
                ExpectedPayment("分配车位缴费", 1200.00),
                ExpectedPayment("美团", 161.00),
                ExpectedPayment("扫码收钱码付款", 191.00),
                ExpectedPayment("余额宝", 0.29),
                ExpectedPayment("成都你六姐", 84.65)
            ],
            structuredPayload: """
            {"source":"支付宝","payments":[
            {"merchant":"成都你六姐上海长阳合乐里店","amount":"-84.65","channel":"支付宝","category":"餐饮","occurredAt":"2026-05-22 20:12","note":"已退款(¥2.00)"},
            {"merchant":"美团","amount":"-161.00","channel":"支付宝","category":"餐饮","occurredAt":"2026-05-22 12:28","note":"餐饮美食"},
            {"merchant":"分配车位缴费-姜徐彬-季付","amount":"-1200.00","channel":"支付宝","category":"交通","occurredAt":"2026-05-22 09:18","note":"充值缴费"},
            {"merchant":"余额宝-收益发放","amount":"0.29","channel":"支付宝","category":"转账","occurredAt":"2026-05-22 03:41","note":"投资理财 收入"},
            {"merchant":"扫码收钱码付款-给。","amount":"-191.00","channel":"支付宝","category":"其他","occurredAt":"2026-05-22 21:11","note":"商业服务"},
            {"merchant":"美团","amount":"98.00","channel":"支付宝","category":"转账","occurredAt":"2026-05-22 21:11","note":"退款"}
            ]}
            """
        ),
        PaymentScreenshotFixture(
            filename: "微信消费.PNG",
            channel: .wechat,
            minimumCount: 9,
            expectedPayments: [
                ExpectedPayment("秦碗会", 146.20),
                ExpectedPayment("上海寓筱", 4.00),
                ExpectedPayment("上海耀汇充科技有限公司", 99.67),
                ExpectedPayment("群收款", 187.80),
                ExpectedPayment("生活缴费", 16.20)
            ],
            structuredPayload: """
            {"source":"微信支付","payments":[
            {"merchant":"秦碗会（中海环宇城）","amount":"-146.20","channel":"微信支付","category":"餐饮","occurredAt":"2026-05-24 19:31","note":"原金额146.50"},
            {"merchant":"上海寓筱商务咨询有限公司","amount":"-4.00","channel":"微信支付","category":"其他","occurredAt":"2026-05-22 21:21","note":""},
            {"merchant":"上海耀汇充科技有限公司-退款","amount":"+78.55","channel":"微信支付","category":"转账","occurredAt":"2026-05-21 23:48","note":"退款"},
            {"merchant":"上海耀汇充科技有限公司","amount":"-99.67","channel":"微信支付","category":"交通","occurredAt":"2026-05-21 23:12","note":"已退款(¥78.55) 原金额100.00"},
            {"merchant":"美团","amount":"-1.50","channel":"微信支付","category":"餐饮","occurredAt":"2026-05-21 14:12","note":""},
            {"merchant":"群收款-来自何忠恒","amount":"+187.80","channel":"微信支付","category":"转账","occurredAt":"2026-05-21 13:02","note":"群收款"},
            {"merchant":"生活缴费","amount":"-16.20","channel":"微信支付","category":"居家","occurredAt":"2026-05-21 09:01","note":""},
            {"merchant":"上海耀汇充科技有限公司-退款","amount":"+85.63","channel":"微信支付","category":"转账","occurredAt":"2026-05-20 00:10","note":"退款"},
            {"merchant":"上海耀汇充科技有限公司","amount":"-100.00","channel":"微信支付","category":"交通","occurredAt":"2026-05-19 23:35","note":"已退款(¥85.63)"}
            ]}
            """
        ),
        PaymentScreenshotFixture(
            filename: "微信消费2.PNG",
            channel: .wechat,
            minimumCount: 8,
            expectedPayments: [
                ExpectedPayment("生活缴费", 55.10),
                ExpectedPayment("城置美宿", 4842.00),
                ExpectedPayment("上海耀汇充科技有限公司", 99.00),
                ExpectedPayment("美团平台商户", 188.30)
            ],
            structuredPayload: """
            {"source":"微信支付","payments":[
            {"merchant":"生活缴费","amount":"-55.10","channel":"微信支付","category":"居家","occurredAt":"2026-06-06 10:24","note":""},
            {"merchant":"上海耀汇充科技有限公司-退款","amount":"+86.59","channel":"微信支付","category":"转账","occurredAt":"2026-06-05 22:49","note":"退款"},
            {"merchant":"上海耀汇充科技有限公司","amount":"-99.00","channel":"微信支付","category":"交通","occurredAt":"2026-06-05 22:19","note":"已退款(¥86.59) 原金额100.00"},
            {"merchant":"城置美宿","amount":"-499.89","channel":"微信支付","category":"旅行","occurredAt":"2026-06-05 09:16","note":"原金额500.00"},
            {"merchant":"城置美宿","amount":"-4842.00","channel":"微信支付","category":"旅行","occurredAt":"2026-06-03 00:17","note":""},
            {"merchant":"上海耀汇充科技有限公司-退款","amount":"+74.32","channel":"微信支付","category":"转账","occurredAt":"2026-06-02 23:43","note":"退款"},
            {"merchant":"上海耀汇充科技有限公司","amount":"-100.00","channel":"微信支付","category":"交通","occurredAt":"2026-06-02 23:04","note":"已退款(¥74.32)"},
            {"merchant":"美团平台商户","amount":"-188.30","channel":"微信支付","category":"餐饮","occurredAt":"2026-05-31 20:54","note":"原金额189.00"}
            ]}
            """
        ),
        PaymentScreenshotFixture(
            filename: "支付宝消费3.PNG",
            channel: .alipay,
            minimumCount: 4,
            expectedPayments: [
                ExpectedPayment("C河间门市-pos1", 14.35, categoryRaw: "日用百货", year: 2026, day: 7, hour: 13, minute: 38),
                ExpectedPayment("美团", 221.00, categoryRaw: "餐饮美食", year: 2026, day: 7, hour: 12, minute: 34),
                ExpectedPayment("余额宝", 0.39, categoryRaw: "投资理财", year: 2026, day: 7, hour: 3, minute: 50),
                ExpectedPayment("余额宝", 0.39, categoryRaw: "投资理财", year: 2026, day: 6, hour: 3, minute: 40)
            ],
            structuredPayload: """
            {"source":"支付宝","payments":[
            {"merchant":"C河间门市-pos1","amount":"-14.35","channel":"支付宝","category":"日用百货","occurredAt":"2026-06-07 13:38","note":"支付宝列表记录","rawText":"C河间门市-pos1\\n日用百货\\n今天 13:38\\n-14.35"},
            {"merchant":"美团","amount":"-221.00","channel":"支付宝","category":"餐饮美食","occurredAt":"2026-06-07 12:34","note":"支付宝列表记录","rawText":"美团\\n餐饮美食\\n今天 12:34\\n-221.00"},
            {"merchant":"余额宝-收益发放","amount":"0.39","channel":"支付宝","category":"投资理财","occurredAt":"2026-06-07 03:50","note":"收益发放","rawText":"余额宝-收益发放\\n投资理财\\n今天 03:50\\n0.39"},
            {"merchant":"余额宝-收益发放","amount":"0.39","channel":"支付宝","category":"投资理财","occurredAt":"2026-06-06 03:40","note":"收益发放","rawText":"余额宝-收益发放\\n投资理财\\n昨天 03:40\\n0.39"}
            ]}
            """
        ),
        PaymentScreenshotFixture(
            filename: "支付宝消费4.PNG",
            channel: .alipay,
            minimumCount: 5,
            expectedPayments: [
                ExpectedPayment("ETC通行费", 67.06, categoryRaw: "爱车养车", year: 2026, day: 31, hour: 21, minute: 50),
                ExpectedPayment("国际会议中心洲际酒店", 1000.00, categoryRaw: "酒店旅游", year: 2026, day: 31, hour: 19, minute: 27),
                ExpectedPayment("1132546154575516", 87.50, categoryRaw: "酒店旅游", year: 2026, day: 31, hour: 16, minute: 14),
                ExpectedPayment("余额宝", 0.26, categoryRaw: "投资理财", year: 2026, day: 31, hour: 3, minute: 34),
                ExpectedPayment("付款", 252.70, categoryRaw: "爱车养车", year: 2026, day: 30, hour: 14, minute: 57)
            ],
            structuredPayload: """
            {"source":"支付宝","payments":[
            {"merchant":"ETC通行费","amount":"-67.06","channel":"支付宝","category":"爱车养车","occurredAt":"2024-05-31 21:50","note":"自动扣款成功","rawText":"ETC通行费\\n爱车养车\\n05-31 21:50\\n-67.06"},
            {"merchant":"国际会议中心洲际酒店","amount":"-1000.00","channel":"支付宝","category":"酒店旅游","occurredAt":"2024-05-31 19:27","note":"已全额退款","rawText":"国际会议中心洲际酒店\\n酒店旅游\\n05-31 19:27\\n-1,000.00\\n已全额退款"},
            {"merchant":"1132546154575516","amount":"-87.50","channel":"支付宝","category":"酒店旅游","occurredAt":"2024-05-31 16:14","note":"","rawText":"1132546154575516\\n酒店旅游\\n05-31 16:14\\n-87.50"},
            {"merchant":"余额宝-收益发放","amount":"0.26","channel":"支付宝","category":"投资理财","occurredAt":"2024-05-31 03:34","note":"收益发放","rawText":"余额宝-收益发放\\n投资理财\\n05-31 03:34\\n0.26"},
            {"merchant":"付款","amount":"-252.70","channel":"支付宝","category":"爱车养车","occurredAt":"2024-05-30 14:57","note":"","rawText":"付款\\n爱车养车\\n05-30 14:57\\n-252.70"}
            ]}
            """
        )
    ]
}

private struct ExpectedPayment {
    let merchantFragment: String
    let amount: Double
    let categoryRaw: String?
    let year: Int?
    let day: Int?
    let hour: Int?
    let minute: Int?

    init(
        _ merchantFragment: String,
        _ amount: Double,
        categoryRaw: String? = nil,
        year: Int? = nil,
        day: Int? = nil,
        hour: Int? = nil,
        minute: Int? = nil
    ) {
        self.merchantFragment = merchantFragment
        self.amount = amount
        self.categoryRaw = categoryRaw
        self.year = year
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    var debugDescription: String {
        [merchantFragment, "\(amount)", categoryRaw ?? "", year.map(String.init) ?? "", hour.map { "\($0):\(minute ?? 0)" } ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func matchesCategory(_ payment: ParsedPayment) -> Bool {
        guard let categoryRaw else { return true }
        return payment.categoryRaw == categoryRaw
    }

    func matchesTime(_ payment: ParsedPayment, calendar: Calendar) -> Bool {
        guard year != nil || day != nil || hour != nil || minute != nil else { return true }
        guard let occurredAt = payment.occurredAt else { return false }
        if let year, calendar.component(.year, from: occurredAt) != year { return false }
        if let day, calendar.component(.day, from: occurredAt) != day { return false }
        if let hour, calendar.component(.hour, from: occurredAt) != hour { return false }
        if let minute, calendar.component(.minute, from: occurredAt) != minute { return false }
        return true
    }
}
