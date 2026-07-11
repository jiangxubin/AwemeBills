import SwiftUI
import UIKit

enum AppTheme {
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let elevatedCard = Color(.tertiarySystemGroupedBackground)
    static let ink = Color.primary
    static let accent = Color(red: 0.02, green: 0.38, blue: 0.78)
    static let success = Color(red: 0.04, green: 0.56, blue: 0.34)
    static let warning = Color(red: 0.86, green: 0.48, blue: 0.08)
    static let teal = success
    static let amber = warning
    static let cardStroke = Color.primary.opacity(0.08)
}

struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct AmountBarRow: View {
    let title: String
    let amount: Decimal
    let maxAmount: Decimal

    private var ratio: Double {
        let current = (amount as NSDecimalNumber).doubleValue
        let maximum = max((maxAmount as NSDecimalNumber).doubleValue, 1)
        return min(max(current / maximum, 0.05), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(BillingAnalytics.currency(amount))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.accent.opacity(0.12))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.accent)
                            .frame(width: proxy.size.width * ratio)
                    }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(BillingAnalytics.currency(amount))")
    }
}

struct BudgetProgressBar: View {
    let spent: Decimal
    let limit: Decimal

    private var ratio: Double {
        let spentValue = (spent as NSDecimalNumber).doubleValue
        let limitValue = max((limit as NSDecimalNumber).doubleValue, 1)
        return min(max(spentValue / limitValue, 0), 1)
    }

    private var tint: Color {
        spent > limit ? .red : AppTheme.accent
    }

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.10))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint)
                        .frame(width: max(proxy.size.width * ratio, ratio > 0 ? 8 : 0))
                }
        }
        .frame(height: 10)
        .accessibilityLabel("预算使用 \(Int((ratio * 100).rounded()))%")
    }
}

struct ExpenseRow: View {
    let record: ExpenseRecord
    var showsCreatedAt = false

    var body: some View {
        HStack(spacing: 12) {
            MerchantLogoBadge(
                merchant: record.merchant,
                category: record.category,
                rawText: record.note,
                logoPNGData: record.merchantLogoPNGData
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(record.merchant)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(record.categoryRaw) · \(record.scene) · \(record.channelRaw)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showsCreatedAt {
                    Text("录入：\(record.createdAt.formatted(.dateTime.year().month().day().hour().minute()))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(BillingAnalytics.currency(record.amount))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                Text(record.occurredAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.merchant)，\(BillingAnalytics.currency(record.amount))，\(record.categoryRaw)，\(record.channelRaw)")
    }
}

struct MerchantLogoBadge: View {
    let merchant: String
    let category: ExpenseCategory
    var rawText = ""
    var logoPNGData: Data?
    var size: CGFloat = 36

    private var style: MerchantLogoStyle {
        MerchantLogoStyle.resolve(merchant: merchant, category: category, rawText: rawText)
    }

    private var logoImage: UIImage? {
        logoPNGData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        Group {
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .padding(max(1, size * 0.06))
                    .frame(width: size, height: size)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(style.background)

                    if let systemImage = style.systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(style.foreground)
                    } else {
                        Text(style.label)
                            .font(.system(size: size * style.labelScale, weight: .black, design: .rounded))
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                            .foregroundStyle(style.foreground)
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.55), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

enum MerchantLogoKind: String {
    case meituan
    case dianping
    case tmall
    case taobao
    case jd
    case pinduoduo
    case eleme
    case hema
    case rtMart
    case sams
    case apple
    case yuebao
    case charging
    case category
}

struct MerchantLogoStyle {
    let kind: MerchantLogoKind
    let label: String
    let background: Color
    let foreground: Color
    let systemImage: String?
    var labelScale: CGFloat = 0.42

    static func resolve(merchant: String, category: ExpenseCategory, rawText: String = "") -> MerchantLogoStyle {
        let haystack = normalized([merchant, rawText].joined(separator: " "))

        if haystack.contains("美团") {
            return MerchantLogoStyle(kind: .meituan, label: "美团", background: Color(red: 1.00, green: 0.82, blue: 0.00), foreground: .black, systemImage: nil, labelScale: 0.34)
        }
        if haystack.contains("点评") || haystack.contains("大众点评") {
            return MerchantLogoStyle(kind: .dianping, label: "点", background: Color(red: 1.00, green: 0.45, blue: 0.12), foreground: .white, systemImage: nil)
        }
        if haystack.contains("天猫") || haystack.contains("tmall") {
            return MerchantLogoStyle(kind: .tmall, label: "天", background: Color(red: 0.82, green: 0.04, blue: 0.10), foreground: .white, systemImage: nil)
        }
        if haystack.contains("淘宝") || haystack.contains("taobao") {
            return MerchantLogoStyle(kind: .taobao, label: "淘", background: Color(red: 1.00, green: 0.39, blue: 0.06), foreground: .white, systemImage: nil)
        }
        if haystack.contains("京东") || haystack.contains("jd") {
            return MerchantLogoStyle(kind: .jd, label: "京", background: Color(red: 0.86, green: 0.05, blue: 0.10), foreground: .white, systemImage: nil)
        }
        if haystack.contains("拼多多") || haystack.contains("pdd") {
            return MerchantLogoStyle(kind: .pinduoduo, label: "拼", background: Color(red: 0.92, green: 0.08, blue: 0.10), foreground: .white, systemImage: nil)
        }
        if haystack.contains("饿了么") || haystack.contains("eleme") {
            return MerchantLogoStyle(kind: .eleme, label: "饿", background: Color(red: 0.04, green: 0.48, blue: 0.95), foreground: .white, systemImage: nil)
        }
        if haystack.contains("盒马") {
            return MerchantLogoStyle(kind: .hema, label: "盒", background: Color(red: 0.03, green: 0.46, blue: 0.85), foreground: .white, systemImage: nil)
        }
        if haystack.contains("大润发") {
            return MerchantLogoStyle(kind: .rtMart, label: "润", background: Color(red: 0.10, green: 0.45, blue: 0.92), foreground: .white, systemImage: nil)
        }
        if haystack.contains("山姆") || haystack.contains("sam") {
            return MerchantLogoStyle(kind: .sams, label: "S", background: Color(red: 0.02, green: 0.19, blue: 0.48), foreground: .white, systemImage: nil)
        }
        if haystack.contains("apple") || haystack.contains("苹果") {
            return MerchantLogoStyle(kind: .apple, label: "", background: Color(red: 0.08, green: 0.09, blue: 0.10), foreground: .white, systemImage: "apple.logo")
        }
        if haystack.contains("余额宝") {
            return MerchantLogoStyle(kind: .yuebao, label: "余", background: Color(red: 1.00, green: 0.36, blue: 0.10), foreground: .white, systemImage: nil)
        }
        if haystack.contains("耀汇充") || haystack.contains("充电") || haystack.contains("生活缴费") {
            return MerchantLogoStyle(kind: .charging, label: "", background: Color(red: 0.09, green: 0.68, blue: 0.38), foreground: .white, systemImage: "checkmark.circle.fill")
        }

        return categoryStyle(for: category, merchant: merchant)
    }

    private static func categoryStyle(for category: ExpenseCategory, merchant: String) -> MerchantLogoStyle {
        MerchantLogoStyle(
            kind: .category,
            label: fallbackInitial(from: merchant),
            background: categoryTint(for: category),
            foreground: .white,
            systemImage: systemImage(for: category),
            labelScale: 0.40
        )
    }

    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }

    private static func fallbackInitial(from merchant: String) -> String {
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map(String.init) ?? "?"
    }

    private static func systemImage(for category: ExpenseCategory) -> String {
        switch category {
        case .dining: "fork.knife"
        case .commute: "car.fill"
        case .shopping: "bag.fill"
        case .housing: "house.fill"
        case .health: "cross.case.fill"
        case .entertainment: "sparkles"
        case .travel: "airplane"
        case .education: "book.fill"
        case .transfer: "arrow.left.arrow.right"
        case .other: "ellipsis.circle.fill"
        }
    }

    private static func categoryTint(for category: ExpenseCategory) -> Color {
        switch category {
        case .dining: .orange
        case .commute: .blue
        case .shopping: .purple
        case .housing: .green
        case .health: .mint
        case .entertainment: .pink
        case .travel: .cyan
        case .education: .indigo
        case .transfer: .teal
        case .other: .gray
        }
    }
}
