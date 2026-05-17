import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchiveSchedule.periodRaw) private var schedules: [ArchiveSchedule]
    @Query private var expenses: [ExpenseRecord]

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
            ensureDefaultSchedules()
        }
    }

    private func seedIfNeeded() {
        guard expenses.isEmpty else { return }
        SampleData.records.forEach { modelContext.insert($0) }
    }

    private func ensureDefaultSchedules() {
        let existing = Set(schedules.compactMap { SummaryPeriod(rawValue: $0.periodRaw) })
        SummaryPeriod.allCases
            .filter { !existing.contains($0) }
            .map { ArchiveSchedule.defaultSchedule(for: $0) }
            .forEach { modelContext.insert($0) }
    }
}
