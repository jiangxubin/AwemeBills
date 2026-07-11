import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ArchiveSchedule.periodRaw) private var schedules: [ArchiveSchedule]
    @Query(sort: \ExpenseCategoryProfile.sortOrder) private var categoryProfiles: [ExpenseCategoryProfile]
    @Query private var expenses: [ExpenseRecord]
    @Query private var reports: [ArchiveReport]
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var selectedTab: AppTab = .overview
    @State private var importMode: ImportMode = .screenshot
    @State private var reviewImportRouteID = UUID()
    @State private var manualImportRequestID = UUID()
    @State private var didSeedUITestRecords = false

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView {
                importMode = .manual
                selectedTab = .importing
                manualImportRequestID = UUID()
            }
                .tabItem {
                    Label("总览", systemImage: "rectangle.grid.1x2")
                }
                .tag(AppTab.overview)

            DetailListView()
                .tabItem {
                    Label("明细", systemImage: "list.bullet.rectangle.portrait")
                }
                .tag(AppTab.details)

            PaymentMonitorView(
                importMode: $importMode,
                reviewRouteID: reviewImportRouteID,
                manualImportRequestID: manualImportRequestID
            )
                .tabItem {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .tag(AppTab.importing)

            ArchiveScheduleView()
                .tabItem {
                    Label("报告", systemImage: "doc.text")
                }
                .tag(AppTab.reports)

            ProfileSettingsView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
                .tag(AppTab.profile)
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(preferredColorScheme)
        .onAppear {
            seedUITestRecordsIfNeeded()
        }
        .task {
            await refreshArchivesAndNotifications(requestAuthorizationIfNeeded: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await refreshArchivesAndNotifications(requestAuthorizationIfNeeded: false)
                }
            }
        }
        .onOpenURL { url in
            Task { await handleURL(url) }
        }
    }

    private func ensureDefaultSchedules() -> [ArchiveSchedule] {
        let existing = Set(schedules.compactMap { SummaryPeriod(rawValue: $0.periodRaw) })
        let newSchedules = SummaryPeriod.allCases
            .filter { !existing.contains($0) }
            .map { ArchiveSchedule.defaultSchedule(for: $0) }
        newSchedules.forEach { modelContext.insert($0) }
        return schedules + newSchedules
    }

    private func refreshArchivesAndNotifications(requestAuthorizationIfNeeded: Bool) async {
        seedUITestRecordsIfNeeded()
        ExpenseCategoryCatalog.ensureDefaults(profiles: categoryProfiles, context: modelContext)
        let allSchedules = ensureDefaultSchedules()
        let isSampleUITest = ProcessInfo.processInfo.arguments.contains("-ui-testing-with-samples")
        let cleanup = isSampleUITest
            ? ExpenseRecordMaintenance.CleanupResult()
            : ExpenseRecordMaintenance.cleanup(records: expenses, context: modelContext)
        let currentRecords = (try? modelContext.fetch(FetchDescriptor<ExpenseRecord>())) ?? expenses
        let currentReports = (try? modelContext.fetch(FetchDescriptor<ArchiveReport>())) ?? reports
        if cleanup.didChange || !currentReports.isEmpty {
            ArchiveReportService.rebuildReports(
                schedules: allSchedules,
                records: currentRecords,
                existingReports: currentReports,
                context: modelContext
            )
        } else {
            ArchiveReportService.generateMissingReports(
                schedules: allSchedules,
                records: currentRecords,
                existingReports: currentReports,
                context: modelContext
            )
        }
        try? modelContext.save()
        await scheduleNotificationsIfPossible(
            allSchedules,
            records: currentRecords,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
        )
    }

    private func scheduleNotificationsIfPossible(
        _ allSchedules: [ArchiveSchedule],
        records: [ExpenseRecord],
        requestAuthorizationIfNeeded: Bool
    ) async {
        do {
            _ = try await ArchiveNotificationService.scheduleAll(
                allSchedules,
                records: records,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            )
            try? modelContext.save()
        } catch {
            print("Failed to schedule archive notifications: \(error)")
        }
    }

    private func seedUITestRecordsIfNeeded() {
        guard !didSeedUITestRecords,
              ProcessInfo.processInfo.arguments.contains("-ui-testing-with-samples")
        else { return }
        didSeedUITestRecords = true

        let existingRecords = (try? modelContext.fetch(FetchDescriptor<ExpenseRecord>())) ?? []
        guard existingRecords.isEmpty else { return }
        for record in SampleData.records {
            modelContext.insert(record)
        }
        try? modelContext.save()
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    @MainActor
    private func handleURL(_ url: URL) async {
        guard url.scheme == "awemebilling" else { return }
        selectedTab = .importing
        importMode = .screenshot

        if url.host == "review-import" {
            reviewImportRouteID = UUID()
            return
        }

        if ScreenshotImportDeepLinkHandler.canHandle(url) {
            await ScreenshotImportDeepLinkHandler.handle(url)
            reviewImportRouteID = UUID()
        }
    }
}

private enum AppTab: Hashable {
    case overview
    case details
    case importing
    case reports
    case profile
}
