import SwiftData
import SwiftUI

struct ArchiveScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchiveSchedule.periodRaw) private var schedules: [ArchiveSchedule]
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @Query(sort: \ArchiveReport.generatedAt, order: .reverse) private var reports: [ArchiveReport]
    @State private var selectedPeriod: SummaryPeriod = .month
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    periodPicker
                    archiveSummaryCard
                    insightSection
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
            .navigationTitle("报告")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var periodPicker: some View {
        Picker("周期", selection: $selectedPeriod) {
            ForEach([SummaryPeriod.day, .week, .month, .quarter, .year]) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var archiveSummaryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("报告中心")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(BillingAnalytics.currency(BillingAnalytics.total(scopedRecords)))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text("\(selectedPeriod.rawValue) · \(scopedRecords.count) 笔明细 · \(visibleReports.count) 份总结")
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
                    Label("刷新报告", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var insightSection: some View {
        let insights = spendingInsights

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "消费洞察", subtitle: "结构、趋势和整理状态")
            AppCard {
                if insights.isEmpty {
                    EmptyStateView(title: "记录更多消费后生成洞察", systemImage: "sparkles")
                } else {
                    VStack(spacing: 12) {
                        ForEach(insights) { insight in
                            SpendingInsightRow(insight: insight)
                            if insight.id != insights.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "消费总结", subtitle: visibleReports.isEmpty ? "\(selectedPeriod.rawValue)历史" : "\(visibleReports.count) 份")
            AppCard {
                if visibleReports.isEmpty {
                    EmptyStateView(title: "暂无\(selectedPeriod.rawValue)消费总结", systemImage: "doc.text.magnifyingglass")
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

    private var scopedRecords: [ExpenseRecord] {
        BillingAnalytics.records(records, in: selectedPeriod)
    }

    private var categoryTotals: [CategoryTotal] {
        BillingAnalytics.categoryTotals(scopedRecords)
    }

    private var sceneTotals: [SceneTotal] {
        BillingAnalytics.sceneTotals(scopedRecords)
    }

    private var visibleReports: [ArchiveReport] {
        Array(reports.filter { $0.recordCount > 0 && $0.period == selectedPeriod }.prefix(20))
    }

    private var spendingInsights: [SpendingInsight] {
        guard !scopedRecords.isEmpty else { return [] }

        var insights: [SpendingInsight] = []
        let currentTotal = BillingAnalytics.total(scopedRecords)

        if let trend = trendInsight(currentTotal: currentTotal) {
            insights.append(trend)
        }

        if let concentration = concentrationInsight(currentTotal: currentTotal) {
            insights.append(concentration)
        }

        let unarchivedCount = scopedRecords.filter { !$0.isArchived }.count
        insights.append(
            SpendingInsight(
                title: unarchivedCount > 0 ? "还有 \(unarchivedCount) 笔未整理" : "本期消费都已整理",
                detail: unarchivedCount > 0 ? "整理后，周期总结会更干净，复盘时也更容易定位异常。" : "记录状态良好，可以直接查看周期消费总结。",
                systemImage: unarchivedCount > 0 ? "archivebox" : "checkmark.seal",
                tint: unarchivedCount > 0 ? AppTheme.amber : AppTheme.teal
            )
        )

        return Array(insights.prefix(3))
    }

    private func trendInsight(currentTotal: Decimal) -> SpendingInsight? {
        guard let previousInterval = BillingAnalytics.completedPeriodInterval(for: selectedPeriod, before: .now) else {
            return nil
        }

        let previousRecords = records.filter {
            $0.occurredAt >= previousInterval.start && $0.occurredAt < previousInterval.end
        }
        let previousTotal = BillingAnalytics.total(previousRecords)

        guard previousTotal > .zero else {
            return SpendingInsight(
                title: "\(selectedPeriod.rawValue)支出 \(BillingAnalytics.currency(currentTotal))",
                detail: "上一完整周期暂无可比数据，先把这期作为你的基线。",
                systemImage: selectedPeriod.iconName,
                tint: AppTheme.accent
            )
        }

        let currentValue = (currentTotal as NSDecimalNumber).doubleValue
        let previousValue = max((previousTotal as NSDecimalNumber).doubleValue, 0.01)
        let delta = (currentValue - previousValue) / previousValue
        let percentText = percentText(abs(delta))

        if delta > 0.02 {
            return SpendingInsight(
                title: "较上一完整周期高 \(percentText)",
                detail: "优先看高额分类和最近消费，确认是不是一次性支出。",
                systemImage: "arrow.up.right",
                tint: .red
            )
        }

        if delta < -0.02 {
            return SpendingInsight(
                title: "较上一完整周期低 \(percentText)",
                detail: "支出节奏变轻，可以维持当前预算线。",
                systemImage: "arrow.down.right",
                tint: AppTheme.teal
            )
        }

        return SpendingInsight(
            title: "支出节奏基本持平",
            detail: "和上一完整周期接近，重点关注结构变化。",
            systemImage: "equal",
            tint: AppTheme.accent
        )
    }

    private func concentrationInsight(currentTotal: Decimal) -> SpendingInsight? {
        guard currentTotal > .zero else { return nil }

        if let topScene = sceneTotals.first, topScene.scene != "未标记场景" {
            return concentrationInsight(
                title: "\(topScene.scene) 是主要场景",
                amount: topScene.amount,
                currentTotal: currentTotal,
                detailPrefix: "\(topScene.count) 笔集中在这里"
            )
        }

        guard let topCategory = categoryTotals.first else { return nil }
        return concentrationInsight(
            title: "\(topCategory.name) 占比最高",
            amount: topCategory.amount,
            currentTotal: currentTotal,
            detailPrefix: "这是本期最大的消费结构"
        )
    }

    private func concentrationInsight(
        title: String,
        amount: Decimal,
        currentTotal: Decimal,
        detailPrefix: String
    ) -> SpendingInsight {
        let amountValue = (amount as NSDecimalNumber).doubleValue
        let totalValue = max((currentTotal as NSDecimalNumber).doubleValue, 0.01)
        let share = amountValue / totalValue
        let tint: Color = share >= 0.45 ? AppTheme.amber : AppTheme.accent

        return SpendingInsight(
            title: title,
            detail: "\(detailPrefix)，占本期 \(percentText(share))。",
            systemImage: "target",
            tint: tint
        )
    }

    private func percentText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int((value * 100).rounded()))%"
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

private struct SpendingInsight: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
}

private struct SpendingInsightRow: View {
    let insight: SpendingInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(insight.tint)
                .frame(width: 34, height: 34)
                .background(insight.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.title)，\(insight.detail)")
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
