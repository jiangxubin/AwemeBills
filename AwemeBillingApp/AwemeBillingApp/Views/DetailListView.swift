import SwiftData
import SwiftUI

struct DetailListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @State private var showingEditor = false
    @State private var selectedCategory: ExpenseCategory?

    private var filteredRecords: [ExpenseRecord] {
        guard let selectedCategory else { return records }
        return records.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            CategoryChip(title: "全部", isSelected: selectedCategory == nil) {
                                selectedCategory = nil
                            }
                            ForEach(ExpenseCategory.allCases) { category in
                                CategoryChip(title: category.rawValue, isSelected: selectedCategory == category) {
                                    selectedCategory = category
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                ForEach(BillingAnalytics.dateGroupedRecords(filteredRecords), id: \.0) { date, dayRecords in
                    Section {
                        ForEach(dayRecords) { record in
                            ExpenseRow(record: record, showsCreatedAt: true)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(record)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        record.isArchived.toggle()
                                    } label: {
                                        Label(record.isArchived ? "取消归档" : "归档", systemImage: "archivebox")
                                    }
                                    .tint(.teal)
                                }
                        }
                    } header: {
                        Text(date, format: .dateTime.year().month().day().weekday())
                    }
                }
            }
            .navigationTitle("消费明细")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增消费")
                }
            }
            .sheet(isPresented: $showingEditor) {
                ExpenseEditorView()
            }
        }
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
