import Foundation
import SwiftData

enum PaymentRuleEngine {
    struct Match {
        let category: ExpenseCategory
        let scene: String
        let confidenceBoost: Double
    }

    @MainActor
    static func applyRules(to payment: ParsedPayment, rules: [PaymentRule]) -> (ParsedPayment, String, Double) {
        let fallback = defaultMatch(for: [payment.merchant, payment.note].joined(separator: " "))
        let sortedRules = rules
            .filter(\.isEnabled)
            .sorted { $0.priority < $1.priority }

        if let rule = sortedRules.first(where: { matches($0, payment: payment) }) {
            let parsed = ParsedPayment(
                amount: payment.amount,
                merchant: payment.merchant,
                channel: payment.channel,
                note: payment.note,
                occurredAt: payment.occurredAt,
                category: rule.category,
                merchantLogoPNGData: payment.merchantLogoPNGData
            )
            return (parsed, rule.scene.isEmpty ? rule.category.rawValue : rule.scene, 0.96)
        }

        let resolvedCategory = payment.category == .other ? fallback.category : payment.category
        let resolvedCategoryRaw = payment.categoryRaw.isEmpty || payment.categoryRaw == ExpenseCategory.other.rawValue
            ? resolvedCategory.rawValue
            : payment.categoryRaw
        let parsed = ParsedPayment(
            amount: payment.amount,
            merchant: payment.merchant,
            channel: payment.channel,
            note: payment.note,
            occurredAt: payment.occurredAt,
            category: resolvedCategory,
            categoryRaw: resolvedCategoryRaw,
            merchantLogoPNGData: payment.merchantLogoPNGData
        )
        return (parsed, fallback.scene, fallback.confidenceBoost)
    }

    static func defaultCategory(for text: String) -> ExpenseCategory {
        defaultMatch(for: text).category
    }

    static func defaultMatch(for text: String) -> Match {
        let normalized = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)

        let rules: [(ExpenseCategory, String, [String])] = [
            (.dining, "餐饮", ["餐饮", "美食", "咖啡", "外卖", "饭", "面馆", "餐厅", "奶茶", "大米先生", "你六姐", "秦碗会"]),
            (.commute, "交通出行", ["停车", "车位", "爱车", "养车", "地铁", "公交", "打车", "高德", "滴滴", "加油", "充电", "沪ah"]),
            (.shopping, "购物", ["超市", "盒马", "京东", "淘宝", "天猫", "拼多多", "便利店", "交易类型 消费", "日用", "百货", "山姆", "大润发"]),
            (.housing, "居家", ["物业", "水费", "电费", "燃气", "家政", "宽带", "房租", "缴费"]),
            (.health, "健康", ["药房", "医院", "体检", "挂号", "医保"]),
            (.entertainment, "休闲娱乐", ["文化", "休闲", "电影", "游戏", "会员", "演出"]),
            (.travel, "旅行", ["酒店", "机票", "火车", "高铁", "携程", "飞猪"]),
            (.education, "学习", ["课程", "图书", "教育", "学习", "知识"]),
            (.transfer, "转账", ["转账", "红包", "收款", "还款", "退款", "收益发放", "群收款"])
        ]

        for (category, scene, keywords) in rules {
            if keywords.contains(where: { normalized.contains($0) }) {
                return Match(category: category, scene: scene, confidenceBoost: 0.86)
            }
        }

        return Match(category: .other, scene: "待分类", confidenceBoost: 0.62)
    }

    @MainActor
    static func learnRule(from record: ExpenseRecord, context: ModelContext) {
        let merchant = record.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard merchant.count >= 2 else { return }

        let descriptor = FetchDescriptor<PaymentRule>(
            predicate: #Predicate { rule in
                rule.pattern == merchant
            }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let rule = PaymentRule(
            title: merchant,
            pattern: merchant,
            category: record.category,
            scene: record.scene.isEmpty ? record.category.rawValue : record.scene,
            priority: 50
        )
        context.insert(rule)
    }

    private static func matches(_ rule: PaymentRule, payment: ParsedPayment) -> Bool {
        guard rule.channel == nil || rule.channel == payment.channel else { return false }
        let pattern = rule.pattern.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        guard !pattern.isEmpty else { return false }

        let merchant = payment.merchant.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        let note = payment.note.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)

        switch rule.matchField {
        case .merchant:
            return merchant.contains(pattern)
        case .note:
            return note.contains(pattern)
        case .merchantAndNote:
            return merchant.contains(pattern) || note.contains(pattern)
        }
    }
}
