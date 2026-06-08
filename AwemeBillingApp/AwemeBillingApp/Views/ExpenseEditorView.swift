import SwiftData
import SwiftUI

struct ExpenseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseCategoryProfile.sortOrder) private var categoryProfiles: [ExpenseCategoryProfile]
    private let editingRecord: ExpenseRecord?
    private let onSaved: (() -> Void)?

    @State private var amount = ""
    @State private var merchant = ""
    @State private var categoryRaw = ExpenseCategory.dining.rawValue
    @State private var scene = ""
    @State private var channel: PaymentChannel = .alipay
    @State private var note = ""
    @State private var occurredAt = Date()
    @State private var saveMessage = ""

    private var parsedAmount: Decimal? {
        Decimal(string: amount.replacingOccurrences(of: ",", with: ""))
    }

    init(record: ExpenseRecord? = nil, onSaved: (() -> Void)? = nil) {
        self.editingRecord = record
        self.onSaved = onSaved
        _amount = State(initialValue: record.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _merchant = State(initialValue: record?.merchant ?? "")
        _categoryRaw = State(initialValue: record?.categoryRaw ?? ExpenseCategory.dining.rawValue)
        _scene = State(initialValue: record?.scene ?? "")
        _channel = State(initialValue: record?.channel ?? .alipay)
        _note = State(initialValue: record?.note ?? "")
        _occurredAt = State(initialValue: record?.occurredAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("金额") {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.bold))
                    TextField("商户", text: $merchant)
                }

                Section("归类") {
                    Picker("分类", selection: $categoryRaw) {
                        ForEach(categoryNames, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    Picker("支付方式", selection: $channel) {
                        ForEach(PaymentChannel.allCases) { channel in
                            Text(channel.rawValue).tag(channel)
                        }
                    }
                    TextField("消费场景，例如通勤、家庭补货", text: $scene)
                }

                Section("时间与备注") {
                    DatePicker("发生时间", selection: $occurredAt)
                    TextField("备注", text: $note, axis: .vertical)
                }

                if !saveMessage.isEmpty {
                    Section {
                        Text(saveMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle(editingRecord == nil ? "新增消费" : "编辑消费")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(parsedAmount == nil || merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var categoryNames: [String] {
        ExpenseCategoryCatalog.visibleNames(from: categoryProfiles, including: categoryRaw)
    }

    @MainActor
    private func save() async {
        let draft = ManualExpenseDraft(
            amount: parsedAmount,
            merchant: merchant,
            categoryRaw: categoryRaw,
            scene: scene,
            channel: channel,
            note: note,
            occurredAt: occurredAt
        )

        switch await ManualExpenseImportService.save(draft: draft, editingRecord: editingRecord, context: modelContext) {
        case .created, .updated:
            onSaved?()
            dismiss()
        case .duplicate:
            saveMessage = "这笔消费已经存在，未重复保存。"
        case .invalid:
            saveMessage = "请补全金额和商户后再保存。"
        }
    }
}
