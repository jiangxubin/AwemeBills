import Foundation
import SwiftData

struct ManualExpenseDraft {
    var amount: Decimal?
    var merchant: String
    var category: ExpenseCategory
    var scene: String
    var channel: PaymentChannel
    var note: String
    var occurredAt: Date

    var trimmedMerchant: String {
        merchant.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedScene: String {
        let trimmedScene = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedScene.isEmpty ? category.rawValue : trimmedScene
    }

    var parsedPayment: ParsedPayment? {
        guard let amount, amount > 0, !trimmedMerchant.isEmpty else { return nil }
        return ParsedPayment(
            amount: amount,
            merchant: trimmedMerchant,
            channel: channel,
            note: note,
            occurredAt: occurredAt,
            category: category
        )
    }
}

enum ManualExpenseImportResult {
    case created(ExpenseRecord)
    case updated(ExpenseRecord)
    case duplicate
    case invalid
}

enum ManualExpenseImportService {
    @MainActor
    static func save(
        draft: ManualExpenseDraft,
        editingRecord: ExpenseRecord? = nil,
        context: ModelContext,
        refreshAfterSave: Bool = true
    ) async -> ManualExpenseImportResult {
        guard let payment = draft.parsedPayment else { return .invalid }

        let existingRecords = ((try? context.fetch(FetchDescriptor<ExpenseRecord>())) ?? [])
            .filter { $0 !== editingRecord }

        guard ExpenseRecordMaintenance.uniquePayments([payment], existing: existingRecords).first != nil else {
            return .duplicate
        }

        if let editingRecord {
            apply(draft: draft, amount: payment.amount, to: editingRecord)
            PaymentRuleEngine.learnRule(from: editingRecord, context: context)
            try? context.save()
            if refreshAfterSave {
                await ExpenseMutationService.refreshReportsAndNotifications(context: context)
            }
            return .updated(editingRecord)
        }

        let record = ExpenseRecord(
            amount: payment.amount,
            merchant: draft.trimmedMerchant,
            category: draft.category,
            scene: draft.normalizedScene,
            channel: draft.channel,
            note: draft.note,
            occurredAt: draft.occurredAt
        )
        context.insert(record)
        PaymentRuleEngine.learnRule(from: record, context: context)
        try? context.save()
        if refreshAfterSave {
            await ExpenseMutationService.refreshReportsAndNotifications(context: context)
        }
        return .created(record)
    }

    private static func apply(draft: ManualExpenseDraft, amount: Decimal, to record: ExpenseRecord) {
        record.amount = amount
        record.merchant = draft.trimmedMerchant
        record.category = draft.category
        record.scene = draft.normalizedScene
        record.channel = draft.channel
        record.note = draft.note
        record.occurredAt = draft.occurredAt
    }
}
