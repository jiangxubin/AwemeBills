import SwiftData
import SwiftUI

struct SceneAnalysisView: View {
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @State private var selectedPeriod: SummaryPeriod = .month

    private var scopedRecords: [ExpenseRecord] {
        BillingAnalytics.records(records, in: selectedPeriod)
    }

    private var sceneTotals: [SceneTotal] {
        BillingAnalytics.sceneTotals(scopedRecords)
    }

    private var channelTotals: [CategoryTotal] {
        Dictionary(grouping: scopedRecords, by: \.channelRaw)
            .map { CategoryTotal(name: $0.key, amount: BillingAnalytics.total($0.value)) }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("周期", selection: $selectedPeriod) {
                        ForEach([SummaryPeriod.week, .month, .quarter, .year]) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    insightCard
                    sceneSection
                    channelSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
            .background(AppTheme.background)
            .navigationTitle("场景")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var insightCard: some View {
        let topScene = sceneTotals.first

        return AppCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("主要消费场景")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(topScene?.scene ?? "暂无数据")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    Spacer()
                    Image(systemName: "sparkline")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 10) {
                    StatPill(title: "场景", value: "\(sceneTotals.count)")
                    StatPill(title: "笔数", value: "\(scopedRecords.count)")
                    StatPill(title: "总额", value: BillingAnalytics.currency(BillingAnalytics.total(scopedRecords)))
                }
            }
        }
    }

    private var sceneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "场景排行", subtitle: "均笔 / 笔数")
            AppCard {
                if sceneTotals.isEmpty {
                    EmptyStateView(title: "暂无场景数据", systemImage: "map")
                } else {
                    VStack(spacing: 16) {
                        ForEach(sceneTotals) { item in
                            SceneRankRow(item: item, maxAmount: sceneTotals.first?.amount ?? 1)
                        }
                    }
                }
            }
        }
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "支付渠道", subtitle: "按金额排序")
            AppCard {
                if channelTotals.isEmpty {
                    EmptyStateView(title: "暂无渠道数据", systemImage: "creditcard")
                } else {
                    VStack(spacing: 16) {
                        ForEach(channelTotals) { item in
                            AmountBarRow(
                                title: item.name,
                                amount: item.amount,
                                maxAmount: channelTotals.first?.amount ?? 1
                            )
                        }
                    }
                }
            }
        }
    }
}

struct SceneRankRow: View {
    let item: SceneTotal
    let maxAmount: Decimal

    private var ratio: Double {
        let current = (item.amount as NSDecimalNumber).doubleValue
        let maximum = max((maxAmount as NSDecimalNumber).doubleValue, 1)
        return min(max(current / maximum, 0.05), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(item.scene, systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(BillingAnalytics.currency(item.amount))
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

            HStack {
                Text("\(item.count) 笔")
                Spacer()
                Text("均笔 \(BillingAnalytics.currency(item.amount / Decimal(item.count)))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
