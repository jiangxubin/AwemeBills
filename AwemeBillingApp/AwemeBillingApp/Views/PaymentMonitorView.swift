import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct PaymentMonitorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ParsedPaymentCandidate.createdAt, order: .reverse) private var candidates: [ParsedPaymentCandidate]
    @Query(sort: \ImportBatch.createdAt, order: .reverse) private var batches: [ImportBatch]
    @Binding var importMode: ImportMode
    let reviewRouteID: UUID
    @State private var rawText = ""
    @State private var importMessage = ""
    @State private var importSucceeded = false
    @State private var lastBatchID: String?
    @State private var reviewScope: ReviewScope = .allPending
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isParsingImage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    importCard
                    reviewCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 118)
            }
            .background(AppTheme.background)
            .navigationTitle("导入")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedPhoto) { _, newValue in
                Task { await loadImage(from: newValue) }
            }
            .onChange(of: reviewRouteID) { _, _ in
                focusReviewQueue()
            }
        }
    }

    private var heroCard: some View {
        AppCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text("导入消费")
                        .font(.title2.weight(.bold))
                    Text("从截图或通知文本解析金额、商户、时间和渠道；识别结果先复核，再入账。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "导入方式", subtitle: "截图 / 文本")
            AppCard {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsInfoRow(
                        title: "截图识别",
                        systemImage: "text.viewfinder",
                        text: "会自动识别账单截图；识别不到时自动换一种方式重试，结果先进入复核。"
                    )

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            ImportActionTile(
                                title: selectedImage == nil ? "截图导入" : "更换截图",
                                subtitle: selectedImage == nil ? "从相册选择" : "已载入",
                                systemImage: "photo.on.rectangle",
                                isSelected: importMode == .screenshot
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            importMode = .text
                        } label: {
                            ImportActionTile(
                                title: "文本解析",
                                subtitle: rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "粘贴通知" : "可解析",
                                systemImage: "text.viewfinder",
                                isSelected: importMode == .text
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    switch importMode {
                    case .screenshot:
                        screenshotImportControls
                    case .text:
                        textImportControls
                    }
                }
            }
        }
    }

    private var screenshotImportControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity)

                Button {
                    Task { await parseSelectedImage() }
                } label: {
                    Label(isParsingImage ? "正在解析截图" : "解析为待复核账单", systemImage: isParsingImage ? "hourglass" : "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isParsingImage)
            } else {
                EmptyStateView(title: "选择一张账单截图后开始解析", systemImage: "photo.on.rectangle")
            }
        }
    }

    private var textImportControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("通知文本")
                .font(.subheadline.weight(.semibold))

            ZStack(alignment: .topLeading) {
                TextEditor(text: $rawText)
                    .frame(minHeight: 118)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                if rawText.isEmpty {
                    Text("粘贴支付通知或账单文本")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }

            Button {
                parseTextToCandidates()
            } label: {
                Label("解析为待复核账单", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "导入复核", subtitle: reviewSubtitle)
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    reviewQueueSummary

                    if canSwitchReviewScope {
                        Picker("复核范围", selection: $reviewScope) {
                            ForEach(ReviewScope.allCases) { scope in
                                Text(scope.rawValue).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    ImportReviewView(
                        candidates: reviewCandidates,
                        onAccepted: { candidate in
                            await accept(candidate)
                        },
                        onAcceptedAll: { pendingCandidates in
                            await acceptAll(pendingCandidates)
                        },
                        onIgnored: { candidate in
                            ImportPipeline.ignore(candidate, context: modelContext)
                            try? modelContext.save()
                            clearCompletedReview(for: candidate.batchID)
                        }
                    )

                    if let duplicateText = duplicateSummaryText {
                        Label(duplicateText, systemImage: "doc.on.doc")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !importMessage.isEmpty {
                        Label(importMessage, systemImage: importSucceeded ? "checkmark.circle.fill" : "info.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(importSucceeded ? .green : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var reviewSubtitle: String {
        let pendingCount = pendingCandidates.count
        return pendingCount == 0 ? "无待确认" : "\(pendingCount) 笔待确认"
    }

    private var reviewCandidates: [ParsedPaymentCandidate] {
        let source = reviewScope == .currentBatch && !currentBatchPendingCandidates.isEmpty
            ? currentBatchPendingCandidates
            : pendingCandidates
        return Array(source.prefix(8))
    }

    private var pendingCandidates: [ParsedPaymentCandidate] {
        candidates.filter { $0.status == .pendingReview }
    }

    private var currentBatchPendingCandidates: [ParsedPaymentCandidate] {
        guard let lastBatchID else { return [] }
        return pendingCandidates.filter { $0.batchID == lastBatchID }
    }

    private var latestPendingBatch: ImportBatch? {
        batches.first { batch in
            pendingCandidates.contains { $0.batchID == batch.idString }
        }
    }

    private var currentBatch: ImportBatch? {
        guard let lastBatchID else { return nil }
        return batches.first { $0.idString == lastBatchID }
    }

    private var canSwitchReviewScope: Bool {
        !currentBatchPendingCandidates.isEmpty && pendingCandidates.count > currentBatchPendingCandidates.count
    }

    private var reviewQueueSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("\(pendingCandidates.count) 笔待复核", systemImage: "checklist")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let batch = visibleBatch {
                    Text(batch.source.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent.opacity(0.10), in: Capsule())
                }
            }

            Text(queueSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var queueSubtitle: String {
        if let batch = visibleBatch {
            let dateText = batch.createdAt.formatted(.dateTime.month().day().hour().minute())
            return "最近来自\(batch.source.rawValue) · \(dateText)。识别结果会先复核，再入账。"
        }
        return pendingCandidates.isEmpty
            ? "暂无待复核账单。可以导入截图、粘贴通知文本，或手动记一笔。"
            : "识别结果会先复核，再入账。"
    }

    private var visibleBatch: ImportBatch? {
        currentBatch ?? latestPendingBatch
    }

    private var duplicateSummaryText: String? {
        let scopedCandidates: [ParsedPaymentCandidate]
        if let lastBatchID {
            scopedCandidates = candidates.filter { $0.batchID == lastBatchID }
        } else {
            scopedCandidates = candidates
        }
        let duplicateCount = scopedCandidates.filter { $0.status == .duplicate }.count
        guard duplicateCount > 0 else { return nil }
        return "\(duplicateCount) 笔疑似重复，已按商户、金额、支付渠道和分钟级时间匹配标记。"
    }

    private func parseTextToCandidates() {
        let payments = PaymentTextParser.parseAll(rawText)
        guard !payments.isEmpty else {
            importSucceeded = false
            importMessage = "未识别出有效消费，请粘贴更完整的支付通知文本或手动记一笔。"
            return
        }

        let newCandidates = ImportPipeline.createBatch(
            source: .paste,
            rawText: rawText,
            payments: payments,
            scene: "文本解析",
            context: modelContext
        )
        let pending = newCandidates.filter { $0.status == .pendingReview }
        lastBatchID = newCandidates.first?.batchID
        reviewScope = pending.isEmpty ? .allPending : .currentBatch
        let duplicate = newCandidates.count - pending.count
        importSucceeded = !pending.isEmpty
        importMessage = duplicate > 0
            ? "已自动识别 \(pending.count) 笔待复核账单，另有 \(duplicate) 笔疑似重复。请核对金额和商户。"
            : "已自动识别 \(pending.count) 笔待复核账单，请核对金额和商户。"
    }

    @MainActor
    private func parseSelectedImage() async {
        guard let image = selectedImage else { return }
        isParsingImage = true
        defer { isParsingImage = false }

        do {
            let payments = try await ReceiptImageParser.parseAll(image: image)
            guard !payments.isEmpty else {
                importSucceeded = false
                importMessage = "未识别出有效消费，请粘贴通知文本或手动记一笔。"
                return
            }

            let rawText = payments.map(\.note).joined(separator: "\n---\n")
            let newCandidates = ImportPipeline.createBatch(
                source: .screenshot,
                rawText: rawText,
                payments: payments,
                scene: "截图解析",
                context: modelContext
            )
            selectedImage = nil
            selectedPhoto = nil
            let pending = newCandidates.filter { $0.status == .pendingReview }
            lastBatchID = newCandidates.first?.batchID
            reviewScope = pending.isEmpty ? .allPending : .currentBatch
            let skippedCount = newCandidates.count - pending.count
            importSucceeded = !pending.isEmpty
            importMessage = skippedCount > 0
                ? "已自动识别 \(pending.count) 笔待复核账单，另有 \(skippedCount) 笔疑似重复。请核对金额和商户。"
                : "已自动识别 \(pending.count) 笔待复核账单，请核对金额和商户。"
        } catch {
            importSucceeded = false
            importMessage = "截图识别暂时失败，请粘贴通知文本或手动记一笔。"
        }
    }

    @MainActor
    private func accept(_ candidate: ParsedPaymentCandidate) async {
        guard let record = ImportPipeline.accept(candidate, context: modelContext) else {
            importSucceeded = false
            importMessage = "这笔消费已存在，已标记为重复。"
            try? modelContext.save()
            return
        }
        try? modelContext.save()
        await refreshSummaryNotifications()
        importSucceeded = true
        importMessage = "已确认入账：\(record.merchant) \(BillingAnalytics.currency(record.amount))"
        clearCompletedReview(for: candidate.batchID)
    }

    @MainActor
    private func acceptAll(_ pendingCandidates: [ParsedPaymentCandidate]) async {
        var imported: [ExpenseRecord] = []
        var skipped = 0
        let batchID = pendingCandidates.first?.batchID

        for candidate in pendingCandidates where candidate.status == .pendingReview {
            if let record = ImportPipeline.accept(candidate, context: modelContext) {
                imported.append(record)
            } else {
                skipped += 1
            }
        }

        try? modelContext.save()
        await refreshSummaryNotifications()
        importSucceeded = !imported.isEmpty
        let totalText = BillingAnalytics.currency(imported.reduce(Decimal.zero) { $0 + $1.amount })
        importMessage = skipped > 0
            ? "已确认 \(imported.count) 笔入账，跳过 \(skipped) 笔重复，合计 \(totalText)。"
            : "已确认 \(imported.count) 笔入账，合计 \(totalText)。"
        clearCompletedReview(for: batchID)
    }

    @MainActor
    private func refreshSummaryNotifications() async {
        await ExpenseMutationService.refreshReportsAndNotifications(context: modelContext)
    }

    @MainActor
    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                importMode = .screenshot
                selectedImage = image.awemeBillingPreparedForOCR(maxPixelDimension: 2200)
                lastBatchID = nil
                reviewScope = .allPending
                importSucceeded = false
                importMessage = "截图已载入，可以开始解析。"
            }
        } catch {
            importSucceeded = false
            importMessage = "读取图片失败，请换一张截图再试。"
        }
    }

    private func clearCompletedReview(for batchID: String?) {
        guard let batchID, lastBatchID == batchID else { return }
        let hasPending = candidates.contains { $0.batchID == batchID && $0.status == .pendingReview }
        if !hasPending {
            lastBatchID = nil
        }
    }

    private func focusReviewQueue() {
        lastBatchID = (latestPendingBatch ?? batches.first)?.idString
        reviewScope = lastBatchID == nil ? .allPending : .currentBatch
        importSucceeded = false
        importMessage = ""
    }
}

enum ImportMode {
    case screenshot
    case text
}

private enum ReviewScope: String, CaseIterable, Identifiable {
    case currentBatch = "当前批次"
    case allPending = "全部待复核"

    var id: String { rawValue }
}

private struct ImportActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(12)
        .background(isSelected ? AppTheme.accent.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? AppTheme.accent.opacity(0.55) : Color.clear, lineWidth: 1)
        }
    }
}
