import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchiveSchedule.periodRaw) private var schedules: [ArchiveSchedule]
    @Query private var expenses: [ExpenseRecord]
    @Query private var reports: [ArchiveReport]

    var body: some View {
        TabView {
            OverviewView()
                .tabItem {
                    Label("总览", systemImage: "chart.pie.fill")
                }

            DetailListView()
                .tabItem {
                    Label("明细", systemImage: "list.bullet.rectangle")
                }

            SceneAnalysisView()
                .tabItem {
                    Label("场景", systemImage: "map.fill")
                }

            ArchiveScheduleView()
                .tabItem {
                    Label("归档", systemImage: "archivebox.fill")
                }

            PaymentMonitorView()
                .tabItem {
                    Label("接入", systemImage: "antenna.radiowaves.left.and.right")
                }
        }
        .task {
            seedIfNeeded()
            let allSchedules = ensureDefaultSchedules()
            ArchiveReportService.generateMissingReports(
                schedules: allSchedules,
                records: expenses,
                existingReports: reports,
                context: modelContext
            )
            try? modelContext.save()
            await scheduleNotificationsIfPossible(allSchedules)
        }
    }

    private func seedIfNeeded() {
        guard expenses.isEmpty else { return }
        SampleData.records.forEach { modelContext.insert($0) }
    }

    private func ensureDefaultSchedules() -> [ArchiveSchedule] {
        let existing = Set(schedules.compactMap { SummaryPeriod(rawValue: $0.periodRaw) })
        let newSchedules = SummaryPeriod.allCases
            .filter { !existing.contains($0) }
            .map { ArchiveSchedule.defaultSchedule(for: $0) }
        newSchedules.forEach { modelContext.insert($0) }
        return schedules + newSchedules
    }

    private func scheduleNotificationsIfPossible(_ allSchedules: [ArchiveSchedule]) async {
        do {
            _ = try await ArchiveNotificationService.scheduleAll(allSchedules, records: expenses)
            try? modelContext.save()
        } catch {
            print("Failed to schedule archive notifications: \(error)")
        }
    }
}
