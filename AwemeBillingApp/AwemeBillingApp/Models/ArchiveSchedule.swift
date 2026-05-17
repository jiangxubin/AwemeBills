import Foundation
import SwiftData

@Model
final class ArchiveSchedule {
    var periodRaw: String
    var hour: Int
    var minute: Int
    var isEnabled: Bool
    var lastScheduledAt: Date?

    init(period: SummaryPeriod, hour: Int = 9, minute: Int = 0, isEnabled: Bool = true) {
        self.periodRaw = period.rawValue
        self.hour = hour
        self.minute = minute
        self.isEnabled = isEnabled
    }

    var period: SummaryPeriod {
        get { SummaryPeriod(rawValue: periodRaw) ?? .day }
        set { periodRaw = newValue.rawValue }
    }

    static func defaultSchedule(for period: SummaryPeriod) -> ArchiveSchedule {
        ArchiveSchedule(period: period, hour: 9, minute: 0, isEnabled: true)
    }
}
