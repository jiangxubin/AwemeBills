import Foundation
import SwiftData

enum ArchiveReportService {
    @discardableResult
    @MainActor
    static func generateMissingReports(
        schedules: [ArchiveSchedule],
        records: [ExpenseRecord],
        existingReports: [ArchiveReport],
        context: ModelContext,
        now: Date = .now
    ) -> [ArchiveReport] {
        var inserted: [ArchiveReport] = []

        for schedule in schedules where schedule.isEnabled {
            guard shouldGenerateReport(for: schedule, now: now),
                  let interval = BillingAnalytics.completedPeriodInterval(for: schedule.period, before: now),
                  !hasReport(for: schedule.period, interval: interval, in: existingReports + inserted)
            else { continue }

            let scoped = records.filter { $0.occurredAt >= interval.start && $0.occurredAt < interval.end }
            guard !scoped.isEmpty else { continue }

            let report = makeReport(period: schedule.period, interval: interval, records: scoped, generatedAt: now)
            context.insert(report)
            inserted.append(report)
        }

        return inserted
    }

    @discardableResult
    @MainActor
    static func rebuildReports(
        schedules: [ArchiveSchedule],
        records: [ExpenseRecord],
        existingReports: [ArchiveReport],
        context: ModelContext,
        now: Date = .now
    ) -> [ArchiveReport] {
        existingReports.forEach { context.delete($0) }

        let enabledPeriods = Set(schedules.filter(\.isEnabled).map(\.period))
        var candidates: [(SummaryPeriod, DateInterval, [ExpenseRecord])] = []

        for period in SummaryPeriod.allCases where enabledPeriods.contains(period) {
            for interval in completedIntervalsWithRecords(for: period, records: records, before: now) {
                let scoped = records.filter { $0.occurredAt >= interval.start && $0.occurredAt < interval.end }
                guard !scoped.isEmpty else { continue }
                candidates.append((period, interval, scoped))
            }
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.1.end == rhs.1.end {
                    return lhs.0.sortPriority < rhs.0.sortPriority
                }
                return lhs.1.end > rhs.1.end
            }
            .prefix(40)
            .map { period, interval, scoped in
                let report = makeReport(period: period, interval: interval, records: scoped, generatedAt: now)
                context.insert(report)
                return report
            }
    }

    static func makeReport(
        period: SummaryPeriod,
        interval: DateInterval,
        records: [ExpenseRecord],
        generatedAt: Date = .now
    ) -> ArchiveReport {
        let total = BillingAnalytics.total(records)
        let topCategory = BillingAnalytics.categoryTotals(records).first?.name ?? "暂无分类"
        let topScene = BillingAnalytics.sceneTotals(records).first?.scene ?? "暂无场景"
        let body = "共 \(records.count) 笔，合计 \(BillingAnalytics.currency(total))，最高分类：\(topCategory)，主要场景：\(topScene)。"

        return ArchiveReport(
            period: period,
            periodStart: interval.start,
            periodEnd: interval.end,
            generatedAt: generatedAt,
            recordCount: records.count,
            totalAmount: total,
            topCategory: topCategory,
            body: body
        )
    }

    private static func shouldGenerateReport(for schedule: ArchiveSchedule, now: Date) -> Bool {
        let scheduledTimeToday = Calendar.current.date(
            bySettingHour: schedule.hour,
            minute: schedule.minute,
            second: 0,
            of: now
        ) ?? now

        return now >= scheduledTimeToday
    }

    private static func hasReport(for period: SummaryPeriod, interval: DateInterval, in reports: [ArchiveReport]) -> Bool {
        reports.contains {
            $0.period == period
                && Calendar.current.isDate($0.periodStart, equalTo: interval.start, toGranularity: .minute)
                && Calendar.current.isDate($0.periodEnd, equalTo: interval.end, toGranularity: .minute)
        }
    }

    private static func completedIntervalsWithRecords(
        for period: SummaryPeriod,
        records: [ExpenseRecord],
        before now: Date
    ) -> [DateInterval] {
        let calendar = Calendar.current
        var intervalsByStart: [Date: DateInterval] = [:]

        for record in records {
            guard let interval = interval(containing: record.occurredAt, period: period, calendar: calendar),
                  interval.end <= now
            else { continue }

            intervalsByStart[interval.start] = interval
        }

        return intervalsByStart.values.sorted { $0.end > $1.end }
    }

    private static func interval(
        containing date: Date,
        period: SummaryPeriod,
        calendar: Calendar
    ) -> DateInterval? {
        switch period {
        case .day:
            return calendar.dateInterval(of: .day, for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)
        case .quarter:
            guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return nil }
            let month = calendar.component(.month, from: date)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var components = calendar.dateComponents([.year], from: date)
            components.month = quarterStartMonth
            components.day = 1
            guard let start = calendar.date(from: components),
                  let end = calendar.date(byAdding: .month, value: 3, to: start)
            else { return nil }
            return DateInterval(start: start, end: max(end, monthInterval.end))
        case .year:
            return calendar.dateInterval(of: .year, for: date)
        }
    }
}

private extension SummaryPeriod {
    var sortPriority: Int {
        switch self {
        case .day: 0
        case .week: 1
        case .month: 2
        case .quarter: 3
        case .year: 4
        }
    }
}
