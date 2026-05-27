import SwiftData
import SwiftUI

struct OverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @Query(sort: \BudgetPlan.createdAt, order: .reverse) private var budgets: [BudgetPlan]
    @State private var selectedPeriod: SummaryPeriod = .month
    @State private var showingEditor = false

    private var scopedRecords: [ExpenseRecord] {
        BillingAnalytics.records(records, in: selectedPeriod)
    }

    private var categoryTotals: [CategoryTotal] {
        BillingAnalytics.categoryTotals(scopedRecords)
    }

    private var sceneTotals: [SceneTotal] {
        BillingAnalytics.sceneTotals(scopedRecords)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    periodPicker
                    summaryCard
                    quickActionSection
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
            .sheet(isPresented: $showingEditor) {
                ExpenseEditorView()
            }
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

    private var summaryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(selectedPeriod.rawValue)支出")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(BillingAnalytics.currency(BillingAnalytics.total(scopedRecords)))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer()

                    Image(systemName: selectedPeriod.iconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 10) {
                    StatPill(title: "笔数", value: "\(scopedRecords.count)")
                    StatPill(title: "已整理", value: "\(scopedRecords.filter(\.isArchived).count)")
                    StatPill(title: "分类", value: "\(categoryTotals.count)")
                }
            }
        }
    }

    private var quickActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "快速入账", subtitle: "手动补一笔")
            AppCard {
                OverviewActionButton(
                    title: "记一笔",
                    subtitle: "手动新增消费记录",
                    systemImage: "plus.circle",
                    action: { showingEditor = true }
                )
            }
        }
    }

    private var budgetSection: some View {
        let spent = BillingAnalytics.total(scopedRecords)
        let plan = activeBudget
        let limit = plan?.amount ?? suggestedBudgetAmount(for: spent)

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "预算执行", subtitle: plan == nil ? "建议预算" : plan?.title)
            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan == nil ? "尚未设置\(selectedPeriod.rawValue)预算" : "\(selectedPeriod.rawValue)预算")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(BillingAnalytics.currency(spent)) / \(BillingAnalytics.currency(limit))")
                                .font(.title3.weight(.bold).monospacedDigit())
                        }

                        Spacer()

                        Text(budgetPercentText(spent: spent, limit: limit))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(budgetTint(spent: spent, limit: limit))
                    }

                    BudgetProgressBar(spent: spent, limit: limit)

                    HStack(spacing: 10) {
                        StatPill(title: "剩余", value: BillingAnalytics.currency(max(limit - spent, Decimal.zero)))
                        StatPill(title: "状态", value: spent > limit ? "超支" : "正常")
                    }

                    if plan == nil {
                        Button {
                            createSuggestedBudget(spent: spent)
                        } label: {
                            Label("采用建议预算", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
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
        let recentRecords = Array(scopedRecords.prefix(5))

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "最近消费", subtitle: "\(recentRecords.count) 笔")
            AppCard {
                if recentRecords.isEmpty {
                    EmptyStateView(title: "暂无明细", systemImage: "list.bullet.rectangle")
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentRecords.indices, id: \.self) { index in
                            ExpenseRow(record: recentRecords[index])
                                .padding(.vertical, 12)
                            if index < recentRecords.count - 1 {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
            }
        }
    }

    private var activeBudget: BudgetPlan? {
        budgets.first {
            $0.isEnabled && $0.period == selectedPeriod && $0.category == nil
        }
    }

    private func suggestedBudgetAmount(for spent: Decimal) -> Decimal {
        let spentValue = (spent as NSDecimalNumber).doubleValue
        let base: Double = switch selectedPeriod {
        case .day: max(spentValue * 1.2, 120)
        case .week: max(spentValue * 1.2, 800)
        case .month: max(spentValue * 1.2, 3600)
        case .quarter: max(spentValue * 1.2, 10000)
        case .year: max(spentValue * 1.2, 42000)
        }
        return Decimal(base.rounded())
    }

    private func createSuggestedBudget(spent: Decimal) {
        let budget = BudgetPlan(
            title: "\(selectedPeriod.rawValue)总预算",
            period: selectedPeriod,
            amount: suggestedBudgetAmount(for: spent)
        )
        modelContext.insert(budget)
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

private struct OverviewActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .padding(12)
            .background(AppTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(subtitle)")
    }
}

struct AmountBarRow: View {
    let title: String
    let amount: Decimal
    let maxAmount: Decimal

    private var ratio: Double {
        let current = (amount as NSDecimalNumber).doubleValue
        let maximum = max((maxAmount as NSDecimalNumber).doubleValue, 1)
        return min(max(current / maximum, 0.05), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(BillingAnalytics.currency(amount))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
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
        .accessibilityLabel("\(title)，\(BillingAnalytics.currency(amount))")
    }
}

struct BudgetProgressBar: View {
    let spent: Decimal
    let limit: Decimal

    private var ratio: Double {
        let spentValue = (spent as NSDecimalNumber).doubleValue
        let limitValue = max((limit as NSDecimalNumber).doubleValue, 1)
        return min(max(spentValue / limitValue, 0), 1)
    }

    private var tint: Color {
        spent > limit ? .red : AppTheme.accent
    }

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.10))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint.gradient)
                        .frame(width: max(proxy.size.width * ratio, ratio > 0 ? 8 : 0))
                }
        }
        .frame(height: 10)
        .accessibilityLabel("预算使用 \(Int((ratio * 100).rounded()))%")
    }
}

struct ExpenseRow: View {
    let record: ExpenseRecord
    var showsCreatedAt = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: record.category))
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(categoryTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(categoryTint)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.merchant)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(record.categoryRaw) · \(record.scene) · \(record.channelRaw)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showsCreatedAt {
                    Text("录入：\(record.createdAt.formatted(.dateTime.year().month().day().hour().minute()))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(BillingAnalytics.currency(record.amount))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                Text(record.occurredAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.merchant)，\(BillingAnalytics.currency(record.amount))，\(record.categoryRaw)，\(record.channelRaw)")
    }

    private func iconName(for category: ExpenseCategory) -> String {
        switch category {
        case .dining: "fork.knife"
        case .commute: "tram.fill"
        case .shopping: "bag.fill"
        case .housing: "house.fill"
        case .health: "cross.case.fill"
        case .entertainment: "ticket.fill"
        case .travel: "airplane"
        case .education: "book.fill"
        case .transfer: "arrow.left.arrow.right"
        case .other: "ellipsis.circle.fill"
        }
    }

    private var categoryTint: Color {
        switch record.category {
        case .dining: .orange
        case .commute: .blue
        case .shopping: .purple
        case .housing: .brown
        case .health: .green
        case .entertainment: .pink
        case .travel: .cyan
        case .education: .indigo
        case .transfer: .teal
        case .other: .gray
        }
    }
}

enum AppTheme {
    static let background = Color(red: 0.965, green: 0.972, blue: 0.980)
    static let card = Color(.systemBackground)
    static let elevatedCard = Color(.secondarySystemGroupedBackground)
    static let ink = Color(red: 0.055, green: 0.067, blue: 0.090)
    static let accent = Color(red: 0.02, green: 0.38, blue: 0.78)
    static let teal = Color(red: 0.04, green: 0.62, blue: 0.54)
    static let amber = Color(red: 0.88, green: 0.50, blue: 0.12)
    static let accentGradient = LinearGradient(
        colors: [accent, teal],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let cardStroke = Color.black.opacity(0.06)
    static let softShadow = Color.black.opacity(0.07)
}

struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            }
            .shadow(color: AppTheme.softShadow, radius: 16, x: 0, y: 8)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
