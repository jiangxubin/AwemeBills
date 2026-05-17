import Foundation

struct CategoryTotal: Identifiable {
    let id = UUID()
    let name: String
    let amount: Decimal
}

struct SceneTotal: Identifiable {
    let id = UUID()
    let scene: String
    let amount: Decimal
    let count: Int
}

enum BillingAnalytics {
    static func total(_ records: [ExpenseRecord]) -> Decimal {
        records.reduce(Decimal.zero) { $0 + $1.amount }
    }

    static func records(_ records: [ExpenseRecord], in period: SummaryPeriod, now: Date = .now) -> [ExpenseRecord] {
        let calendar = Calendar.current
        let start: Date
        switch period {
        case .day:
            start = calendar.startOfDay(for: now)
        case .week:
            start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .month:
            start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .quarter:
            start = quarterStart(containing: now)
        case .year:
            start = calendar.dateInterval(of: .year, for: now)?.start ?? now
        }
        return records.filter { $0.occurredAt >= start && $0.occurredAt <= now }
    }

    static func categoryTotals(_ records: [ExpenseRecord]) -> [CategoryTotal] {
        Dictionary(grouping: records, by: \.categoryRaw)
            .map { CategoryTotal(name: $0.key, amount: total($0.value)) }
            .sorted { $0.amount > $1.amount }
    }

    static func sceneTotals(_ records: [ExpenseRecord]) -> [SceneTotal] {
        Dictionary(grouping: records) { record in
            record.scene.isEmpty ? "未标记场景" : record.scene
        }
        .map { SceneTotal(scene: $0.key, amount: total($0.value), count: $0.value.count) }
        .sorted { $0.amount > $1.amount }
    }

    static func dateGroupedRecords(_ records: [ExpenseRecord]) -> [(Date, [ExpenseRecord])] {
        Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.occurredAt) }
            .map { ($0.key, $0.value.sorted { $0.occurredAt > $1.occurredAt }) }
            .sorted { $0.0 > $1.0 }
    }

    static func nextFireDate(for schedule: ArchiveSchedule, from date: Date = .now) -> Date {
        let calendar = Calendar.current
        var base: Date

        switch schedule.period {
        case .day:
            base = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        case .week:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            base = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? date
        case .month:
            let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
            base = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? date
        case .quarter:
            base = nextQuarterStart(after: date)
        case .year:
            let yearStart = calendar.dateInterval(of: .year, for: date)?.start ?? date
            base = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? date
        }

        return calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: base) ?? base
    }

    static func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: value as NSDecimalNumber) ?? "¥0.00"
    }

    private static func quarterStart(containing date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        let month = components.month ?? 1
        let quarterMonth = ((month - 1) / 3) * 3 + 1
        return calendar.date(from: DateComponents(year: components.year, month: quarterMonth, day: 1)) ?? date
    }

    private static func nextQuarterStart(after date: Date) -> Date {
        let start = quarterStart(containing: date)
        return Calendar.current.date(byAdding: .month, value: 3, to: start) ?? date
    }
}
