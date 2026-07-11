import SwiftData
import SwiftUI

struct OverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @Query(sort: \BudgetPlan.createdAt, order: .reverse) private var budgets: [BudgetPlan]
    @State private var editingBudgetPeriod: SummaryPeriod?

    let onManualImport: () -> Void

    private let budgetPeriods: [SummaryPeriod] = [.day, .week, .month, .quarter, .year]

    init(onManualImport: @escaping () -> Void = {}) {
        self.onManualImport = onManualImport
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    monthSummarySection
                    budgetSection
                    recentRecordsSection
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

    private var monthRecords: [ExpenseRecord] {
        BillingAnalytics.records(records, in: .month)
    }

    private var monthTotal: Decimal {
        BillingAnalytics.total(monthRecords)
    }

    private var topCategory: CategoryTotal? {
        BillingAnalytics.categoryTotals(monthRecords).first
    }

    private var recentRecords: [ExpenseRecord] {
        Array(records.prefix(5))
    }

    private var monthSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "本月", subtitle: "截至今天")
            AppCard {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本月支出")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(BillingAnalytics.currency(monthTotal))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    HStack(spacing: 0) {
                        summaryMetric(title: "记录", value: "\(monthRecords.count) 笔")
                        Divider()
                            .frame(height: 34)
                            .padding(.horizontal, 14)
                        summaryMetric(title: "主要分类", value: topCategory?.name ?? "暂无")
                        Divider()
                            .frame(height: 34)
                            .padding(.horizontal, 14)
                        summaryMetric(
                            title: "分类支出",
                            value: topCategory.map { BillingAnalytics.currency($0.amount) } ?? "--"
                        )
                    }

                    Button(action: onManualImport) {
                        Label("记一笔", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("总览记一笔")
                }
            }
        }
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "预算", subtitle: "点击周期设置")
            AppCard {
                VStack(spacing: 0) {
                    ForEach(Array(budgetPeriods.enumerated()), id: \.element) { index, period in
                        BudgetOverviewRow(
                            period: period,
                            spent: spentAmount(for: period),
                            plan: activeBudget(for: period),
                            suggestedAmount: suggestedBudgetAmount(
                                for: period,
                                spent: spentAmount(for: period)
                            )
                        ) {
                            editingBudgetPeriod = period
                        }
                        .padding(.vertical, 12)

                        if index < budgetPeriods.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var recentRecordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "最近记录", subtitle: recentRecords.isEmpty ? nil : "最近 \(recentRecords.count) 笔")
            AppCard {
                if recentRecords.isEmpty {
                    EmptyStateView(title: "还没有消费记录", systemImage: "list.bullet.rectangle")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(recentRecords.enumerated()), id: \.element.persistentModelID) { index, record in
                            ExpenseRow(record: record)
                                .padding(.vertical, 11)
                            if index < recentRecords.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
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
            modelContext.insert(
                BudgetPlan(
                    title: "\(period.rawValue)总预算",
                    period: period,
                    amount: amount,
                    isEnabled: isEnabled
                )
            )
        }
        try? modelContext.save()
    }
}

private struct BudgetOverviewRow: View {
    let period: SummaryPeriod
    let spent: Decimal
    let plan: BudgetPlan?
    let suggestedAmount: Decimal
    let action: () -> Void

    private var limit: Decimal {
        plan?.amount ?? suggestedAmount
    }

    private var ratio: Double {
        let spentValue = (spent as NSDecimalNumber).doubleValue
        let limitValue = max((limit as NSDecimalNumber).doubleValue, 1)
        return max(spentValue / limitValue, 0)
    }

    private var tint: Color {
        guard plan != nil else { return .secondary }
        if ratio > 1 { return .red }
        if ratio >= 0.8 { return AppTheme.warning }
        return AppTheme.success
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Text(period.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(BillingAnalytics.currency(spent))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(plan == nil ? "尚未启用预算" : "预算 \(BillingAnalytics.currency(limit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(plan == nil ? "设置" : "\(Int((ratio * 100).rounded()))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                BudgetProgressBar(spent: spent, limit: limit)
                    .opacity(plan == nil ? 0.45 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(period.rawValue)预算，已支出\(BillingAnalytics.currency(spent))")
    }
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
                    Text("建议值：\(BillingAnalytics.currency(suggestedAmount))。预算只用于提醒，不会修改历史消费记录。")
                }
            }
            .navigationTitle("设置预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
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
