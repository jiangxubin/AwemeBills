import SwiftData
import SwiftUI

@main
struct AwemeBillingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task {
                        await ScreenshotImportDeepLinkHandler.handle(url)
                    }
                }
        }
        .modelContainer(DataController.sharedModelContainer)
    }
}
