import Foundation

enum SampleData {
    static var records: [ExpenseRecord] {
        [
            ExpenseRecord(amount: 38.5, merchant: "咖啡店", category: .dining, scene: "工作日早餐", channel: .alipay, note: "拿铁和三明治", occurredAt: daysAgo(0, hour: 8, minute: 20)),
            ExpenseRecord(amount: 128, merchant: "盒马", category: .shopping, scene: "家庭补货", channel: .wechat, occurredAt: daysAgo(0, hour: 19, minute: 10)),
            ExpenseRecord(amount: 16, merchant: "地铁", category: .commute, scene: "通勤", channel: .unionPay, occurredAt: daysAgo(1, hour: 9, minute: 2)),
            ExpenseRecord(amount: 56, merchant: "面馆", category: .dining, scene: "午餐", channel: .wechat, occurredAt: daysAgo(2, hour: 12, minute: 16)),
            ExpenseRecord(amount: 268, merchant: "药房", category: .health, scene: "家庭健康", channel: .alipay, occurredAt: daysAgo(5, hour: 15, minute: 42)),
            ExpenseRecord(amount: 89, merchant: "电影院", category: .entertainment, scene: "周末休闲", channel: .wechat, occurredAt: daysAgo(9, hour: 21, minute: 5)),
            ExpenseRecord(amount: 420, merchant: "酒店", category: .travel, scene: "短途出行", channel: .bankCard, occurredAt: daysAgo(18, hour: 22, minute: 12)),
            ExpenseRecord(amount: 199, merchant: "在线课程", category: .education, scene: "技能提升", channel: .alipay, occurredAt: daysAgo(36, hour: 20, minute: 30))
        ]
    }

    private static func daysAgo(_ day: Int, hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.day = (components.day ?? 1) - day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? .now
    }
}
