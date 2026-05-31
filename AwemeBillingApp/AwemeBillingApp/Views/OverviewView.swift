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

    private var monthRecords: [ExpenseRecord] {
        BillingAnalytics.records(records, in: .month)
    }

    private var categoryTotals: [CategoryTotal] {
        BillingAnalytics.categoryTotals(monthRecords)
    }

    private var sceneTotals: [SceneTotal] {
        BillingAnalytics.sceneTotals(monthRecords)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    budgetSection
                    categorySection
                    recentSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
            .background(AppTheme.background)
            .navigationTitle("总览")
            .navigationBarTitleDisplayMode(.inline)
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

    private var summaryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("本月支出")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(BillingAnalytics.currency(BillingAnalytics.total(monthRecords)))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer()

                    Button(action: onManualImport) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("从总览手动导入")
                }

                HStack(spacing: 10) {
                    StatPill(title: "笔数", value: "\(monthRecords.count)")
                    StatPill(title: "已整理", value: "\(monthRecords.filter(\.isArchived).count)")
                    StatPill(title: "分类", value: "\(categoryTotals.count)")
                }
            }
        }
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "预算进度", subtitle: "每日到年度一屏对比，可单独设置")
            AppCard {
                VStack(spacing: 0) {
                    ForEach(budgetPeriods) { period in
                        let spent = spentAmount(for: period)
                        let plan = activeBudget(for: period)
                        let limit = plan?.amount ?? suggestedBudgetAmount(for: period, spent: spent)

                        BudgetProgressRow(
                            period: period,
                            spent: spent,
                            limit: limit,
                            hasCustomBudget: plan != nil,
                            isEnabled: plan?.isEnabled ?? false,
                            percentText: budgetPercentText(spent: spent, limit: limit),
                            tint: budgetTint(spent: spent, limit: limit)
                        ) {
                            editingBudgetPeriod = period
                        }

                        if period.id != budgetPeriods.last?.id {
                            Divider()
                                .padding(.leading, 46)
                                .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "分类总览", subtitle: "按金额排序")
            AppCard {
                if categoryTotals.isEmpty {
                    EmptyStateView(title: "暂无消费", systemImage: "tray")
                } else {
                    VStack(spacing: 16) {
                        ForEach(categoryTotals) { item in
                            AmountBarRow(
                                title: item.name,
                                amount: item.amount,
                                maxAmount: categoryTotals.first?.amount ?? 1
                            )
                        }
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        let recentRecords = Array(monthRecords.prefix(5))

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "最近消费", subtitle: "\(recentRecords.count) 笔")
            AppCard {
                if recentRecords.isEmpty {
                    EmptyStateView(title: "暂无明细", systemImage: "list.bullet.rectangle")
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentRecords) { record in
                            ExpenseRow(record: record)
                                .padding(.vertical, 12)
                            if let lastRecord = recentRecords.last, record !== lastRecord {
                                Divider()
                                    .padding(.leading, 48)
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

    private func budgetPercentText(spent: Decimal, limit: Decimal) -> String {
        let spentValue = (spent as NSDecimalNumber).doubleValue
        let limitValue = max((limit as NSDecimalNumber).doubleValue, 1)
        return "\(Int((spentValue / limitValue * 100).rounded()))%"
    }

    private func budgetTint(spent: Decimal, limit: Decimal) -> Color {
        spent > limit ? .red : AppTheme.accent
    }
}

private struct BudgetProgressRow: View {
    let period: SummaryPeriod
    let spent: Decimal
    let limit: Decimal
    let hasCustomBudget: Bool
    let isEnabled: Bool
    let percentText: String
    let tint: Color
    let onEdit: () -> Void

    private var remaining: Decimal {
        max(limit - spent, Decimal.zero)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: period.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(period.rawValue)
                            .font(.subheadline.weight(.semibold))
                        Text(hasCustomBudget && isEnabled ? "自定义" : "建议")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(hasCustomBudget && isEnabled ? AppTheme.accent : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((hasCustomBudget && isEnabled ? AppTheme.accent : Color.secondary).opacity(0.12), in: Capsule())
                    }

                    Text("\(BillingAnalytics.currency(spent)) / \(BillingAnalytics.currency(limit))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(percentText)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(tint)
                    Text("余 \(BillingAnalytics.currency(remaining))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("设置\(period.rawValue)预算")
            }

            BudgetProgressBar(spent: spent, limit: limit)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
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
