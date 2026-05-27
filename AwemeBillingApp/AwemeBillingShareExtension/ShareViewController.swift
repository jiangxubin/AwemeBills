import SwiftData
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        Task { await processSharedImage() }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        statusLabel.text = "正在解析账单截图..."
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .headline)

        activityIndicator.startAnimating()

        let stack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel])
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    @MainActor
    private func processSharedImage() async {
        do {
            guard let image = try await loadFirstSharedImage() else {
                finish(message: "没有找到可解析的图片。")
                return
            }

            let payments = try await ReceiptImageParser.parseAll(image: image)
            guard !payments.isEmpty else {
                finish(message: "未识别到消费记录。")
                return
            }

            let context = ModelContext(DataController.sharedModelContainer)
            let rawText = payments.map(\.note).joined(separator: "\n---\n")
            let candidates = ImportPipeline.createBatch(
                source: .shareExtension,
                rawText: rawText,
                payments: payments,
                scene: "相册分享",
                context: context
            )
            try context.save()

            let pendingCount = candidates.filter { $0.status == .pendingReview }.count
            let duplicateCount = candidates.count - pendingCount
            let message = pendingCount == 0
                ? "识别到的消费都已存在。"
                : duplicateCount > 0
                    ? "已生成 \(pendingCount) 笔待复核，跳过 \(duplicateCount) 笔重复。"
                    : "已生成 \(pendingCount) 笔待复核账单。"
            finish(message: message, openMainApp: pendingCount > 0)
        } catch {
            finish(message: "解析失败：\(error.localizedDescription)")
        }
    }

    private func finish(message: String, openMainApp: Bool = false) {
        activityIndicator.stopAnimating()
        statusLabel.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if openMainApp, let url = URL(string: "awemebilling://review-import") {
                self.extensionContext?.open(url) { _ in
                    self.extensionContext?.completeRequest(returningItems: nil)
                }
            } else {
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    private func loadFirstSharedImage() async throws -> UIImage? {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments
        else { return nil }

        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.image.identifier)

            if let image = item as? UIImage {
                return image
            }

            if let url = item as? URL,
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                return image
            }

            if let data = item as? Data,
               let image = UIImage(data: data) {
                return image
            }
        }

        return nil
    }
}

private extension NSItemProvider {
    func loadItem(forTypeIdentifier typeIdentifier: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item)
                }
            }
        }
    }
}
