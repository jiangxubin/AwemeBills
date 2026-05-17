import Foundation
import SwiftData

enum DataController {
    static let appGroupIdentifier = "group.com.aweme.billing.personal"

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ExpenseRecord.self,
            ArchiveSchedule.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(appGroupIdentifier),
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Cannot create SwiftData container: \(error)")
        }
    }()
}
