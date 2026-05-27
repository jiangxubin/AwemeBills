import Foundation
import SwiftData

enum ImportPipeline {
    @MainActor
    static func createBatch(
        source: ImportSource,
        rawText: String,
        payments: [ParsedPayment],
        scene: String,
        context: ModelContext
    ) -> [ParsedPaymentCandidate] {
        let rules = (try? context.fetch(FetchDescriptor<PaymentRule>())) ?? []
        let records = (try? context.fetch(FetchDescriptor<ExpenseRecord>())) ?? []
        var seenRecordKeys = Set(records.map {
            ExpenseRecordMaintenance.deduplicationKey(
                amount: $0.amount,
                merchant: $0.merchant,
                category: $0.category,
                channel: $0.channel,
                occurredAt: $0.occurredAt
            )
        })
        var seenFingerprints = Set<String>()
        let importDate = Date()

        let batch = ImportBatch(
            source: source,
            rawText: rawText,
            sourceFingerprint: ImportFingerprint.text(rawText)
        )
        context.insert(batch)

        var candidates: [ParsedPaymentCandidate] = []
        var duplicateCount = 0

        for payment in payments {
            let (ruledPayment, ruledScene, confidence) = PaymentRuleEngine.applyRules(to: payment, rules: rules)
            let fingerprint = ImportFingerprint.candidate(payment: ruledPayment, rawText: ruledPayment.note.isEmpty ? rawText : ruledPayment.note)
            let recordKey = ExpenseRecordMaintenance.deduplicationKey(
                amount: ruledPayment.amount,
                merchant: ruledPayment.merchant,
                category: ruledPayment.category,
                channel: ruledPayment.channel,
                occurredAt: ruledPayment.occurredAt ?? importDate
            )
            let isDuplicate = seenRecordKeys.contains(recordKey) || seenFingerprints.contains(fingerprint)
            let status: ParsedPaymentCandidateStatus = isDuplicate ? .duplicate : .pendingReview

            if status == .duplicate {
                duplicateCount += 1
            } else {
                seenRecordKeys.insert(recordKey)
                seenFingerprints.insert(fingerprint)
            }

            let candidate = ParsedPaymentCandidate(
                batchID: batch.idString,
                payment: ruledPayment,
                scene: scene.isEmpty ? ruledScene : scene,
                rawText: rawText,
                sourceFingerprint: fingerprint,
                confidence: confidence,
                status: status
            )
            context.insert(candidate)
            candidates.append(candidate)
        }

        batch.duplicateCount = duplicateCount
        batch.status = candidates.allSatisfy { $0.status == .duplicate } ? .duplicate : .pendingReview
        try? context.save()
        return candidates
    }

    @MainActor
    static func accept(_ candidate: ParsedPaymentCandidate, context: ModelContext) -> ExpenseRecord? {
        guard candidate.status == .pendingReview else { return nil }

        let existingRecords = (try? context.fetch(FetchDescriptor<ExpenseRecord>())) ?? []
        guard ExpenseRecordMaintenance.uniquePayments([candidate.payment], existing: existingRecords).first != nil else {
            candidate.status = .duplicate
            updateBatch(for: candidate, context: context)
            return nil
        }

        let record = ExpenseRecord(
            amount: candidate.amount,
            merchant: candidate.merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            category: candidate.category,
            scene: candidate.scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? candidate.category.rawValue : candidate.scene,
            channel: candidate.channel,
            note: candidate.note,
            occurredAt: candidate.occurredAt ?? .now,
            isArchived: true
        )
        context.insert(record)
        candidate.status = .accepted
        PaymentRuleEngine.learnRule(from: record, context: context)
        updateBatch(for: candidate, context: context)
        return record
    }

    @MainActor
    static func ignore(_ candidate: ParsedPaymentCandidate, context: ModelContext) {
        candidate.status = .ignored
        updateBatch(for: candidate, context: context)
    }

    @MainActor
    static func updateBatch(for candidate: ParsedPaymentCandidate, context: ModelContext) {
        let batchID = candidate.batchID
        let batchDescriptor = FetchDescriptor<ImportBatch>(
            predicate: #Predicate { batch in
                batch.idString == batchID
            }
        )
        guard let batch = try? context.fetch(batchDescriptor).first else { return }

        let candidateDescriptor = FetchDescriptor<ParsedPaymentCandidate>(
            predicate: #Predicate { item in
                item.batchID == batchID
            }
        )
        let candidates = (try? context.fetch(candidateDescriptor)) ?? []
        batch.acceptedCount = candidates.filter { $0.status == .accepted }.count
        batch.duplicateCount = candidates.filter { $0.status == .duplicate }.count
        batch.failedCount = candidates.filter { $0.status == .failed }.count

        if candidates.contains(where: { $0.status == .pendingReview }) {
            batch.status = .pendingReview
        } else if batch.acceptedCount > 0, batch.acceptedCount < candidates.count {
            batch.status = .partial
        } else if batch.acceptedCount == candidates.count, !candidates.isEmpty {
            batch.status = .accepted
        } else if batch.duplicateCount == candidates.count, !candidates.isEmpty {
            batch.status = .duplicate
        } else if !candidates.isEmpty, candidates.allSatisfy({ $0.status == .ignored }) {
            batch.status = .ignored
        } else {
            batch.status = .failed
        }
    }
}
