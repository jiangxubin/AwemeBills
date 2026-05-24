import AppIntents
import Foundation
import SwiftData

enum ExpenseCategory: String, AppEnum, CaseIterable, Identifiable {
    case dining = "餐饮"
    case commute = "交通"
    case shopping = "购物"
    case housing = "居家"
    case health = "健康"
    case entertainment = "娱乐"
    case travel = "旅行"
    case education = "学习"
    case transfer = "转账"
    case other = "其他"

    var id: String { rawValue }

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "消费分类")

    static var caseDisplayRepresentations: [ExpenseCategory: DisplayRepresentation] = [
        .dining: "餐饮",
        .commute: "交通",
        .shopping: "购物",
        .housing: "居家",
        .health: "健康",
        .entertainment: "娱乐",
        .travel: "旅行",
        .education: "学习",
        .transfer: "转账",
        .other: "其他"
    ]
}

enum PaymentChannel: String, AppEnum, CaseIterable, Identifiable {
    case alipay = "支付宝"
    case wechat = "微信支付"
    case unionPay = "云闪付"
    case bankCard = "银行卡"
    case cash = "现金"
    case other = "其他"

    var id: String { rawValue }

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "支付渠道")

    static var caseDisplayRepresentations: [PaymentChannel: DisplayRepresentation] = [
        .alipay: "支付宝",
        .wechat: "微信支付",
        .unionPay: "云闪付",
        .bankCard: "银行卡",
        .cash: "现金",
        .other: "其他"
    ]
}

@Model
final class ExpenseRecord {
    var amount: Decimal
    var merchant: String
    var categoryRaw: String
    var scene: String
    var channelRaw: String
    var note: String
    var occurredAt: Date
    var createdAt: Date
    var isArchived: Bool

    init(
        amount: Decimal,
        merchant: String,
        category: ExpenseCategory,
        scene: String,
        channel: PaymentChannel,
        note: String = "",
        occurredAt: Date = .now,
        createdAt: Date = .now,
        isArchived: Bool = false
    ) {
        self.amount = amount
        self.merchant = merchant
        self.categoryRaw = category.rawValue
        self.scene = scene
        self.channelRaw = channel.rawValue
        self.note = note
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.isArchived = isArchived
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var channel: PaymentChannel {
        get { PaymentChannel(rawValue: channelRaw) ?? .other }
        set { channelRaw = newValue.rawValue }
    }
}

enum ExpenseRecordMaintenance {
    struct CleanupResult {
        var removedSeedRecords = 0
        var removedDuplicateRecords = 0

        var didChange: Bool {
            removedSeedRecords > 0 || removedDuplicateRecords > 0
        }
    }

    private struct SeedSignature {
        let merchant: String
        let amountCents: Int64
        let scene: String
        let channel: PaymentChannel
        let category: ExpenseCategory
        let note: String
    }

    private static let seedSignatures: [SeedSignature] = [
        SeedSignature(merchant: "咖啡店", amountCents: 3850, scene: "工作日早餐", channel: .alipay, category: .dining, note: "拿铁和三明治"),
        SeedSignature(merchant: "盒马", amountCents: 12800, scene: "家庭补货", channel: .wechat, category: .shopping, note: ""),
        SeedSignature(merchant: "地铁", amountCents: 1600, scene: "通勤", channel: .unionPay, category: .commute, note: ""),
        SeedSignature(merchant: "面馆", amountCents: 5600, scene: "午餐", channel: .wechat, category: .dining, note: ""),
        SeedSignature(merchant: "药房", amountCents: 26800, scene: "家庭健康", channel: .alipay, category: .health, note: ""),
        SeedSignature(merchant: "电影院", amountCents: 8900, scene: "周末休闲", channel: .wechat, category: .entertainment, note: ""),
        SeedSignature(merchant: "酒店", amountCents: 42000, scene: "短途出行", channel: .bankCard, category: .travel, note: ""),
        SeedSignature(merchant: "在线课程", amountCents: 19900, scene: "技能提升", channel: .alipay, category: .education, note: "")
    ]

    static func cleanup(records: [ExpenseRecord], context: ModelContext) -> CleanupResult {
        var result = CleanupResult()
        var seenKeys = Set<String>()

        for record in records.sorted(by: { $0.createdAt < $1.createdAt }) {
            if isSeedRecord(record) {
                context.delete(record)
                result.removedSeedRecords += 1
                continue
            }

            let key = deduplicationKey(
                amount: record.amount,
                merchant: record.merchant,
                category: record.category,
                channel: record.channel,
                occurredAt: record.occurredAt
            )

            if seenKeys.contains(key) {
                context.delete(record)
                result.removedDuplicateRecords += 1
            } else {
                seenKeys.insert(key)
            }
        }

        return result
    }

    static func uniquePayments(
        _ payments: [ParsedPayment],
        existing records: [ExpenseRecord]
    ) -> [ParsedPayment] {
        var seenKeys = Set(records.map {
            deduplicationKey(
                amount: $0.amount,
                merchant: $0.merchant,
                category: $0.category,
                channel: $0.channel,
                occurredAt: $0.occurredAt
            )
        })

        var unique: [ParsedPayment] = []
        for payment in payments {
            let key = deduplicationKey(
                amount: payment.amount,
                merchant: payment.merchant,
                category: payment.category,
                channel: payment.channel,
                occurredAt: payment.occurredAt ?? .now
            )

            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            unique.append(payment)
        }
        return unique
    }

    static func deduplicationKey(
        amount: Decimal,
        merchant: String,
        category: ExpenseCategory,
        channel: PaymentChannel,
        occurredAt: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: occurredAt)
        let time = [
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        ]
        .map(String.init)
        .joined(separator: "-")

        return [
            normalizedMerchant(merchant),
            String(cents(from: amount)),
            category.rawValue,
            channel.rawValue,
            time
        ].joined(separator: "|")
    }

    static func centsValue(from amount: Decimal) -> Int64 {
        cents(from: amount)
    }

    private static func isSeedRecord(_ record: ExpenseRecord) -> Bool {
        seedSignatures.contains { signature in
            normalizedMerchant(record.merchant) == normalizedMerchant(signature.merchant)
                && cents(from: record.amount) == signature.amountCents
                && record.scene == signature.scene
                && record.channel == signature.channel
                && record.category == signature.category
                && record.note == signature.note
        }
    }

    private static func normalizedMerchant(_ merchant: String) -> String {
        merchant
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }

    private static func cents(from amount: Decimal) -> Int64 {
        let scaled = NSDecimalNumber(decimal: amount)
            .multiplying(byPowerOf10: 2)
            .rounding(accordingToBehavior: nil)
        return scaled.int64Value
    }
}
