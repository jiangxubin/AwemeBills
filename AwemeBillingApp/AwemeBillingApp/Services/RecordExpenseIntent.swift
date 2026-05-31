import AppIntents
import Foundation
import SwiftData
import UIKit

struct RecordExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "记录消费"
    static var description = IntentDescription("把快捷指令、短信、邮件或 Apple Pay 自动化识别到的消费写入消费管家。")
    static var openAppWhenRun = false

    @Parameter(title: "金额", requestValueDialog: "消费金额是多少？")
    var amount: Double

    @Parameter(title: "商户", default: "未命名商户")
    var merchant: String

    @Parameter(title: "分类", default: .other)
    var category: ExpenseCategory

    @Parameter(title: "支付渠道", default: .other)
    var channel: PaymentChannel

    @Parameter(title: "消费场景", default: "快捷指令")
    var scene: String

    @Parameter(title: "备注", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("记录 \(\.$merchant) 的 \(\.$amount) 元消费")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            throw $amount.needsValueError("金额需要大于 0。")
        }

        let context = ModelContext(DataController.sharedModelContainer)
        let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanScene = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        let payment = ParsedPayment(
            amount: Decimal(amount),
            merchant: cleanMerchant.isEmpty ? "未命名商户" : cleanMerchant,
            channel: channel,
            note: note,
            occurredAt: .now,
            category: category
        )
        let candidates = ImportPipeline.createBatch(
            source: .shortcutURL,
            rawText: "\(payment.merchant) \(amount)",
            payments: [payment],
            scene: cleanScene.isEmpty ? "快捷指令" : cleanScene,
            context: context
        )

        guard let candidate = candidates.first, let record = ImportPipeline.accept(candidate, context: context) else {
            return .result(dialog: "这笔消费已经存在，未重复记录。")
        }

        try context.save()
        await ExpenseMutationService.refreshReportsAndNotifications(context: context)

        let amountText = BillingAnalytics.currency(record.amount)
        return .result(dialog: "已记录 \(record.merchant) \(amountText)。")
    }
}

enum AutomationTextImportService {
    struct Summary {
        let parsedCount: Int
        let acceptedCount: Int
        let duplicateCount: Int
        let pendingReviewCount: Int
        let totalAmount: Decimal

        var didParsePayments: Bool {
            parsedCount > 0
        }
    }

    private static let automaticAcceptThreshold = 0.84

    @MainActor
    static func importText(
        _ rawText: String,
        scene: String = "快捷指令自动化",
        context: ModelContext,
        refreshAfterAccept: Bool = true
    ) async -> Summary {
        let cleanText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            return Summary(parsedCount: 0, acceptedCount: 0, duplicateCount: 0, pendingReviewCount: 0, totalAmount: .zero)
        }

        let payments = PaymentTextParser.parseAll(cleanText)
        guard !payments.isEmpty else {
            return Summary(parsedCount: 0, acceptedCount: 0, duplicateCount: 0, pendingReviewCount: 0, totalAmount: .zero)
        }

        let candidates = ImportPipeline.createBatch(
            source: .shortcutURL,
            rawText: cleanText,
            payments: payments,
            scene: scene,
            context: context
        )

        var acceptedCount = 0
        var duplicateCount = candidates.filter { $0.status == .duplicate }.count
        var acceptedAmount = Decimal.zero

        for candidate in candidates where candidate.status == .pendingReview {
            guard candidate.confidence >= automaticAcceptThreshold else { continue }
            if let record = ImportPipeline.accept(candidate, context: context) {
                acceptedCount += 1
                acceptedAmount += record.amount
            } else {
                duplicateCount += 1
            }
        }

        try? context.save()

        if acceptedCount > 0, refreshAfterAccept {
            await ExpenseMutationService.refreshReportsAndNotifications(context: context)
        }

        let pendingReviewCount = candidates.filter { $0.status == .pendingReview }.count
        return Summary(
            parsedCount: payments.count,
            acceptedCount: acceptedCount,
            duplicateCount: duplicateCount,
            pendingReviewCount: pendingReviewCount,
            totalAmount: acceptedAmount
        )
    }
}

struct ImportExpenseTextIntent: AppIntent {
    static var title: LocalizedStringResource = "自动记录消费文本"
    static var description = IntentDescription("从短信、邮件、支付通知或快捷指令文本中识别消费，并自动写入消费管家。")
    static var openAppWhenRun = false

    @Parameter(title: "通知或账单文本", requestValueDialog: "请传入短信、邮件或支付通知文本。")
    var text: String

    @Parameter(title: "来源说明", default: "快捷指令自动化")
    var scene: String

    static var parameterSummary: some ParameterSummary {
        Summary("识别 \(\.$text) 并自动入账")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(DataController.sharedModelContainer)
        let summary = await AutomationTextImportService.importText(text, scene: scene, context: context)

        guard summary.didParsePayments else {
            return .result(dialog: "未识别出有效消费。请确认短信或邮件里包含金额和商户信息。")
        }

        if summary.acceptedCount == 0, summary.pendingReviewCount == 0 {
            return .result(dialog: "已识别 \(summary.parsedCount) 笔，但都已存在，未重复入账。")
        }

        let amountText = BillingAnalytics.currency(summary.totalAmount)
        if summary.pendingReviewCount > 0 {
            return .result(
                dialog: "已自动入账 \(summary.acceptedCount) 笔，共 \(amountText)；另有 \(summary.pendingReviewCount) 笔需要在消费管家复核。"
            )
        }

        if summary.duplicateCount > 0 {
            return .result(
                dialog: "已自动入账 \(summary.acceptedCount) 笔，共 \(amountText)，跳过 \(summary.duplicateCount) 笔重复记录。"
            )
        }

        return .result(dialog: "已自动入账 \(summary.acceptedCount) 笔，共 \(amountText)。")
    }
}

struct AwemeBillingShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordExpenseIntent(),
            phrases: [
                "用\(.applicationName)记录消费",
                "在\(.applicationName)记一笔账",
                "添加\(.applicationName)消费"
            ],
            shortTitle: "记录消费",
            systemImageName: "yensign.circle.fill"
        )

        AppShortcut(
            intent: ImportExpenseTextIntent(),
            phrases: [
                "用\(.applicationName)自动记录消费通知",
                "让\(.applicationName)识别消费短信",
                "让\(.applicationName)导入消费邮件"
            ],
            shortTitle: "自动入账",
            systemImageName: "text.badge.checkmark"
        )

        AppShortcut(
            intent: ImportExpenseScreenshotIntent(),
            phrases: [
                "用\(.applicationName)导入消费截图",
                "在\(.applicationName)归档消费截图",
                "让\(.applicationName)识别账单截图"
            ],
            shortTitle: "导入截图",
            systemImageName: "photo.badge.checkmark"
        )
    }
}

struct ImportExpenseScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "导入消费截图"
    static var description = IntentDescription("从快捷指令传入支付 App 截图，识别后生成待复核账单。")
    static var openAppWhenRun = true

    @Parameter(title: "截图", requestValueDialog: "请选择要导入的消费截图。")
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("导入 \(\.$screenshot) 并生成待复核账单")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let image = UIImage(data: screenshot.data) else {
            return .result(dialog: "这张图片无法读取，请换一张截图再试。")
        }

        let payments = try await ReceiptImageParser.parseAll(image: image)
        guard !payments.isEmpty else {
            return .result(dialog: "未识别出有效消费，请粘贴通知文本或手动记一笔。")
        }

        let context = ModelContext(DataController.sharedModelContainer)
        let rawText = payments.map(\.note).joined(separator: "\n---\n")
        let candidates = ImportPipeline.createBatch(
            source: .shortcutURL,
            rawText: rawText,
            payments: payments,
            scene: "快捷指令截图导入",
            context: context
        )
        try context.save()

        let pendingCount = candidates.filter { $0.status == .pendingReview }.count
        let skippedCount = candidates.count - pendingCount
        guard pendingCount > 0 else {
            return .result(dialog: "已识别 \(payments.count) 笔，但都已经存在，未重复导入。")
        }

        let dialog = skippedCount > 0
            ? "已生成 \(pendingCount) 笔待复核账单，跳过 \(skippedCount) 笔重复。"
            : "已生成 \(pendingCount) 笔待复核账单，请在消费管家确认入账。"
        return .result(dialog: "\(dialog)")
    }
}
