import Foundation
import SwiftData

enum ExpenseMutationService {
    @MainActor
    static func refreshReportsAndNotifications(context: ModelContext) async {
        do {
            let schedules = try context.fetch(FetchDescriptor<ArchiveSchedule>())
            let records = try context.fetch(FetchDescriptor<ExpenseRecord>())
            let reports = try context.fetch(FetchDescriptor<ArchiveReport>())
            ArchiveReportService.rebuildReports(
                schedules: schedules,
                records: records,
                existingReports: reports,
                context: context
            )
            _ = try await ArchiveNotificationService.scheduleAll(
                schedules,
                records: records,
                requestAuthorizationIfNeeded: false
            )
            try? context.save()
        } catch {
            print("Failed to refresh reports and notifications: \(error)")
        }
    }
}
