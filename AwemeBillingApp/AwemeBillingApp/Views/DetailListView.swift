import SwiftData
import SwiftUI

struct DetailListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @Query(sort: \ArchiveReport.generatedAt, order: .reverse) private var reports: [ArchiveReport]
    @AppStorage("detailDefaultPeriod") private var detailDefaultPeriod = "month"
    @State private var editorRoute: ExpenseEditorRoute?
    @State private var selectedCategory: ExpenseCategory?
    @State private var displayMode: DetailDisplayMode = .records
    @State private var selectedPeriod: ExpensePeriodFilter = .all
    @State private var selectedDimension: ExpenseAggregationDimension = .category
    @State private var didApplyDefaultPeriod = false
    @State private var pendingDeletion: ExpenseRecord?

    private var scopedRecords: [ExpenseRecord] {
        selectedPeriod.records(from: records)
    }

    private var filteredRecords: [ExpenseRecord] {
        guard displayMode == .records, let selectedCategory else { return scopedRecords }
        return scopedRecords.filter { $0.category == selectedCategory }
    }

    private var aggregateRows: [ExpenseAggregateRowData] {
        ExpenseAggregateRowData.rows(
            from: scopedRecords,
            dimension: selectedDimension,
            period: selectedPeriod
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    controlPanel
                        .listRowInsets(EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18))
                        .listRowBackground(Color.clear)
                }

                switch displayMode {
                case .records:
                    recordListContent
                case .aggregate:
                    aggregateContent
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("明细")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editorRoute) { route in
                switch route {
                case .edit(let record):
                    ExpenseEditorView(record: record)
                }
            }
            .onChange(of: displayMode) { _, newValue in
                if newValue == .aggregate {
                    selectedCategory = nil
                }
            }
            .task {
                applyDefaultPeriodIfNeeded()
            }
            .onChange(of: detailDefaultPeriod) { _, _ in
                didApplyDefaultPeriod = false
                applyDefaultPeriodIfNeeded()
            }
            .confirmationDialog(
                "删除这笔消费？",
                isPresented: deletionConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let pendingDeletion {
                        Task { await deleteRecord(pendingDeletion) }
                    }
                }
                Button("取消", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: {
                Text("删除后会同步刷新总览和历史总结。")
            }
        }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: displayMode == .records ? selectedCategory?.rawValue ?? "全部消费" : selectedDimension.rawValue,
                subtitle: "\(filteredRecords.count) 笔 / \(BillingAnalytics.currency(BillingAnalytics.total(filteredRecords)))"
            )

            Picker("查看方式", selection: $displayMode) {
                ForEach(DetailDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            chipRow {
                ForEach(ExpensePeriodFilter.allCases) { period in
                    CategoryChip(title: period.rawValue, isSelected: selectedPeriod == period) {
                        selectedPeriod = period
                    }
                }
            }

            if displayMode == .records {
                chipRow {
                    CategoryChip(title: "全部类型", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(ExpenseCategory.allCases) { category in
                        CategoryChip(title: category.rawValue, isSelected: selectedCategory == category) {
                            selectedCategory = category
                        }
                    }
                }
            } else {
                chipRow {
                    ForEach(ExpenseAggregationDimension.allCases) { dimension in
                        CategoryChip(title: dimension.rawValue, isSelected: selectedDimension == dimension) {
                            selectedDimension = dimension
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
    }

    private func applyDefaultPeriodIfNeeded() {
        guard !didApplyDefaultPeriod else { return }
        selectedPeriod = ExpensePeriodFilter(storageValue: detailDefaultPeriod)
        didApplyDefaultPeriod = true
    }

    private func chipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var recordListContent: some View {
        if filteredRecords.isEmpty {
            Section {
                EmptyStateView(title: "没有符合筛选的消费", systemImage: "tray")
                    .listRowBackground(AppTheme.card)
            }
        } else {
            ForEach(BillingAnalytics.dateGroupedRecords(filteredRecords), id: \.0) { date, dayRecords in
                Section {
                    ForEach(dayRecords) { record in
                        Button {
                            editorRoute = .edit(record)
                        } label: {
                            ExpenseRow(record: record, showsCreatedAt: true)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeletion = record
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await toggleArchived(record) }
                            } label: {
                                Label(record.isArchived ? "取消归档" : "归档", systemImage: "archivebox")
                            }
                            .tint(.teal)
                        }
                    }
                } header: {
                    HStack {
                        Text(date, format: .dateTime.year().month().day().weekday())
                        Spacer()
                        Text("\(dayRecords.count) 笔")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var aggregateContent: some View {
        Section {
            if aggregateRows.isEmpty {
                EmptyStateView(title: "暂无聚合数据", systemImage: selectedDimension.systemImage)
                    .listRowBackground(AppTheme.card)
            } else {
                VStack(spacing: 16) {
                    ForEach(aggregateRows) { row in
                        DetailAggregateRow(
                            row: row,
                            maxAmount: aggregateRows.first?.amount ?? 1
                        )
                    }
                }
                .padding(.vertical, 8)
            }
        } header: {
            HStack {
                Text("\(selectedPeriod.rawValue) · \(selectedDimension.rawValue)")
                Spacer()
                Text("\(aggregateRows.count) 项")
            }
        }

        if !detailInsights.isEmpty {
            Section {
                VStack(spacing: 12) {
                    ForEach(detailInsights) { insight in
                        DetailInsightRow(insight: insight)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                HStack {
                    Text("消费洞察")
                    Spacer()
                    Text("\(scopedRecords.count) 笔")
                }
            }
        }

        Section {
            if visibleReports.isEmpty {
                EmptyStateView(title: "暂无历史总结", systemImage: "doc.text")
                    .listRowBackground(AppTheme.card)
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleReports) { report in
                        ArchiveReportRow(report: report)
                            .padding(.vertical, 12)
                        if report.id != visibleReports.last?.id {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("历史总结")
                Spacer()
                Text(selectedPeriod.reportTitle)
            }
        }
    }

    private var detailInsights: [DetailInsight] {
        guard !scopedRecords.isEmpty else { return [] }

        let total = BillingAnalytics.total(scopedRecords)
        var insights = [
            DetailInsight(
                title: "周期总支出",
                value: BillingAnalytics.currency(total),
                subtitle: "\(scopedRecords.count) 笔消费",
                systemImage: "chart.pie"
            )
        ]

        if let topAggregate = aggregateRows.first {
            insights.append(
                DetailInsight(
                    title: "最高占比",
                    value: topAggregate.title,
                    subtitle: "\(BillingAnalytics.currency(topAggregate.amount)) · \(topAggregate.count) 笔",
                    systemImage: selectedDimension.systemImage
                )
            )
        }

        let archivedCount = scopedRecords.filter(\.isArchived).count
        insights.append(
            DetailInsight(
                title: "归档状态",
                value: "\(archivedCount)/\(scopedRecords.count)",
                subtitle: archivedCount == scopedRecords.count ? "已全部整理" : "还有 \(scopedRecords.count - archivedCount) 笔未归档",
                systemImage: "archivebox"
            )
        )

        return insights
    }

    private var visibleReports: [ArchiveReport] {
        let nonEmptyReports = reports.filter { $0.recordCount > 0 }
        if let summaryPeriod = selectedPeriod.summaryPeriod {
            return Array(nonEmptyReports.filter { $0.period == summaryPeriod }.prefix(5))
        }
        return Array(nonEmptyReports.prefix(5))
    }

    private var deletionConfirmation: Binding<Bool> {
        Binding {
            pendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                pendingDeletion = nil
            }
        }
    }

    @MainActor
    private func deleteRecord(_ record: ExpenseRecord) async {
        modelContext.delete(record)
        try? modelContext.save()
        await ExpenseMutationService.refreshReportsAndNotifications(context: modelContext)
        pendingDeletion = nil
    }

    @MainActor
    private func toggleArchived(_ record: ExpenseRecord) async {
        record.isArchived.toggle()
        try? modelContext.save()
        await ExpenseMutationService.refreshReportsAndNotifications(context: modelContext)
    }
}

private enum ExpenseEditorRoute: Identifiable {
    case edit(ExpenseRecord)

    var id: String {
        switch self {
        case .edit(let record):
            "edit-\(ObjectIdentifier(record).hashValue)"
        }
    }
}

private enum DetailDisplayMode: String, CaseIterable, Identifiable {
    case records = "明细"
    case aggregate = "聚合"

    var id: String { rawValue }
}

private enum ExpensePeriodFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case day = "今天"
    case week = "本周"
    case month = "本月"
    case quarter = "本季"
    case year = "本年"

    var id: String { rawValue }

    var summaryPeriod: SummaryPeriod? {
        switch self {
        case .all: nil
        case .day: .day
        case .week: .week
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        }
    }

    var reportTitle: String {
        summaryPeriod?.rawValue ?? "最近 5 份"
    }

    func records(from records: [ExpenseRecord], now: Date = .now) -> [ExpenseRecord] {
        guard let period = summaryPeriod else { return records }
        return BillingAnalytics.records(records, in: period, now: now)
    }
}

private struct DetailInsight: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
}

private struct DetailInsightRow: View {
    let insight: DetailInsight

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: insight.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(insight.value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer()

            Text(insight.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private enum ExpenseAggregationDimension: String, CaseIterable, Identifiable {
    case category = "消费类型"
    case time = "时间周期"
    case scene = "来源场景"
    case channel = "支付渠道"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .category: "tag"
        case .time: "calendar"
        case .scene: "map"
        case .channel: "creditcard"
        }
    }
}

private struct ExpenseAggregateRowData: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let amount: Decimal
    let count: Int

    static func rows(
        from records: [ExpenseRecord],
        dimension: ExpenseAggregationDimension,
        period: ExpensePeriodFilter
    ) -> [ExpenseAggregateRowData] {
        switch dimension {
        case .category:
            return groupedRows(records, title: { $0.categoryRaw }, subtitle: { _ in "按消费类型" })
        case .time:
            return groupedRows(records, title: { timeBucketTitle(for: $0.occurredAt, period: period) }, subtitle: { _ in "按发生时间" })
        case .scene:
            return groupedRows(records, title: { $0.scene.isEmpty ? "未标记场景" : $0.scene }, subtitle: { _ in "来源场景" })
        case .channel:
            return groupedRows(records, title: { $0.channelRaw }, subtitle: { _ in "支付渠道" })
        }
    }

    private static func groupedRows(
        _ records: [ExpenseRecord],
        title: (ExpenseRecord) -> String,
        subtitle: (String) -> String
    ) -> [ExpenseAggregateRowData] {
        Dictionary(grouping: records, by: title)
            .map { key, values in
                ExpenseAggregateRowData(
                    id: key,
                    title: key,
                    subtitle: subtitle(key),
                    amount: BillingAnalytics.total(values),
                    count: values.count
                )
            }
            .sorted {
                if $0.amount == $1.amount {
                    return $0.count > $1.count
                }
                return $0.amount > $1.amount
            }
    }

    private static func timeBucketTitle(for date: Date, period: ExpensePeriodFilter) -> String {
        switch period {
        case .all, .year:
            return date.formatted(.dateTime.year().month())
        case .day, .week, .month, .quarter:
            return date.formatted(.dateTime.month().day())
        }
    }
}

private extension ExpensePeriodFilter {
    init(storageValue: String) {
        switch storageValue {
        case "day":
            self = .day
        case "week":
            self = .week
        case "month":
            self = .month
        case "quarter":
            self = .quarter
        case "year":
            self = .year
        default:
            self = .all
        }
    }
}

private struct DetailAggregateRow: View {
    let row: ExpenseAggregateRowData
    let maxAmount: Decimal

    private var ratio: Double {
        let current = (row.amount as NSDecimalNumber).doubleValue
        let maximum = max((maxAmount as NSDecimalNumber).doubleValue, 1)
        return min(max(current / maximum, 0.05), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(row.subtitle) · \(row.count) 笔")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(BillingAnalytics.currency(row.amount))
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.accent.opacity(0.12))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.accentGradient)
                            .frame(width: proxy.size.width * ratio)
                    }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title)，\(row.count) 笔，\(BillingAnalytics.currency(row.amount))")
    }
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.accent : Color.secondary.opacity(0.10), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
