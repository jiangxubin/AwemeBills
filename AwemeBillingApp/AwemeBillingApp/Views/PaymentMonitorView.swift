import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct PaymentMonitorView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var rawText = "支付宝通知：你向咖啡店支付38.50元"
    @State private var parseMessage = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isParsingImage = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CapabilityRow(
                        title: "可落地接入",
                        systemImage: "checkmark.seal.fill",
                        text: "手动记账、账单文本粘贴、CSV/账单文件导入、通知文本解析。"
                    )
                    CapabilityRow(
                        title: "iOS 限制",
                        systemImage: "lock.shield.fill",
                        text: "普通 App 不能实时读取其他 App 的支付流水、通知内容或后台私有数据。"
                    )
                    CapabilityRow(
                        title: "后续扩展",
                        systemImage: "square.and.arrow.down.fill",
                        text: "可通过分享扩展、文件导入、邮箱账单、银行开放接口继续增强自动化。"
                    )
                } header: {
                    Text("支付宝 / 微信 / 云闪付")
                }

                Section("截图解析") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(selectedImage == nil ? "选择账单截图" : "更换账单截图", systemImage: "photo")
                    }

                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        Task { await parseSelectedImage() }
                    } label: {
                        if isParsingImage {
                            Label("正在解析", systemImage: "hourglass")
                        } else {
                            Label("解析截图并归档", systemImage: "text.viewfinder")
                        }
                    }
                    .disabled(selectedImage == nil || isParsingImage)

                    Text("会优先使用云端 OCR 解析；额度用尽或解析失败时，自动使用系统 OCR 兜底。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("通知或账单文本解析") {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 120)
                    Button {
                        parseAndSave()
                    } label: {
                        Label("解析并归档为消费", systemImage: "wand.and.stars")
                    }
                    if !parseMessage.isEmpty {
                        Text(parseMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("动账接入")
            .onChange(of: selectedPhoto) { _, newValue in
                Task { await loadImage(from: newValue) }
            }
        }
    }

    private func parseAndSave() {
        guard let payment = PaymentTextParser.parse(rawText) else {
            parseMessage = "没有识别到金额，请检查文本里是否包含 38.50 元这类金额。"
            return
        }

        let record = ExpenseRecord(
            amount: payment.amount,
            merchant: payment.merchant,
            category: payment.category,
            scene: "自动解析",
            channel: payment.channel,
            note: payment.note,
            occurredAt: payment.occurredAt ?? .now,
            isArchived: true
        )
        modelContext.insert(record)
        Task { await refreshSummaryNotifications() }
        parseMessage = "已保存：\(payment.channel.rawValue) · \(payment.merchant) · \(BillingAnalytics.currency(payment.amount))"
    }

    @MainActor
    private func parseSelectedImage() async {
        guard let selectedImage else { return }
        isParsingImage = true
        defer { isParsingImage = false }

        do {
            let payments = try await ReceiptImageParser.parseAll(image: selectedImage)
            guard !payments.isEmpty else {
                parseMessage = "截图里没有识别到可归档的消费记录。"
                return
            }

            for payment in payments {
                let record = ExpenseRecord(
                    amount: payment.amount,
                    merchant: payment.merchant,
                    category: payment.category,
                    scene: "截图解析",
                    channel: payment.channel,
                    note: payment.note,
                    occurredAt: payment.occurredAt ?? .now,
                    isArchived: true
                )
                modelContext.insert(record)
            }
            let total = payments.reduce(Decimal.zero) { $0 + $1.amount }
            await refreshSummaryNotifications()
            parseMessage = "已从截图保存 \(payments.count) 笔，共 \(BillingAnalytics.currency(total))"
        } catch {
            parseMessage = "截图解析失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshSummaryNotifications() async {
        do {
            let schedules = try modelContext.fetch(FetchDescriptor<ArchiveSchedule>())
            let records = try modelContext.fetch(FetchDescriptor<ExpenseRecord>())
            let reports = try modelContext.fetch(FetchDescriptor<ArchiveReport>())
            ArchiveReportService.generateMissingReports(
                schedules: schedules,
                records: records,
                existingReports: reports,
                context: modelContext
            )
            if try await ArchiveNotificationService.scheduleAll(schedules, records: records, requestAuthorizationIfNeeded: false) {
                try? modelContext.save()
            }
        } catch {
            print("Failed to refresh summary notifications: \(error)")
        }
    }

    @MainActor
    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImage = image
                parseMessage = "截图已载入，可以开始解析。"
            }
        } catch {
            parseMessage = "读取图片失败：\(error.localizedDescription)"
        }
    }
}

struct CapabilityRow: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 30, height: 30)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
