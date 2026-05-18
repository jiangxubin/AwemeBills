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
            let report = makeReport(period: schedule.period, interval: interval, records: scoped, generatedAt: now)
            context.insert(report)
            inserted.append(report)
        }

        return inserted
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
}
