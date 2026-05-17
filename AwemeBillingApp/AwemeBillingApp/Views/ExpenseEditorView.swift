import SwiftData
import SwiftUI

struct ExpenseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var amount = ""
    @State private var merchant = ""
    @State private var category: ExpenseCategory = .dining
    @State private var scene = ""
    @State private var channel: PaymentChannel = .alipay
    @State private var note = ""
    @State private var occurredAt = Date()

    private var parsedAmount: Decimal? {
        Decimal(string: amount.replacingOccurrences(of: ",", with: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("金额") {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
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
            }
            .navigationTitle("新增消费")
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
        let record = ExpenseRecord(
            amount: parsedAmount,
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            scene: scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.rawValue : scene,
            channel: channel,
            note: note,
            occurredAt: occurredAt
        )
        modelContext.insert(record)
        dismiss()
    }
}
