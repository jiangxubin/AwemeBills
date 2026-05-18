import SwiftData
import SwiftUI

struct ArchiveScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchiveSchedule.periodRaw) private var schedules: [ArchiveSchedule]
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @Query(sort: \ArchiveReport.generatedAt, order: .reverse) private var reports: [ArchiveReport]
    @State private var statusMessage = ""
    @State private var showsFallbackSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if reports.isEmpty {
                        ContentUnavailableView(
                            "暂无历史归档",
                            systemImage: "archivebox",
                            description: Text("到达推送时间后，消费管家会生成对应周期的归档报告。")
                        )
                        .listRowInsets(EdgeInsets())
                    } else {
                        ForEach(reports) { report in
                            ArchiveReportRow(report: report)
                        }
                    }
                } header: {
                    Text("历史归档")
                }

                Section("归档状态") {
                    LabeledContent("已归档", value: "\(records.filter(\.isArchived).count) 笔")
                    LabeledContent("未归档", value: "\(records.filter { !$0.isArchived }.count) 笔")
                    Button {
                        records.forEach { $0.isArchived = true }
                    } label: {
                        Label("归档当前全部历史消费", systemImage: "archivebox.fill")
                    }

                    Button {
                        generateReports()
                    } label: {
                        Label("补齐历史归档报告", systemImage: "doc.badge.clock")
                    }
                }

                fallbackSettingsSection

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("历史归档")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await scheduleNotifications() }
                    } label: {
                        Image(systemName: "bell.badge")
                    }
                    .accessibilityLabel("排程推送")
                }
            }
        }
    }

    private var fallbackSettingsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsFallbackSettings) {
                ForEach(SummaryPeriod.allCases) { period in
                    if let schedule = schedules.first(where: { $0.period == period }) {
                        ScheduleRow(schedule: schedule)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("兜底推送设置")
                        .font(.headline)
                    Text(scheduleSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("默认已经按日、周、月、季、年生成推送计划。平时不用改，只有想调整某个周期的推送时间时再展开。")
        }
    }

    private var scheduleSummary: String {
        let enabledCount = schedules.filter(\.isEnabled).count
        guard let daySchedule = schedules.first(where: { $0.period == .day }) else {
            return "默认每日 09:00，其余周期同样按周期开始后推送"
        }
        return "\(enabledCount) 个兜底推送已启用，每日 \(String(format: "%02d:%02d", daySchedule.hour, daySchedule.minute))"
    }

    private func scheduleNotifications() async {
        let granted = await ArchiveNotificationService.requestAuthorization()
        guard granted else {
            statusMessage = "通知权限未开启，无法推送消费总结。"
            return
        }

        do {
            for schedule in schedules {
                try await ArchiveNotificationService.schedule(schedule, records: records)
            }
            try? modelContext.save()
            statusMessage = "已更新 \(schedules.filter(\.isEnabled).count) 个总结推送。"
        } catch {
            statusMessage = "排程失败：\(error.localizedDescription)"
        }
    }

    private func generateReports() {
        let inserted = ArchiveReportService.generateMissingReports(
            schedules: schedules,
            records: records,
            existingReports: reports,
            context: modelContext
        )
        try? modelContext.save()
        statusMessage = inserted.isEmpty ? "没有需要补齐的历史归档报告。" : "已补齐 \(inserted.count) 份历史归档报告。"
    }
}

struct ScheduleRow: View {
    @Bindable var schedule: ArchiveSchedule
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用推送", isOn: $schedule.isEnabled)

                HStack {
                    Picker("小时", selection: $schedule.hour) {
                        ForEach(0...23, id: \.self) { hour in
                            Text(String(format: "%02d 时", hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("分钟", selection: $schedule.minute) {
                        ForEach(0...59, id: \.self) { minute in
                            Text(String(format: "%02d 分", minute)).tag(minute)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .font(.subheadline)

                Text("默认：\(schedule.period.defaultDescription)。下一次：\(BillingAnalytics.nextFireDate(for: schedule), format: .dateTime.year().month().day().hour().minute())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 12) {
                Label(schedule.period.rawValue, systemImage: schedule.period.iconName)
                    .font(.headline)
                Spacer()
                Text(schedule.isEnabled ? String(format: "%02d:%02d", schedule.hour, schedule.minute) : "已停用")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(schedule.isEnabled ? .primary : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ArchiveReportRow: View {
    let report: ArchiveReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(report.period.rawValue, systemImage: report.period.iconName)
                    .font(.headline)
                Spacer()
                Text(BillingAnalytics.currency(report.totalAmount))
                    .font(.headline.monospacedDigit())
            }

            Text(reportPeriodText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(report.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var reportPeriodText: String {
        let start = report.periodStart.formatted(.dateTime.year().month().day())
        let end = Calendar.current.date(byAdding: .second, value: -1, to: report.periodEnd) ?? report.periodEnd
        let endText = end.formatted(.dateTime.year().month().day())
        return "\(start) - \(endText) · \(report.recordCount) 笔 · \(report.generatedAt.formatted(.dateTime.month().day().hour().minute()))生成"
    }
}
