import Foundation
import SwiftData

struct ManualExpenseDraft {
    var amount: Decimal?
    var merchant: String
    var categoryRaw: String
    var scene: String
    var channel: PaymentChannel
    var note: String
    var occurredAt: Date

    var trimmedMerchant: String {
        merchant.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedScene: String {
        let trimmedScene = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedScene.isEmpty ? trimmedCategory : trimmedScene
    }

    var trimmedCategory: String {
        let trimmed = categoryRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ExpenseCategory.other.rawValue : trimmed
    }

    var category: ExpenseCategory {
        ExpenseCategory(rawValue: trimmedCategory) ?? .other
    }

    var parsedPayment: ParsedPayment? {
        guard let amount, amount > 0, !trimmedMerchant.isEmpty else { return nil }
        return ParsedPayment(
            amount: amount,
            merchant: trimmedMerchant,
            channel: channel,
            note: note,
            occurredAt: occurredAt,
            category: category,
            categoryRaw: trimmedCategory
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

        let draftKey = ExpenseRecordMaintenance.deduplicationKey(
            amount: payment.amount,
            merchant: draft.trimmedMerchant,
            categoryRaw: draft.trimmedCategory,
            channelRaw: draft.channel.rawValue,
            occurredAt: draft.occurredAt
        )
        let existingKeys = Set(existingRecords.map {
            ExpenseRecordMaintenance.deduplicationKey(
                amount: $0.amount,
                merchant: $0.merchant,
                categoryRaw: $0.categoryRaw,
                channelRaw: $0.channelRaw,
                occurredAt: $0.occurredAt
            )
        })

        guard !existingKeys.contains(draftKey) else {
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
            categoryRaw: draft.trimmedCategory,
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
        record.categoryRaw = draft.trimmedCategory
        record.scene = draft.normalizedScene
        record.channel = draft.channel
        record.note = draft.note
        record.occurredAt = draft.occurredAt
    }
}
