import Foundation
import SwiftData

@Model
final class ArchiveReport {
    var periodRaw: String
    var periodStart: Date
    var periodEnd: Date
    var generatedAt: Date
    var recordCount: Int
    var totalAmount: Decimal
    var topCategory: String
    var body: String

    init(
        period: SummaryPeriod,
        periodStart: Date,
        periodEnd: Date,
        generatedAt: Date = .now,
        recordCount: Int,
        totalAmount: Decimal,
        topCategory: String,
        body: String
    ) {
        self.periodRaw = period.rawValue
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.generatedAt = generatedAt
        self.recordCount = recordCount
        self.totalAmount = totalAmount
        self.topCategory = topCategory
        self.body = body
    }

    var period: SummaryPeriod {
        get { SummaryPeriod(rawValue: periodRaw) ?? .day }
        set { periodRaw = newValue.rawValue }
    }
}
