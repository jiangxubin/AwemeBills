import Foundation
import UserNotifications

enum ArchiveNotificationService {
    static func canScheduleWithoutPrompting() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    static func scheduleAll(_ schedules: [ArchiveSchedule], records: [ExpenseRecord], requestAuthorizationIfNeeded: Bool = true) async throws -> Bool {
        var canSchedule = await canScheduleWithoutPrompting()
        if !canSchedule && requestAuthorizationIfNeeded {
            canSchedule = await requestAuthorization()
        }
        guard canSchedule else { return false }

        for schedule in schedules {
            try await ArchiveNotificationService.schedule(schedule, records: records)
        }
        return true
    }

    static func schedule(_ schedule: ArchiveSchedule, records: [ExpenseRecord]) async throws {
        guard schedule.isEnabled else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: schedule.period)])
            return
        }

        let fireDate = BillingAnalytics.nextFireDate(for: schedule)
        let content = UNMutableNotificationContent()
        content.title = "\(schedule.period.rawValue)消费总结"
        content.body = summaryBody(for: schedule.period, records: records, fireDate: fireDate)
        content.sound = .default

        let dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: schedule.period), content: content, trigger: trigger)

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [request.identifier])
        try await UNUserNotificationCenter.current().add(request)
        schedule.lastScheduledAt = .now
    }

    static func identifier(for period: SummaryPeriod) -> String {
        "archive-summary-\(period.rawValue)"
    }

    private static func summaryBody(for period: SummaryPeriod, records: [ExpenseRecord], fireDate: Date) -> String {
        let scoped = BillingAnalytics.records(records, completedPeriod: period, before: fireDate)
        let total = BillingAnalytics.currency(BillingAnalytics.total(scoped))
        let top = BillingAnalytics.categoryTotals(scoped).first?.name ?? "暂无分类"
        return "本期共 \(scoped.count) 笔，合计 \(total)，最高分类：\(top)。"
    }
}
