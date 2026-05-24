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
            let rawText = payments.map(\.note).joined(separator: "\n---\n")
            _ = ImportPipeline.createBatch(
                source: .shortcutURL,
                rawText: rawText,
                payments: payments,
                scene: "快捷指令截图导入",
                context: context
            )
        } catch {
            print("Failed to import latest screenshot: \(error)")
        }
    }

    @MainActor
    private static func refreshSummaryNotifications(context: ModelContext) async {
        let scheduleDescriptor = FetchDescriptor<ArchiveSchedule>()
        let recordDescriptor = FetchDescriptor<ExpenseRecord>()

        do {
            let schedules = try context.fetch(scheduleDescriptor)
            let records = try context.fetch(recordDescriptor)
            let reports = try context.fetch(FetchDescriptor<ArchiveReport>())
            ArchiveReportService.rebuildReports(
                schedules: schedules,
                records: records,
                existingReports: reports,
                context: context
            )
            if try await ArchiveNotificationService.scheduleAll(schedules, records: records, requestAuthorizationIfNeeded: false) {
                try? context.save()
            }
        } catch {
            print("Failed to refresh summary notifications: \(error)")
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
