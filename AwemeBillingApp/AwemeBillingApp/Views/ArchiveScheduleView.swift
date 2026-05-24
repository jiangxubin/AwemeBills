import SwiftData
import SwiftUI

struct ArchiveScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchiveSchedule.periodRaw) private var schedules: [ArchiveSchedule]
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @Query(sort: \ArchiveReport.generatedAt, order: .reverse) private var reports: [ArchiveReport]
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    archiveSummaryCard
                    reportSection

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
            .background(AppTheme.background)
            .navigationTitle("归档")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var archiveSummaryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("历史归档")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(visibleReports.count) 份报告")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("只保留有消费明细的周期，报告会从当前明细重建。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    rebuildReports()
                } label: {
                    Label("刷新历史归档", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "报告列表", subtitle: visibleReports.isEmpty ? nil : "\(visibleReports.count) 份")
            AppCard {
                if visibleReports.isEmpty {
                    EmptyStateView(title: "暂无历史归档", systemImage: "archivebox")
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleReports.indices, id: \.self) { index in
                            ArchiveReportRow(report: visibleReports[index])
                                .padding(.vertical, 12)
                            if index < visibleReports.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var visibleReports: [ArchiveReport] {
        Array(reports.filter { $0.recordCount > 0 }.prefix(20))
    }

    private func rebuildReports() {
        let cleanup = ExpenseRecordMaintenance.cleanup(records: records, context: modelContext)
        let currentRecords = (try? modelContext.fetch(FetchDescriptor<ExpenseRecord>())) ?? records
        let currentReports = (try? modelContext.fetch(FetchDescriptor<ArchiveReport>())) ?? reports
        let rebuilt = ArchiveReportService.rebuildReports(
            schedules: schedules,
            records: currentRecords,
            existingReports: currentReports,
            context: modelContext
        )
        try? modelContext.save()
        if cleanup.didChange {
            statusMessage = "已清理 \(cleanup.removedSeedRecords + cleanup.removedDuplicateRecords) 条脏/重复明细，并重建 \(rebuilt.count) 份报告。"
        } else {
            statusMessage = rebuilt.isEmpty ? "暂无可生成的历史归档报告。" : "已重建 \(rebuilt.count) 份历史归档报告。"
        }
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
                Image(systemName: schedule.period.iconName)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28)

                Text(schedule.period.rawValue)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(schedule.isEnabled ? String(format: "%02d:%02d", schedule.hour, schedule.minute) : "已停用")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(schedule.isEnabled ? .primary : .secondary)
            }
        }
    }
}

struct ArchiveReportRow: View {
    let report: ArchiveReport

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: report.period.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(report.period.rawValue) · \(reportDateText)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(report.recordCount) 笔 · \(report.topCategory)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(BillingAnalytics.currency(report.totalAmount))
                .font(.subheadline.weight(.bold).monospacedDigit())
        }
    }

    private var reportDateText: String {
        let start = report.periodStart.formatted(.dateTime.year().month().day())
        let end = Calendar.current.date(byAdding: .second, value: -1, to: report.periodEnd) ?? report.periodEnd
        let endText = end.formatted(.dateTime.year().month().day())
        return start == endText ? start : "\(start)-\(endText)"
    }
}
