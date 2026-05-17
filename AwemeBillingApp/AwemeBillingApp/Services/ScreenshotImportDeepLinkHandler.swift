import Foundation
import Photos
import SwiftData
import UIKit

enum ScreenshotImportDeepLinkHandler {
    static func canHandle(_ url: URL) -> Bool {
        url.scheme == "awemebilling" && url.host == "import-latest-screenshot"
    }

    @MainActor
    static func handle(_ url: URL) async {
        guard canHandle(url) else { return }
        guard let image = await latestScreenshot() else { return }

        do {
            let payments = try await ReceiptImageParser.parseAll(image: image)
            guard !payments.isEmpty else { return }

            let context = ModelContext(DataController.sharedModelContainer)
            for payment in payments {
                let record = ExpenseRecord(
                    amount: payment.amount,
                    merchant: payment.merchant,
                    category: payment.category,
                    scene: "快捷指令截图导入",
                    channel: payment.channel,
                    note: payment.note,
                    occurredAt: payment.occurredAt ?? .now,
                    isArchived: true
                )
                context.insert(record)
            }
            try context.save()
        } catch {
            print("Failed to import latest screenshot: \(error)")
        }
    }

    private static func latestScreenshot() async -> UIImage? {
        let status = await requestPhotoAccess()
        guard status == .authorized || status == .limited else { return nil }

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )
        guard let screenshots = collections.firstObject else { return nil }

        let options = PHFetchOptions()
        options.fetchLimit = 1
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        guard let asset = PHAsset.fetchAssets(in: screenshots, options: options).firstObject else { return nil }
        return await image(for: asset)
    }

    private static func requestPhotoAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func image(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data.flatMap(UIImage.init(data:)))
            }
        }
    }
}
