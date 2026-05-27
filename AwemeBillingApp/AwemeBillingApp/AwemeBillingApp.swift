import SwiftData
import SwiftUI

@main
struct AwemeBillingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(DataController.sharedModelContainer)
    }
}
