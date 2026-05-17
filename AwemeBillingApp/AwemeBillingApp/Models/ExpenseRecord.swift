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
