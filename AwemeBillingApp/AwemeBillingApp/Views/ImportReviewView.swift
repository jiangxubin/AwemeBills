import SwiftData
import SwiftUI

struct ImportReviewView: View {
    let candidates: [ParsedPaymentCandidate]
    var onAccepted: (ParsedPaymentCandidate) async -> Void
    var onAcceptedAll: ([ParsedPaymentCandidate]) async -> Void
    var onIgnored: (ParsedPaymentCandidate) -> Void

    private var pendingCandidates: [ParsedPaymentCandidate] {
        candidates.filter { $0.status == .pendingReview }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if pendingCandidates.isEmpty {
                EmptyStateView(title: "暂无待复核账单", systemImage: "checklist")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("\(pendingCandidates.count) 笔待确认", systemImage: "checklist")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(BillingAnalytics.currency(total(pendingCandidates)))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }

                    Button {
                        Task { await onAcceptedAll(pendingCandidates) }
                    } label: {
                        Label("全部确认入账", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(pendingCandidates.isEmpty ? .secondary : .primary)

                VStack(spacing: 12) {
                    ForEach(pendingCandidates) { candidate in
                        ImportCandidateRow(
                            candidate: candidate,
                            onAccept: {
                                await onAccepted(candidate)
                            },
                            onIgnore: {
                                onIgnored(candidate)
                            }
                        )
                    }
                }
            }
        }
    }

    private func total(_ items: [ParsedPaymentCandidate]) -> Decimal {
        items.reduce(Decimal.zero) { $0 + $1.amount }
    }
}

private struct ImportCandidateRow: View {
    @Query(sort: \ExpenseCategoryProfile.sortOrder) private var categoryProfiles: [ExpenseCategoryProfile]
    @Bindable var candidate: ParsedPaymentCandidate
    var onAccept: () async -> Void
    var onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MerchantLogoBadge(
                    merchant: candidate.merchant,
                    category: candidate.category,
                    rawText: candidate.rawText,
                    logoPNGData: candidate.merchantLogoPNGData,
                    size: 34
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.merchant)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(candidate.channelRaw) · \(candidate.statusRaw) · 置信度 \(Int(candidate.confidence * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Text(BillingAnalytics.currency(candidate.amount))
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }

            if candidate.status == .pendingReview {
                VStack(spacing: 10) {
                    TextField("商户", text: $candidate.merchant)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 10) {
                        TextField("金额", text: amountText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)

                        DatePicker("时间", selection: occurredAt, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }

                    HStack(spacing: 10) {
                        Picker("分类", selection: $candidate.categoryRaw) {
                            ForEach(categoryNames, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("渠道", selection: $candidate.channelRaw) {
                            ForEach(PaymentChannel.allCases) { channel in
                                Text(channel.rawValue).tag(channel.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    TextField("场景", text: $candidate.scene)
                        .textFieldStyle(.roundedBorder)

                    TextField("备注", text: noteText, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 10) {
                        Button(role: .destructive) {
                            onIgnore()
                        } label: {
                            Label("忽略", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await onAccept() }
                        } label: {
                            Label("确认入账", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(12)
        .background(statusColor.opacity(candidate.status == .pendingReview ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(candidate.status == .pendingReview ? 0.22 : 0.10), lineWidth: 1)
        }
    }

    private var categoryNames: [String] {
        ExpenseCategoryCatalog.visibleNames(from: categoryProfiles, including: candidate.categoryRaw)
    }

    private var amountText: Binding<String> {
        Binding {
            NSDecimalNumber(decimal: candidate.amount).stringValue
        } set: { value in
            let normalized = value
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let amount = Decimal(string: normalized) {
                candidate.amount = amount
            }
        }
    }

    private var occurredAt: Binding<Date> {
        Binding {
            candidate.occurredAt ?? .now
        } set: { value in
            candidate.occurredAt = value
        }
    }

    private var noteText: Binding<String> {
        Binding {
            candidate.note
        } set: { value in
            candidate.note = value
        }
    }

    private var statusColor: Color {
        switch candidate.status {
        case .pendingReview: AppTheme.accent
        case .accepted: .green
        case .ignored: .secondary
        case .duplicate: .orange
        case .failed: .red
        }
    }
}
