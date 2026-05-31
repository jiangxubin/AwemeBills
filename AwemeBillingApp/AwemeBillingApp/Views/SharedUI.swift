import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.965, green: 0.972, blue: 0.980)
    static let card = Color(.systemBackground)
    static let elevatedCard = Color(.secondarySystemGroupedBackground)
    static let ink = Color(red: 0.055, green: 0.067, blue: 0.090)
    static let accent = Color(red: 0.02, green: 0.38, blue: 0.78)
    static let teal = Color(red: 0.04, green: 0.62, blue: 0.54)
    static let amber = Color(red: 0.88, green: 0.50, blue: 0.12)
    static let accentGradient = LinearGradient(
        colors: [accent, teal],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let cardStroke = Color.black.opacity(0.06)
    static let softShadow = Color.black.opacity(0.07)
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
            .shadow(color: AppTheme.softShadow, radius: 16, x: 0, y: 8)
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

struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        }
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
                            .fill(AppTheme.accentGradient)
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
                        .fill(tint.gradient)
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
            Image(systemName: iconName(for: record.category))
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(categoryTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(categoryTint)

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

    private func iconName(for category: ExpenseCategory) -> String {
        switch category {
        case .dining: "fork.knife"
        case .commute: "tram.fill"
        case .shopping: "bag.fill"
        case .housing: "house.fill"
        case .health: "cross.case.fill"
        case .entertainment: "ticket.fill"
        case .travel: "airplane"
        case .education: "book.fill"
        case .transfer: "arrow.left.arrow.right"
        case .other: "ellipsis.circle.fill"
        }
    }

    private var categoryTint: Color {
        switch record.category {
        case .dining: .orange
        case .commute: .blue
        case .shopping: .purple
        case .housing: .brown
        case .health: .green
        case .entertainment: .pink
        case .travel: .cyan
        case .education: .indigo
        case .transfer: .teal
        case .other: .gray
        }
    }
}
