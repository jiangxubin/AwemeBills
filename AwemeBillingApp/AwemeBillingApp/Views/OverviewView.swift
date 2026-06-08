import SwiftData
import SwiftUI

struct OverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @Query(sort: \BudgetPlan.createdAt, order: .reverse) private var budgets: [BudgetPlan]
    @AppStorage("advancedAnalysisControlsEnabled") private var advancedAnalysisControlsEnabled = false
    @State private var editingBudgetPeriod: SummaryPeriod?
    @State private var selectedAnalysisDimension: OverviewAnalysisDimension = .category
    @State private var selectedAnalysisChartType: OverviewAnalysisChartType = .bar
    @State private var selectedBarOrientation: OverviewBarOrientation = .horizontal
    @State private var selectedPieStyle: OverviewPieStyle = .hollow
    @State private var selectedAnalysisRowID: String?
    @State private var selectedBudgetTrendScope: BudgetTrendScope = .week

    let onManualImport: () -> Void

    private let budgetPeriods: [SummaryPeriod] = [.day, .week, .month, .quarter, .year]

    init(onManualImport: @escaping () -> Void = {}) {
        self.onManualImport = onManualImport
    }

    private var monthRecords: [ExpenseRecord] {
        BillingAnalytics.records(records, in: .month)
    }

    private var analysisRows: [OverviewAggregateRowData] {
        OverviewAggregateRowData.rows(from: monthRecords, dimension: selectedAnalysisDimension)
    }

    private var budgetTrendBars: [BudgetTrendBar] {
        BudgetTrendBar.bars(from: records, scope: selectedBudgetTrendScope)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    budgetSection
                    spendingStructureSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
            .background(AppTheme.background)
            .navigationTitle("总览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onManualImport) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("从总览手动导入")
                }
            }
            .sheet(item: $editingBudgetPeriod) { period in
                BudgetEditorView(
                    period: period,
                    budget: budgetPlan(for: period, includingDisabled: true),
                    suggestedAmount: suggestedBudgetAmount(for: period, spent: spentAmount(for: period))
                ) { amount, isEnabled in
                    saveBudget(period: period, amount: amount, isEnabled: isEnabled)
                }
            }
        }
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "预算进度", subtitle: "已包含各周期支出，点击任一周期可设置")
            AppCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(budgetPeriods) { period in
                            let spent = spentAmount(for: period)
                            let plan = activeBudget(for: period)
                            let limit = plan?.amount ?? suggestedBudgetAmount(for: period, spent: spent)

                            BudgetRingButton(
                                period: period,
                                spent: spent,
                                limit: limit,
                                isEnabled: plan?.isEnabled ?? false,
                                tint: budgetTint(spent: spent, limit: limit)
                            ) {
                                editingBudgetPeriod = period
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(selectedBudgetTrendScope.rawValue)消费")
                                .font(.subheadline.weight(.semibold))
                            Text(selectedBudgetTrendScope.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        CompactToggleGroup {
                            ForEach(BudgetTrendScope.allCases) { scope in
                                CompactIconButton(
                                    systemImage: scope.systemImage,
                                    isSelected: selectedBudgetTrendScope == scope,
                                    accessibilityLabel: "查看\(scope.rawValue)消费柱状图",
                                    tint: AppTheme.accent
                                ) {
                                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                                        selectedBudgetTrendScope = scope
                                    }
                                }
                            }
                        }
                    }

                    BudgetTrendBarChart(bars: budgetTrendBars)
                }
            }
        }
    }

    private var spendingStructureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            overviewSectionHeader(
                title: "消费分析",
                subtitle: "本月 · 按\(selectedAnalysisDimension.rawValue)"
            ) {
                analysisChartControls
            }
            AppCard {
                VStack(alignment: .leading, spacing: 16) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(OverviewAnalysisDimension.allCases) { dimension in
                                CategoryChip(title: dimension.rawValue, isSelected: selectedAnalysisDimension == dimension) {
                                    selectedAnalysisDimension = dimension
                                    selectedAnalysisRowID = nil
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if analysisRows.isEmpty {
                        EmptyStateView(title: "暂无消费分析", systemImage: "chart.pie")
                    } else {
                        OverviewAggregateVisualizationView(
                            rows: analysisRows,
                            chartType: selectedAnalysisChartType,
                            barOrientation: selectedBarOrientation,
                            pieStyle: selectedPieStyle,
                            selectedRowID: $selectedAnalysisRowID
                        )
                    }
                }
            }
        }
    }

    private var analysisChartControls: some View {
        HStack(spacing: 8) {
            CompactToggleGroup {
                ForEach(OverviewAnalysisChartType.allCases) { chartType in
                    CompactIconButton(
                        systemImage: chartType.systemImage,
                        isSelected: selectedAnalysisChartType == chartType,
                        accessibilityLabel: "查看\(chartType.rawValue)",
                        tint: AppTheme.amber
                    ) {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                            selectedAnalysisChartType = chartType
                            selectedAnalysisRowID = nil
                        }
                    }
                }
            }

            if advancedAnalysisControlsEnabled {
                CompactToggleGroup {
                    switch selectedAnalysisChartType {
                    case .bar:
                        ForEach(OverviewBarOrientation.allCases) { orientation in
                            CompactIconButton(
                                systemImage: orientation.systemImage,
                                isSelected: selectedBarOrientation == orientation,
                                accessibilityLabel: "查看\(orientation.rawValue)柱状图",
                                tint: AppTheme.teal
                            ) {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                    selectedBarOrientation = orientation
                                    selectedAnalysisRowID = nil
                                }
                            }
                        }
                    case .pie:
                        ForEach(OverviewPieStyle.allCases) { style in
                            CompactIconButton(
                                systemImage: style.systemImage,
                                isSelected: selectedPieStyle == style,
                                accessibilityLabel: "查看\(style.rawValue)饼图",
                                tint: AppTheme.teal
                            ) {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                    selectedPieStyle = style
                                    selectedAnalysisRowID = nil
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func overviewSectionHeader<Actions: View>(
        title: String,
        subtitle: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            actions()
        }
        .padding(.horizontal, 2)
    }

    private func activeBudget(for period: SummaryPeriod) -> BudgetPlan? {
        budgets.first {
            $0.isEnabled && $0.period == period && $0.category == nil
        }
    }

    private func budgetPlan(for period: SummaryPeriod, includingDisabled: Bool) -> BudgetPlan? {
        budgets.first {
            (includingDisabled || $0.isEnabled) && $0.period == period && $0.category == nil
        }
    }

    private func spentAmount(for period: SummaryPeriod) -> Decimal {
        BillingAnalytics.total(BillingAnalytics.records(records, in: period))
    }

    private func suggestedBudgetAmount(for period: SummaryPeriod, spent: Decimal) -> Decimal {
        let spentValue = (spent as NSDecimalNumber).doubleValue
        let base: Double = switch period {
        case .day: max(spentValue * 1.2, 120)
        case .week: max(spentValue * 1.2, 800)
        case .month: max(spentValue * 1.2, 3600)
        case .quarter: max(spentValue * 1.2, 10000)
        case .year: max(spentValue * 1.2, 42000)
        }
        return Decimal(base.rounded())
    }

    private func saveBudget(period: SummaryPeriod, amount: Decimal, isEnabled: Bool) {
        if let budget = budgetPlan(for: period, includingDisabled: true) {
            budget.title = "\(period.rawValue)总预算"
            budget.amount = amount
            budget.isEnabled = isEnabled
        } else {
            let budget = BudgetPlan(
                title: "\(period.rawValue)总预算",
                period: period,
                amount: amount,
                isEnabled: isEnabled
            )
            modelContext.insert(budget)
        }
        try? modelContext.save()
    }

    private func budgetTint(spent: Decimal, limit: Decimal) -> Color {
        let spentValue = max((spent as NSDecimalNumber).doubleValue, 0)
        let limitValue = max((limit as NSDecimalNumber).doubleValue, 1)
        let ratio = spentValue / limitValue
        if ratio < 0.3 {
            return Color(red: 0.10, green: 0.62, blue: 0.32)
        } else if ratio < 0.7 {
            return Color(red: 0.92, green: 0.68, blue: 0.10)
        } else if ratio <= 1.0 {
            return Color(red: 0.88, green: 0.22, blue: 0.18)
        }
        return Color(red: 0.50, green: 0.00, blue: 0.04)
    }
}

private enum BudgetTrendScope: String, CaseIterable, Identifiable {
    case week = "周度"
    case month = "月度"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .week: "近 7 天每日支出"
        case .month: "近 6 个月每月支出"
        }
    }

    var systemImage: String {
        switch self {
        case .week: "calendar.day.timeline.left"
        case .month: "calendar"
        }
    }
}

private struct BudgetTrendBar: Identifiable {
    let id: String
    let label: String
    let amount: Decimal

    var magnitude: Double {
        max((amount as NSDecimalNumber).doubleValue, 0)
    }

    static func bars(from records: [ExpenseRecord], scope: BudgetTrendScope, now: Date = .now) -> [BudgetTrendBar] {
        let calendar = Calendar.current
        switch scope {
        case .week:
            let today = calendar.startOfDay(for: now)
            return (-6...0).compactMap { offset in
                guard let start = calendar.date(byAdding: .day, value: offset, to: today),
                      let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
                let scoped = records.filter { $0.occurredAt >= start && $0.occurredAt < end }
                return BudgetTrendBar(
                    id: "day-\(start.timeIntervalSince1970)",
                    label: offset == 0 ? "今天" : start.formatted(.dateTime.weekday(.narrow)),
                    amount: positiveTotal(scoped)
                )
            }
        case .month:
            let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (-5...0).compactMap { offset in
                guard let start = calendar.date(byAdding: .month, value: offset, to: currentMonth),
                      let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
                let scoped = records.filter { $0.occurredAt >= start && $0.occurredAt < end }
                let month = calendar.component(.month, from: start)
                return BudgetTrendBar(
                    id: "month-\(start.timeIntervalSince1970)",
                    label: "\(month)月",
                    amount: positiveTotal(scoped)
                )
            }
        }
    }

    private static func positiveTotal(_ records: [ExpenseRecord]) -> Decimal {
        records.reduce(Decimal.zero) { partial, record in
            record.amount > 0 ? partial + record.amount : partial
        }
    }
}

private struct BudgetRingButton: View {
    let period: SummaryPeriod
    let spent: Decimal
    let limit: Decimal
    let isEnabled: Bool
    let tint: Color
    let onEdit: () -> Void

    private var ratio: Double {
        let spentValue = max((spent as NSDecimalNumber).doubleValue, 0)
        let limitValue = max((limit as NSDecimalNumber).doubleValue, 1)
        return min(max(spentValue / limitValue, 0), 1)
    }

    private var percent: Int {
        let spentValue = max((spent as NSDecimalNumber).doubleValue, 0)
        let limitValue = max((limit as NSDecimalNumber).doubleValue, 1)
        return Int((spentValue / limitValue * 100).rounded())
    }

    var body: some View {
        Button(action: onEdit) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.13), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: ratio)
                        .stroke(tint.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text("\(percent)%")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.72)
                }
                .frame(width: 48, height: 48)

                VStack(spacing: 2) {
                    Text(period.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(compactCurrency(spent))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("设置\(period.rawValue)预算")
        .accessibilityValue("\(BillingAnalytics.currency(spent)) / \(BillingAnalytics.currency(limit))，已用 \(percent)%")
    }
}

private struct BudgetTrendBarChart: View {
    let bars: [BudgetTrendBar]

    private var maxMagnitude: Double {
        max(bars.map(\.magnitude).max() ?? 1, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                VStack(spacing: 7) {
                    Text(compactCurrency(bar.amount))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    RoundedRectangle(cornerRadius: 5)
                        .fill(overviewChartColor(index).gradient)
                        .frame(width: bars.count > 6 ? 24 : 30, height: max(10, 88 * bar.magnitude / maxMagnitude))
                        .opacity(bar.magnitude > 0 ? 1 : 0.28)

                    Text(bar.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 14)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(bar.label)，\(BillingAnalytics.currency(bar.amount))")
            }
        }
        .frame(height: 130, alignment: .bottom)
        .padding(.top, 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: bars.map(\.id).joined())
    }
}

private struct CompactToggleGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(3)
        .background(AppTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        }
    }
}

private struct CompactIconButton: View {
    let systemImage: String
    let isSelected: Bool
    let accessibilityLabel: String
    var accessibilityIdentifier: String? = nil
    var tint: Color = AppTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : tint)
                .frame(width: 30, height: 30)
                .background(isSelected ? tint : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .id("\(systemImage)-\(isSelected)-\(accessibilityLabel)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private func compactCurrency(_ amount: Decimal) -> String {
    let value = max((amount as NSDecimalNumber).doubleValue, 0)
    if value >= 10_000 {
        let text = String(format: "%.1f", value / 10_000)
            .replacingOccurrences(of: ".0", with: "")
        return "¥\(text)万"
    }
    if value >= 1_000 {
        return "¥\(Int(value.rounded()))"
    }
    if value >= 100 {
        return "¥\(Int(value.rounded()))"
    }
    return "¥\(String(format: "%.0f", value.rounded()))"
}

private enum OverviewAnalysisDimension: String, CaseIterable, Identifiable {
    case category = "消费类型"
    case time = "时间周期"
    case scene = "来源场景"
    case channel = "支付渠道"

    var id: String { rawValue }
}

private enum OverviewAnalysisChartType: String, CaseIterable, Identifiable {
    case bar = "柱状图"
    case pie = "饼图"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .bar: "chart.bar.xaxis"
        case .pie: "chart.pie.fill"
        }
    }
}

private enum OverviewBarOrientation: String, CaseIterable, Identifiable {
    case horizontal = "横向"
    case vertical = "竖向"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .horizontal: "align.horizontal.left.fill"
        case .vertical: "align.vertical.bottom.fill"
        }
    }
}

private enum OverviewPieStyle: String, CaseIterable, Identifiable {
    case hollow = "空心"
    case solid = "实心"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .hollow: "circle"
        case .solid: "circle.fill"
        }
    }

    var innerRatio: Double {
        switch self {
        case .hollow: 0.58
        case .solid: 0
        }
    }
}

private struct OverviewAggregateRowData: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let amount: Decimal
    let count: Int

    var magnitude: Double {
        abs((amount as NSDecimalNumber).doubleValue)
    }

    static func rows(
        from records: [ExpenseRecord],
        dimension: OverviewAnalysisDimension
    ) -> [OverviewAggregateRowData] {
        switch dimension {
        case .category:
            return groupedRows(
                records,
                dimension: dimension,
                title: { cleanTitle($0.categoryRaw, fallback: "其他") },
                subtitle: { _ in "消费类型" }
            )
        case .time:
            return groupedRows(
                records,
                dimension: dimension,
                title: { $0.occurredAt.formatted(.dateTime.month().day()) },
                subtitle: { _ in "发生日期" }
            )
        case .scene:
            return groupedRows(
                records,
                dimension: dimension,
                title: { cleanTitle($0.scene, fallback: "未标记场景") },
                subtitle: { _ in "来源场景" }
            )
        case .channel:
            return groupedRows(
                records,
                dimension: dimension,
                title: { cleanTitle($0.channelRaw, fallback: "其他") },
                subtitle: { _ in "支付渠道" }
            )
        }
    }

    private static func groupedRows(
        _ records: [ExpenseRecord],
        dimension: OverviewAnalysisDimension,
        title: (ExpenseRecord) -> String,
        subtitle: (String) -> String
    ) -> [OverviewAggregateRowData] {
        Dictionary(grouping: records, by: title)
            .map { key, values in
                OverviewAggregateRowData(
                    id: "\(dimension.id)-\(ExpenseCategoryCatalog.normalized(key))",
                    title: key,
                    subtitle: subtitle(key),
                    amount: BillingAnalytics.total(values),
                    count: values.count
                )
            }
            .sorted {
                if $0.magnitude == $1.magnitude {
                    return $0.count > $1.count
                }
                return $0.magnitude > $1.magnitude
            }
    }

    private static func cleanTitle(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private struct OverviewAggregateVisualizationView: View {
    let rows: [OverviewAggregateRowData]
    let chartType: OverviewAnalysisChartType
    let barOrientation: OverviewBarOrientation
    let pieStyle: OverviewPieStyle
    @Binding var selectedRowID: String?

    private var selectedRow: OverviewAggregateRowData? {
        rows.first { $0.id == selectedRowID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch chartType {
            case .bar:
                switch barOrientation {
                case .horizontal:
                    OverviewHorizontalBarChart(rows: rows, selectedRowID: $selectedRowID)
                case .vertical:
                    OverviewVerticalBarChart(rows: rows, selectedRowID: $selectedRowID)
                }
            case .pie:
                OverviewPieChartView(rows: rows, style: pieStyle, selectedRowID: $selectedRowID)
            }

            if chartType == .bar, let selectedRow {
                OverviewSelectedAggregateCard(row: selectedRow) {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        selectedRowID = nil
                    }
                }
                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: selectedRowID)
        .accessibilityIdentifier(chartType == .pie ? "消费分析饼图" : "消费分析柱状图")
    }
}

private struct OverviewHorizontalBarChart: View {
    let rows: [OverviewAggregateRowData]
    @Binding var selectedRowID: String?

    private var maxMagnitude: Double {
        max(rows.first?.magnitude ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(rows.prefix(10).enumerated()), id: \.element.id) { index, row in
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        selectedRowID = row.id
                    }
                } label: {
                    OverviewAggregateBarRow(
                        row: row,
                        color: overviewChartColor(index),
                        maxMagnitude: maxMagnitude,
                        isSelected: selectedRowID == row.id
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.title)，\(row.count) 笔，\(BillingAnalytics.currency(row.amount))")
            }

            if rows.count > 10 {
                Text("已展示金额最高的 10 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct OverviewVerticalBarChart: View {
    let rows: [OverviewAggregateRowData]
    @Binding var selectedRowID: String?

    private var limitedRows: [OverviewAggregateRowData] {
        Array(rows.prefix(12))
    }

    private var maxMagnitude: Double {
        max(limitedRows.first?.magnitude ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Array(limitedRows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                selectedRowID = row.id
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Text(BillingAnalytics.currency(row.amount))
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)

                                Capsule()
                                    .fill(overviewChartColor(index).gradient)
                                    .frame(width: 30, height: max(22, 132 * row.magnitude / maxMagnitude))
                                    .overlay {
                                        if selectedRowID == row.id {
                                            Capsule()
                                                .stroke(.primary.opacity(0.22), lineWidth: 2)
                                        }
                                    }

                                Text(row.title)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 58, height: 34, alignment: .top)
                            }
                            .frame(width: 64, height: 210, alignment: .bottom)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(row.title)，\(row.count) 笔，\(BillingAnalytics.currency(row.amount))")
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, 6)
            }

            if rows.count > limitedRows.count {
                Text("已展示金额最高的 \(limitedRows.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct OverviewAggregateBarRow: View {
    let row: OverviewAggregateRowData
    let color: Color
    let maxMagnitude: Double
    let isSelected: Bool

    private var ratio: Double {
        min(max(row.magnitude / maxMagnitude, 0.05), 1)
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
                    .fill(color.opacity(0.13))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.gradient)
                            .frame(width: proxy.size.width * ratio)
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(color.opacity(0.42), lineWidth: 1)
                        }
                    }
            }
            .frame(height: 8)
        }
        .padding(10)
        .background(isSelected ? color.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct OverviewPieChartView: View {
    let rows: [OverviewAggregateRowData]
    let style: OverviewPieStyle
    @Binding var selectedRowID: String?

    private var total: Double {
        max(rows.reduce(0) { $0 + $1.magnitude }, 0.01)
    }

    private var slices: [OverviewPieSlice] {
        var start = 0.0
        return rows.prefix(10).enumerated().map { index, row in
            let sweep = 360 * row.magnitude / total
            let slice = OverviewPieSlice(
                row: row,
                startDegrees: start,
                endDegrees: start + sweep,
                color: overviewChartColor(index)
            )
            start += sweep
            return slice
        }
    }

    private var selectedRow: OverviewAggregateRowData? {
        rows.first { $0.id == selectedRowID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { proxy in
                ZStack {
                    ForEach(slices) { slice in
                        OverviewPieSliceShape(
                            startDegrees: slice.startDegrees,
                            endDegrees: slice.endDegrees,
                            innerRatio: style.innerRatio
                        )
                        .fill(slice.color.gradient)
                        .scaleEffect(selectedRowID == slice.row.id ? 1.035 : 1)
                        .shadow(color: slice.color.opacity(selectedRowID == slice.row.id ? 0.22 : 0.08), radius: 10, x: 0, y: 5)
                    }

                    VStack(spacing: 4) {
                        Text(BillingAnalytics.currency(selectedRow?.amount ?? rows.reduce(Decimal.zero) { $0 + $1.amount }))
                            .font(.headline.weight(.bold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(selectedRow.map { "\($0.title) · \($0.count) 笔" } ?? "\(rows.reduce(0) { $0 + $1.count }) 笔")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(width: min(proxy.size.width, proxy.size.height) * 0.42)
                    .padding(style == .solid ? 9 : 0)
                    .background {
                        if style == .solid {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.regularMaterial)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard let slice = slice(at: value.location, in: proxy.size) else { return }
                            selectedRowID = slice.row.id
                        }
                )
            }
            .frame(height: 226)
            .accessibilityLabel("消费分析饼图")

            VStack(spacing: 8) {
                ForEach(slices) { slice in
                    Button {
                        selectedRowID = slice.row.id
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(slice.color)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(slice.row.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(slice.row.count) 笔 · \(Int(round((slice.endDegrees - slice.startDegrees) / 360 * 100)))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(BillingAnalytics.currency(slice.row.amount))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                        }
                        .padding(10)
                        .background(
                            selectedRowID == slice.row.id ? slice.color.opacity(0.12) : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(slice.row.title)，\(slice.row.count) 笔，\(BillingAnalytics.currency(slice.row.amount))")
                }
            }
        }
    }

    private func slice(at location: CGPoint, in size: CGSize) -> OverviewPieSlice? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let innerHitRadius = style == .hollow ? radius * 0.42 : 0
        guard distance >= innerHitRadius, distance <= radius else { return nil }

        var degrees = atan2(dy, dx) * 180 / .pi + 90
        if degrees < 0 { degrees += 360 }
        if degrees >= 360 { degrees -= 360 }

        return slices.first { degrees >= $0.startDegrees && degrees < $0.endDegrees }
            ?? slices.last
    }
}

private struct OverviewPieSlice: Identifiable {
    var id: String { row.id }
    let row: OverviewAggregateRowData
    let startDegrees: Double
    let endDegrees: Double
    let color: Color
}

private struct OverviewPieSliceShape: Shape {
    let startDegrees: Double
    let endDegrees: Double
    let innerRatio: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRatio
        let start = startDegrees - 90
        let end = endDegrees - 90
        var path = Path()

        path.move(to: point(center: center, radius: innerRadius, degrees: start))
        path.addLine(to: point(center: center, radius: outerRadius, degrees: start))
        path.addArc(center: center, radius: outerRadius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addLine(to: point(center: center, radius: innerRadius, degrees: end))
        path.addArc(center: center, radius: innerRadius, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }

    private func point(center: CGPoint, radius: Double, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

private struct OverviewSelectedAggregateCard: View {
    let row: OverviewAggregateRowData
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
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
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭消费分析详情")
        }
        .padding(12)
        .background(AppTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title)，\(row.count) 笔，\(BillingAnalytics.currency(row.amount))")
    }
}

private func overviewChartColor(_ index: Int) -> Color {
    let palette: [Color] = [
        AppTheme.accent,
        .teal,
        .orange,
        .indigo,
        .pink,
        .mint,
        .cyan,
        .purple,
        .brown,
        .green
    ]
    return palette[index % palette.count]
}

private struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let period: SummaryPeriod
    let budget: BudgetPlan?
    let suggestedAmount: Decimal
    let onSave: (Decimal, Bool) -> Void

    @State private var amountText: String
    @State private var isEnabled: Bool

    init(
        period: SummaryPeriod,
        budget: BudgetPlan?,
        suggestedAmount: Decimal,
        onSave: @escaping (Decimal, Bool) -> Void
    ) {
        self.period = period
        self.budget = budget
        self.suggestedAmount = suggestedAmount
        self.onSave = onSave

        let initialAmount = budget?.amount ?? suggestedAmount
        _amountText = State(initialValue: BudgetEditorView.amountFormatter.string(from: initialAmount as NSDecimalNumber) ?? "")
        _isEnabled = State(initialValue: budget?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("预算金额", text: $amountText)
                        .keyboardType(.decimalPad)
                    Toggle("启用\(period.rawValue)预算", isOn: $isEnabled)
                } header: {
                    Text("\(period.rawValue)预算")
                } footer: {
                    Text("建议值：\(BillingAnalytics.currency(suggestedAmount))。保存后会用于总览里的进度计算，不会影响历史消费记录。")
                }
            }
            .navigationTitle("设置预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let amount = parsedAmount {
                            onSave(amount, isEnabled)
                            dismiss()
                        }
                    }
                    .disabled(parsedAmount == nil)
                }
            }
        }
    }

    private var parsedAmount: Decimal? {
        let normalized = amountText
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Decimal(string: normalized), amount > 0 else { return nil }
        return amount
    }

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
