import Foundation

enum SummaryPeriod: String, CaseIterable, Identifiable {
    case day = "每日"
    case week = "每周"
    case month = "每月"
    case quarter = "每季度"
    case year = "每年"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .day: "sun.max.fill"
        case .week: "calendar.badge.clock"
        case .month: "calendar"
        case .quarter: "chart.bar.xaxis"
        case .year: "sparkles"
        }
    }

    var defaultDescription: String {
        switch self {
        case .day: "第二天上午九点"
        case .week: "下周第一天上午九点"
        case .month: "下个月第一天上午九点"
        case .quarter: "下个季度第一天上午九点"
        case .year: "第二年第一天上午九点"
        }
    }
}
