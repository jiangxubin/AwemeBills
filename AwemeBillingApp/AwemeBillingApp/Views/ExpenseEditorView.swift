import SwiftData
import SwiftUI

struct ExpenseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    private let editingRecord: ExpenseRecord?

    @State private var amount = ""
    @State private var merchant = ""
    @State private var category: ExpenseCategory = .dining
    @State private var scene = ""
    @State private var channel: PaymentChannel = .alipay
    @State private var note = ""
    @State private var occurredAt = Date()
    @State private var saveMessage = ""

    private var parsedAmount: Decimal? {
        Decimal(string: amount.replacingOccurrences(of: ",", with: ""))
    }

    init(record: ExpenseRecord? = nil) {
        self.editingRecord = record
        _amount = State(initialValue: record.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _merchant = State(initialValue: record?.merchant ?? "")
        _category = State(initialValue: record?.category ?? .dining)
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
                    Picker("分类", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
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
                        save()
                    }
                    .disabled(parsedAmount == nil || merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let parsedAmount else { return }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let payment = ParsedPayment(
            amount: parsedAmount,
            merchant: trimmedMerchant,
            channel: channel,
            note: note,
            occurredAt: occurredAt,
            category: category
        )
        let existingRecords = ((try? modelContext.fetch(FetchDescriptor<ExpenseRecord>())) ?? [])
            .filter { $0 !== editingRecord }

        guard ExpenseRecordMaintenance.uniquePayments([payment], existing: existingRecords).first != nil else {
            saveMessage = "这笔消费已经存在，未重复保存。"
            return
        }

        if let editingRecord {
            editingRecord.amount = parsedAmount
            editingRecord.merchant = trimmedMerchant
            editingRecord.category = category
            editingRecord.scene = scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.rawValue : scene
            editingRecord.channel = channel
            editingRecord.note = note
            editingRecord.occurredAt = occurredAt
            PaymentRuleEngine.learnRule(from: editingRecord, context: modelContext)
            dismiss()
            return
        }

        let record = ExpenseRecord(
            amount: parsedAmount,
            merchant: trimmedMerchant,
            category: category,
            scene: scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.rawValue : scene,
            channel: channel,
            note: note,
            occurredAt: occurredAt
        )
        modelContext.insert(record)
        PaymentRuleEngine.learnRule(from: record, context: modelContext)
        dismiss()
    }
}
