import XCTest
import SwiftData
@testable import AwemeBillingApp

final class AwemeBillingCoreTests: XCTestCase {
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
    func testImportPipelineAcceptsCandidateOnceAndUpdatesBatch() throws {
        let context = try makeInMemoryContext()
        let candidate = try XCTUnwrap(makeSingleCandidate(in: context))

        let record = try XCTUnwrap(ImportPipeline.accept(candidate, context: context))
        try context.save()

        XCTAssertEqual(record.merchant, "咖啡店")
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
            category: .dining,
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
            category: .dining,
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
}
