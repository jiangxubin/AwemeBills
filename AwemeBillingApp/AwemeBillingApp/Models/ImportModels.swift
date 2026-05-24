import Foundation
import SwiftData

enum ImportSource: String, CaseIterable, Identifiable {
    case manual = "手动"
    case paste = "文本"
    case screenshot = "截图"
    case shareExtension = "分享"
    case csv = "CSV"
    case shortcutURL = "快捷指令"

    var id: String { rawValue }
}

enum ImportBatchStatus: String {
    case pendingReview = "待复核"
    case accepted = "已入账"
    case partial = "部分入账"
    case duplicate = "重复"
    case failed = "失败"
}

enum ParsedPaymentCandidateStatus: String {
    case pendingReview = "待复核"
    case accepted = "已入账"
    case ignored = "已忽略"
    case duplicate = "重复"
    case failed = "失败"
}

@Model
final class ImportBatch {
    @Attribute(.unique) var idString: String
    var sourceRaw: String
    var statusRaw: String
    var rawText: String
    var sourceFingerprint: String
    var parserVersion: String
    var createdAt: Date
    var acceptedCount: Int
    var duplicateCount: Int
    var failedCount: Int

    init(
        source: ImportSource,
        rawText: String,
        sourceFingerprint: String,
        parserVersion: String = "payment-parser-v2",
        status: ImportBatchStatus = .pendingReview,
        createdAt: Date = .now
    ) {
        self.idString = UUID().uuidString
        self.sourceRaw = source.rawValue
        self.statusRaw = status.rawValue
        self.rawText = rawText
        self.sourceFingerprint = sourceFingerprint
        self.parserVersion = parserVersion
        self.createdAt = createdAt
        self.acceptedCount = 0
        self.duplicateCount = 0
        self.failedCount = 0
    }

    var source: ImportSource {
        get { ImportSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var status: ImportBatchStatus {
        get { ImportBatchStatus(rawValue: statusRaw) ?? .pendingReview }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class ParsedPaymentCandidate {
    @Attribute(.unique) var idString: String
    var batchID: String
    var amount: Decimal
    var merchant: String
    var categoryRaw: String
    var scene: String
    var channelRaw: String
    var note: String
    var rawText: String
    var sourceFingerprint: String
    var confidence: Double
    var occurredAt: Date?
    var createdAt: Date
    var statusRaw: String

    init(
        batchID: String,
        payment: ParsedPayment,
        scene: String,
        rawText: String,
        sourceFingerprint: String,
        confidence: Double,
        status: ParsedPaymentCandidateStatus = .pendingReview,
        createdAt: Date = .now
    ) {
        self.idString = UUID().uuidString
        self.batchID = batchID
        self.amount = payment.amount
        self.merchant = payment.merchant
        self.categoryRaw = payment.category.rawValue
        self.scene = scene
        self.channelRaw = payment.channel.rawValue
        self.note = payment.note
        self.rawText = rawText
        self.sourceFingerprint = sourceFingerprint
        self.confidence = confidence
        self.occurredAt = payment.occurredAt
        self.createdAt = createdAt
        self.statusRaw = status.rawValue
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var channel: PaymentChannel {
        get { PaymentChannel(rawValue: channelRaw) ?? .other }
        set { channelRaw = newValue.rawValue }
    }

    var status: ParsedPaymentCandidateStatus {
        get { ParsedPaymentCandidateStatus(rawValue: statusRaw) ?? .pendingReview }
        set { statusRaw = newValue.rawValue }
    }

    var payment: ParsedPayment {
        ParsedPayment(
            amount: amount,
            merchant: merchant,
            channel: channel,
            note: note,
            occurredAt: occurredAt,
            category: category
        )
    }
}

@Model
final class PaymentRule {
    var title: String
    var pattern: String
    var matchFieldRaw: String
    var channelRaw: String
    var categoryRaw: String
    var scene: String
    var priority: Int
    var isEnabled: Bool
    var createdAt: Date

    init(
        title: String,
        pattern: String,
        matchField: PaymentRuleMatchField = .merchantAndNote,
        channel: PaymentChannel? = nil,
        category: ExpenseCategory,
        scene: String,
        priority: Int = 100,
        isEnabled: Bool = true,
        createdAt: Date = .now
    ) {
        self.title = title
        self.pattern = pattern
        self.matchFieldRaw = matchField.rawValue
        self.channelRaw = channel?.rawValue ?? ""
        self.categoryRaw = category.rawValue
        self.scene = scene
        self.priority = priority
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    var matchField: PaymentRuleMatchField {
        get { PaymentRuleMatchField(rawValue: matchFieldRaw) ?? .merchantAndNote }
        set { matchFieldRaw = newValue.rawValue }
    }

    var channel: PaymentChannel? {
        get { channelRaw.isEmpty ? nil : PaymentChannel(rawValue: channelRaw) }
        set { channelRaw = newValue?.rawValue ?? "" }
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

enum PaymentRuleMatchField: String, CaseIterable, Identifiable {
    case merchant = "商户"
    case note = "备注"
    case merchantAndNote = "商户或备注"

    var id: String { rawValue }
}

@Model
final class BudgetPlan {
    var title: String
    var periodRaw: String
    var categoryRaw: String
    var amount: Decimal
    var createdAt: Date
    var isEnabled: Bool

    init(
        title: String,
        period: SummaryPeriod,
        category: ExpenseCategory? = nil,
        amount: Decimal,
        createdAt: Date = .now,
        isEnabled: Bool = true
    ) {
        self.title = title
        self.periodRaw = period.rawValue
        self.categoryRaw = category?.rawValue ?? ""
        self.amount = amount
        self.createdAt = createdAt
        self.isEnabled = isEnabled
    }

    var period: SummaryPeriod {
        get { SummaryPeriod(rawValue: periodRaw) ?? .month }
        set { periodRaw = newValue.rawValue }
    }

    var category: ExpenseCategory? {
        get { categoryRaw.isEmpty ? nil : ExpenseCategory(rawValue: categoryRaw) }
        set { categoryRaw = newValue?.rawValue ?? "" }
    }
}
