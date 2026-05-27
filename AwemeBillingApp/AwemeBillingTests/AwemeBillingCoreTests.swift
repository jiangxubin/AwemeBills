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
