import SwiftData
import SwiftUI

struct OverviewView: View {
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
                        ForEach([SummaryPeriod.day, .week, .month, .quarter, .year]) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(BillingAnalytics.currency(BillingAnalytics.total(scopedRecords)))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        HStack {
                            Label("\(scopedRecords.count) 笔", systemImage: "number")
                            Spacer()
                            Label("已归档 \(scopedRecords.filter(\.isArchived).count)", systemImage: "archivebox")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("分类总览") {
                    let totals = BillingAnalytics.categoryTotals(scopedRecords)
                    if totals.isEmpty {
                        ContentUnavailableView("暂无消费", systemImage: "tray")
                    } else {
                        ForEach(totals) { item in
                            AmountBarRow(
                                title: item.name,
                                amount: item.amount,
                                maxAmount: totals.first?.amount ?? 1
                            )
                        }
                    }
                }

                Section("最近消费") {
                    ForEach(scopedRecords.prefix(5)) { record in
                        ExpenseRow(record: record)
                    }
                }
            }
            .navigationTitle("消费总览")
        }
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
                    .font(.headline)
                Spacer()
                Text(BillingAnalytics.currency(amount))
                    .font(.subheadline.weight(.semibold))
            }
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.16))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
                            .frame(width: proxy.size.width * ratio)
                    }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }
}

struct ExpenseRow: View {
    let record: ExpenseRecord
    var showsCreatedAt = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: record.category))
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.merchant)
                    .font(.headline)
                Text("\(record.categoryRaw) · \(record.scene) · \(record.channelRaw)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showsCreatedAt {
                    Text("录入：\(record.createdAt.formatted(.dateTime.year().month().day().hour().minute()))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(BillingAnalytics.currency(record.amount))
                    .font(.headline)
                Text(record.occurredAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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
}
