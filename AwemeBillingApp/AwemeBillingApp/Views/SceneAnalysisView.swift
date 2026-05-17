import SwiftData
import SwiftUI

struct SceneAnalysisView: View {
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @State private var selectedPeriod: SummaryPeriod = .month

    private var scopedRecords: [ExpenseRecord] {
        BillingAnalytics.records(records, in: selectedPeriod)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("周期", selection: $selectedPeriod) {
                        ForEach([SummaryPeriod.week, .month, .quarter, .year]) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("场景排行") {
                    let totals = BillingAnalytics.sceneTotals(scopedRecords)
                    if totals.isEmpty {
                        ContentUnavailableView("暂无场景数据", systemImage: "map")
                    } else {
                        ForEach(totals) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(item.scene, systemImage: "mappin.and.ellipse")
                                        .font(.headline)
                                    Spacer()
                                    Text(BillingAnalytics.currency(item.amount))
                                        .font(.headline)
                                }
                                HStack {
                                    Text("\(item.count) 笔")
                                    Spacer()
                                    Text("均笔 \(BillingAnalytics.currency(item.amount / Decimal(item.count)))")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("支付渠道") {
                    let channelTotals = Dictionary(grouping: scopedRecords, by: \.channelRaw)
                        .map { CategoryTotal(name: $0.key, amount: BillingAnalytics.total($0.value)) }
                        .sorted { $0.amount > $1.amount }
                    ForEach(channelTotals) { item in
                        AmountBarRow(
                            title: item.name,
                            amount: item.amount,
                            maxAmount: channelTotals.first?.amount ?? 1
                        )
                    }
                }
            }
            .navigationTitle("消费场景")
        }
    }
}
