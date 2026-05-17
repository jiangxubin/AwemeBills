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

        let record = ExpenseRecord(
            amount: Decimal(amount),
            merchant: cleanMerchant.isEmpty ? "未命名商户" : cleanMerchant,
            category: category,
            scene: cleanScene.isEmpty ? "快捷指令" : cleanScene,
            channel: channel,
            note: note,
            occurredAt: .now,
            isArchived: true
        )

        context.insert(record)
        try context.save()

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
    static var description = IntentDescription("从快捷指令传入支付 App 截图，自动 OCR 识别并归档消费。")
    static var openAppWhenRun = false

    @Parameter(title: "截图", requestValueDialog: "请选择要导入的消费截图。")
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("导入 \(\.$screenshot) 并归档消费")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let image = UIImage(data: screenshot.data) else {
            return .result(dialog: "这张图片无法读取，请换一张截图再试。")
        }

        let payments = try await ReceiptImageParser.parseAll(image: image)
        guard !payments.isEmpty else {
            return .result(dialog: "没有从截图里识别到可归档的消费。")
        }

        let context = ModelContext(DataController.sharedModelContainer)
        for payment in payments {
            let record = ExpenseRecord(
                amount: payment.amount,
                merchant: payment.merchant,
                category: payment.category,
                scene: "快捷指令截图导入",
                channel: payment.channel,
                note: payment.note,
                occurredAt: payment.occurredAt ?? .now,
                isArchived: true
            )
            context.insert(record)
        }
        try context.save()

        let total = payments.reduce(Decimal.zero) { $0 + $1.amount }
        return .result(dialog: "已归档 \(payments.count) 笔消费，共 \(BillingAnalytics.currency(total))。")
    }
}
