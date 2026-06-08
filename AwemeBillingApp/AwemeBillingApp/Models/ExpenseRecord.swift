import AppIntents
import Foundation
import SwiftData

enum ExpenseCategory: String, AppEnum, CaseIterable, Identifiable {
    case dining = "餐饮"
    case commute = "交通"
    case shopping = "购物"
    case housing = "居家"
    case health = "健康"
    case entertainment = "娱乐"
    case travel = "旅行"
    case education = "学习"
    case transfer = "转账"
    case other = "其他"

    var id: String { rawValue }

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "消费分类")

    static var caseDisplayRepresentations: [ExpenseCategory: DisplayRepresentation] = [
        .dining: "餐饮",
        .commute: "交通",
        .shopping: "购物",
        .housing: "居家",
        .health: "健康",
        .entertainment: "娱乐",
        .travel: "旅行",
        .education: "学习",
        .transfer: "转账",
        .other: "其他"
    ]
}

enum PaymentChannel: String, AppEnum, CaseIterable, Identifiable {
    case alipay = "支付宝"
    case wechat = "微信支付"
    case unionPay = "云闪付"
    case bankCard = "银行卡"
    case cash = "现金"
    case other = "其他"

    var id: String { rawValue }

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "支付渠道")

    static var caseDisplayRepresentations: [PaymentChannel: DisplayRepresentation] = [
        .alipay: "支付宝",
        .wechat: "微信支付",
        .unionPay: "云闪付",
        .bankCard: "银行卡",
        .cash: "现金",
        .other: "其他"
    ]
}

@Model
final class ExpenseCategoryProfile: Identifiable {
    @Attribute(.unique) var idString: String
    var name: String
    var systemImage: String
    var isBuiltIn: Bool
    var semanticRawName: String?
    var isEnabled: Bool
    var sortOrder: Int
    var createdAt: Date

    var id: String { idString }

    init(
        name: String,
        systemImage: String,
        isBuiltIn: Bool,
        semanticRawName: String? = nil,
        isEnabled: Bool = true,
        sortOrder: Int,
        createdAt: Date = .now
    ) {
        self.idString = UUID().uuidString
        self.name = name
        self.systemImage = systemImage
        self.isBuiltIn = isBuiltIn
        self.semanticRawName = semanticRawName
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

enum ExpenseCategoryCatalog {
    static func defaultProfiles() -> [ExpenseCategoryProfile] {
        ExpenseCategory.allCases.enumerated().map { index, category in
            ExpenseCategoryProfile(
                name: category.rawValue,
                systemImage: systemImage(for: category.rawValue),
                isBuiltIn: true,
                semanticRawName: category.rawValue,
                sortOrder: index
            )
        }
    }

    @discardableResult
    @MainActor
    static func ensureDefaults(
        profiles: [ExpenseCategoryProfile],
        context: ModelContext
    ) -> [ExpenseCategoryProfile] {
        let defaults = defaultProfiles()
        var existingNames = Set(profiles.map { normalized($0.name) })
        var existingBuiltInSemantics = Set<String>()
        var combined = profiles

        for profile in combined where profile.isBuiltIn {
            let semantic = profile.semanticRawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if semantic.isEmpty {
                if let exactCategory = ExpenseCategory(rawValue: profile.name) {
                    profile.semanticRawName = exactCategory.rawValue
                } else if defaults.indices.contains(profile.sortOrder) {
                    profile.semanticRawName = defaults[profile.sortOrder].semanticRawName
                }
            }

            if let semantic = profile.semanticRawName,
               !semantic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existingBuiltInSemantics.insert(normalized(semantic))
            }
        }

        for defaultProfile in defaults {
            let semantic = defaultProfile.semanticRawName ?? defaultProfile.name
            guard !existingBuiltInSemantics.contains(normalized(semantic)) else { continue }
            guard !existingNames.contains(normalized(defaultProfile.name)) else { continue }
            context.insert(defaultProfile)
            combined.append(defaultProfile)
            existingNames.insert(normalized(defaultProfile.name))
            existingBuiltInSemantics.insert(normalized(semantic))
        }

        return combined.sorted { $0.sortOrder < $1.sortOrder }
    }

    static func visibleNames(
        from profiles: [ExpenseCategoryProfile],
        including currentName: String? = nil
    ) -> [String] {
        var names = profiles
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.name)

        if names.isEmpty {
            names = ExpenseCategory.allCases.map(\.rawValue)
        }

        if let currentName,
           !currentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !names.contains(where: { normalized($0) == normalized(currentName) }) {
            names.append(currentName)
        }

        return names
    }

    static func canCreate(_ name: String, in profiles: [ExpenseCategoryProfile]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalizedName = normalized(trimmed)
        return !profiles.contains {
            normalized($0.name) == normalizedName
                || normalized($0.semanticRawName ?? "") == normalizedName
        }
    }

    static func canRename(_ profile: ExpenseCategoryProfile, to name: String, in profiles: [ExpenseCategoryProfile]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalizedName = normalized(trimmed)
        return !profiles.contains {
            $0.idString != profile.idString
                && (normalized($0.name) == normalizedName
                    || normalized($0.semanticRawName ?? "") == normalizedName)
        }
    }

    static func displayName(forSemanticRawName name: String, in profiles: [ExpenseCategoryProfile]) -> String {
        let normalizedName = normalized(name)
        guard let profile = profiles.first(where: {
            $0.isBuiltIn && normalized($0.semanticRawName ?? "") == normalizedName
        }) else {
            return name
        }
        return profile.name
    }

    static func userFacingPayment(_ payment: ParsedPayment, profiles: [ExpenseCategoryProfile]) -> ParsedPayment {
        let displayCategory = displayName(forSemanticRawName: payment.categoryRaw, in: profiles)
        guard normalized(displayCategory) != normalized(payment.categoryRaw) else {
            return payment
        }
        return ParsedPayment(
            amount: payment.amount,
            merchant: payment.merchant,
            channel: payment.channel,
            note: payment.note,
            occurredAt: payment.occurredAt,
            category: payment.category,
            categoryRaw: displayCategory,
            merchantLogoPNGData: payment.merchantLogoPNGData
        )
    }

    static func normalized(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }

    static func systemImage(for name: String) -> String {
        if let category = ExpenseCategory(rawValue: name) {
            switch category {
            case .dining: return "fork.knife"
            case .commute: return "car.fill"
            case .shopping: return "bag.fill"
            case .housing: return "house.fill"
            case .health: return "cross.case.fill"
            case .entertainment: return "sparkles"
            case .travel: return "airplane"
            case .education: return "book.fill"
            case .transfer: return "arrow.left.arrow.right"
            case .other: return "ellipsis.circle.fill"
            }
        }

        if name.contains("宠物") { return "pawprint.fill" }
        if name.contains("运动") { return "figure.run" }
        if name.contains("咖啡") { return "cup.and.saucer.fill" }
        return "tag.fill"
    }
}

@Model
final class ExpenseRecord {
    var amount: Decimal
    var merchant: String
    var categoryRaw: String
    var scene: String
    var channelRaw: String
    var note: String
    @Attribute(.externalStorage) var merchantLogoPNGData: Data?
    var occurredAt: Date
    var createdAt: Date
    var isArchived: Bool

    init(
        amount: Decimal,
        merchant: String,
        category: ExpenseCategory,
        scene: String,
        channel: PaymentChannel,
        note: String = "",
        merchantLogoPNGData: Data? = nil,
        occurredAt: Date = .now,
        createdAt: Date = .now,
        isArchived: Bool = false
    ) {
        self.amount = amount
        self.merchant = merchant
        self.categoryRaw = category.rawValue
        self.scene = scene
        self.channelRaw = channel.rawValue
        self.note = note
        self.merchantLogoPNGData = merchantLogoPNGData
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.isArchived = isArchived
    }

    convenience init(
        amount: Decimal,
        merchant: String,
        categoryRaw: String,
        scene: String,
        channel: PaymentChannel,
        note: String = "",
        merchantLogoPNGData: Data? = nil,
        occurredAt: Date = .now,
        createdAt: Date = .now,
        isArchived: Bool = false
    ) {
        self.init(
            amount: amount,
            merchant: merchant,
            category: ExpenseCategory(rawValue: categoryRaw) ?? .other,
            scene: scene,
            channel: channel,
            note: note,
            merchantLogoPNGData: merchantLogoPNGData,
            occurredAt: occurredAt,
            createdAt: createdAt,
            isArchived: isArchived
        )
        self.categoryRaw = categoryRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var channel: PaymentChannel {
        get { PaymentChannel(rawValue: channelRaw) ?? .other }
        set { channelRaw = newValue.rawValue }
    }
}

enum ExpenseRecordMaintenance {
    struct CleanupResult {
        var removedSeedRecords = 0
        var removedDuplicateRecords = 0

        var didChange: Bool {
            removedSeedRecords > 0 || removedDuplicateRecords > 0
        }
    }

    private struct SeedSignature {
        let merchant: String
        let amountCents: Int64
        let scene: String
        let channel: PaymentChannel
        let category: ExpenseCategory
        let note: String
    }

    private static let seedSignatures: [SeedSignature] = [
        SeedSignature(merchant: "咖啡店", amountCents: 3850, scene: "工作日早餐", channel: .alipay, category: .dining, note: "拿铁和三明治"),
        SeedSignature(merchant: "盒马", amountCents: 12800, scene: "家庭补货", channel: .wechat, category: .shopping, note: ""),
        SeedSignature(merchant: "地铁", amountCents: 1600, scene: "通勤", channel: .unionPay, category: .commute, note: ""),
        SeedSignature(merchant: "面馆", amountCents: 5600, scene: "午餐", channel: .wechat, category: .dining, note: ""),
        SeedSignature(merchant: "药房", amountCents: 26800, scene: "家庭健康", channel: .alipay, category: .health, note: ""),
        SeedSignature(merchant: "电影院", amountCents: 8900, scene: "周末休闲", channel: .wechat, category: .entertainment, note: ""),
        SeedSignature(merchant: "酒店", amountCents: 42000, scene: "短途出行", channel: .bankCard, category: .travel, note: ""),
        SeedSignature(merchant: "在线课程", amountCents: 19900, scene: "技能提升", channel: .alipay, category: .education, note: "")
    ]

    static func cleanup(records: [ExpenseRecord], context: ModelContext) -> CleanupResult {
        var result = CleanupResult()
        var seenKeys = Set<String>()

        for record in records.sorted(by: { $0.createdAt < $1.createdAt }) {
            if isSeedRecord(record) {
                context.delete(record)
                result.removedSeedRecords += 1
                continue
            }

            let key = deduplicationKey(
                amount: record.amount,
                merchant: record.merchant,
                categoryRaw: record.categoryRaw,
                channelRaw: record.channelRaw,
                occurredAt: record.occurredAt
            )

            if seenKeys.contains(key) {
                context.delete(record)
                result.removedDuplicateRecords += 1
            } else {
                seenKeys.insert(key)
            }
        }

        return result
    }

    static func uniquePayments(
        _ payments: [ParsedPayment],
        existing records: [ExpenseRecord]
    ) -> [ParsedPayment] {
        var seenKeys = Set(records.map {
            deduplicationKey(
                amount: $0.amount,
                merchant: $0.merchant,
                categoryRaw: $0.categoryRaw,
                channelRaw: $0.channelRaw,
                occurredAt: $0.occurredAt
            )
        })

        var unique: [ParsedPayment] = []
        for payment in payments {
            let key = deduplicationKey(
                amount: payment.amount,
                merchant: payment.merchant,
                category: payment.category,
                channel: payment.channel,
                occurredAt: payment.occurredAt ?? .now
            )

            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            unique.append(payment)
        }
        return unique
    }

    static func deduplicationKey(
        amount: Decimal,
        merchant: String,
        category: ExpenseCategory,
        channel: PaymentChannel,
        occurredAt: Date,
        calendar: Calendar = .current
    ) -> String {
        deduplicationKey(
            amount: amount,
            merchant: merchant,
            categoryRaw: category.rawValue,
            channelRaw: channel.rawValue,
            occurredAt: occurredAt,
            calendar: calendar
        )
    }

    static func deduplicationKey(
        amount: Decimal,
        merchant: String,
        categoryRaw: String,
        channelRaw: String,
        occurredAt: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: occurredAt)
        let time = [
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        ]
        .map(String.init)
        .joined(separator: "-")

        return [
            normalizedMerchant(merchant),
            String(cents(from: amount)),
            ExpenseCategoryCatalog.normalized(categoryRaw),
            ExpenseCategoryCatalog.normalized(channelRaw),
            time
        ].joined(separator: "|")
    }

    static func centsValue(from amount: Decimal) -> Int64 {
        cents(from: amount)
    }

    private static func isSeedRecord(_ record: ExpenseRecord) -> Bool {
        seedSignatures.contains { signature in
            normalizedMerchant(record.merchant) == normalizedMerchant(signature.merchant)
                && cents(from: record.amount) == signature.amountCents
                && record.scene == signature.scene
                && record.channel == signature.channel
                && record.category == signature.category
                && record.note == signature.note
        }
    }

    private static func normalizedMerchant(_ merchant: String) -> String {
        merchant
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }

    private static func cents(from amount: Decimal) -> Int64 {
        let scaled = NSDecimalNumber(decimal: amount)
            .multiplying(byPowerOf10: 2)
            .rounding(accordingToBehavior: nil)
        return scaled.int64Value
    }
}
