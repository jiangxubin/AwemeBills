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
