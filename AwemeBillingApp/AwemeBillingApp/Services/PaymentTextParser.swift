import Foundation

struct ParsedPayment {
    let amount: Decimal
    let merchant: String
    let channel: PaymentChannel
    let note: String
    let occurredAt: Date?
    let category: ExpenseCategory
    let categoryRaw: String
    let merchantLogoPNGData: Data?

    init(
        amount: Decimal,
        merchant: String,
        channel: PaymentChannel,
        note: String,
        occurredAt: Date?,
        category: ExpenseCategory,
        categoryRaw: String? = nil,
        merchantLogoPNGData: Data? = nil
    ) {
        self.amount = amount
        self.merchant = merchant
        self.channel = channel
        self.note = note
        self.occurredAt = occurredAt
        self.category = category
        self.categoryRaw = categoryRaw?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? category.rawValue
        self.merchantLogoPNGData = merchantLogoPNGData
    }

    func withMerchantLogoPNGData(_ data: Data?) -> ParsedPayment {
        ParsedPayment(
            amount: amount,
            merchant: merchant,
            channel: channel,
            note: note,
            occurredAt: occurredAt,
            category: category,
            categoryRaw: categoryRaw,
            merchantLogoPNGData: data ?? merchantLogoPNGData
        )
    }
}

enum PaymentTextParser {
    static func parseAll(
        _ text: String,
        preferredChannel: PaymentChannel? = nil,
        referenceDate: Date = .now
    ) -> [ParsedPayment] {
        let structuredPayments = PaymentStructuredPayloadParser.parse(
            text: text,
            preferredChannel: preferredChannel,
            referenceDate: referenceDate
        )
        if !structuredPayments.isEmpty {
            return structuredPayments
        }
        if PaymentStructuredPayloadParser.containsStructuredPayload(in: text) {
            return []
        }

        let listPayments = parseBillList(
            text,
            preferredChannel: preferredChannel,
            referenceDate: referenceDate
        )
        if !listPayments.isEmpty {
            return listPayments
        }

        return parse(text, preferredChannel: preferredChannel, referenceDate: referenceDate).map { [$0] } ?? []
    }

    static func parse(
        _ text: String,
        preferredChannel: PaymentChannel? = nil,
        referenceDate: Date = .now
    ) -> ParsedPayment? {
        guard let amount = firstAmount(in: text) else { return nil }
        let channel = channel(in: text, preferredChannel: preferredChannel)
        let merchant = merchant(in: text, channel: channel)
        return ParsedPayment(
            amount: amount,
            merchant: merchant,
            channel: channel,
            note: text,
            occurredAt: occurredAt(in: text) ?? billDate(from: text, now: referenceDate),
            category: category(in: text)
        )
    }

    private struct BillAmountLine {
        let amount: Decimal
        let isIncome: Bool
        let originalText: String
    }

    private static func parseBillList(
        _ text: String,
        preferredChannel: PaymentChannel?,
        referenceDate: Date
    ) -> [ParsedPayment] {
        let channel = billListChannel(in: text, preferredChannel: preferredChannel)
        switch channel {
        case .alipay:
            return AlipayBillListParser.parse(text, referenceDate: referenceDate)
        case .wechat:
            return WeChatBillListParser.parse(text, referenceDate: referenceDate)
        default:
            return GenericBillListParser.parse(text, channel: channel, referenceDate: referenceDate)
        }
    }

    private static func parseGenericBillList(
        _ text: String,
        channel: PaymentChannel,
        referenceDate: Date,
        categoryResolver: (_ merchant: String, _ categoryText: String, _ amountLine: BillAmountLine) -> (category: ExpenseCategory, categoryRaw: String?)
    ) -> [ParsedPayment] {
        guard looksLikeBillList(text) else {
            return []
        }

        let lines = normalizedBillLines(from: text)
        var payments: [ParsedPayment] = []
        var previousAmountIndex = -1

        for index in lines.indices {
            guard let amountLine = billAmountLine(
                from: lines[index],
                lines: lines,
                amountIndex: index,
                lowerBound: previousAmountIndex + 1
            ) else {
                continue
            }

            let lowerBound = previousAmountIndex + 1
            let merchant = merchantNearAmount(lines, amountIndex: index, lowerBound: lowerBound)
            guard !merchant.isEmpty, !shouldIgnoreBillMerchant(merchant) else {
                previousAmountIndex = index
                continue
            }

            let upperBound = nextAmountIndex(in: lines, after: index) ?? lines.count
            let categoryText = categoryNearAmount(
                lines,
                amountIndex: index,
                lowerBound: lowerBound,
                upperBound: upperBound
            ) ?? ""
            let timeLine = timeLineNearAmount(
                lines,
                amountIndex: index,
                lowerBound: lowerBound,
                upperBound: upperBound
            )
            let resolvedCategory = categoryResolver(merchant, categoryText, amountLine)
            payments.append(
                ParsedPayment(
                    amount: amountLine.amount,
                    merchant: merchant,
                    channel: channel,
                    note: [merchant, categoryText, timeLine ?? "", amountLine.originalText]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n"),
                    occurredAt: timeLine.flatMap { billDate(from: $0, now: referenceDate) },
                    category: resolvedCategory.category,
                    categoryRaw: resolvedCategory.categoryRaw
                )
            )
            previousAmountIndex = index
        }

        return payments
    }

    private enum GenericBillListParser {
        static func parse(
            _ text: String,
            channel: PaymentChannel,
            referenceDate: Date
        ) -> [ParsedPayment] {
            parseGenericBillList(text, channel: channel, referenceDate: referenceDate) { merchant, categoryText, amountLine in
                let context = [merchant, categoryText, amountLine.isIncome ? "收入 退款" : ""].joined(separator: " ")
                return (category(in: context), nil)
            }
        }
    }

    private enum AlipayBillListParser {
        static func parse(_ text: String, referenceDate: Date) -> [ParsedPayment] {
            parseGenericBillList(text, channel: .alipay, referenceDate: referenceDate) { merchant, categoryText, amountLine in
                if let mapped = PaymentPlatformCategoryMapper.category(from: categoryText) {
                    return (mapped.category, mapped.raw)
                }
                let context = [merchant, categoryText, amountLine.isIncome ? "收入 退款" : ""].joined(separator: " ")
                return (category(in: context), nil)
            }
        }
    }

    private enum WeChatBillListParser {
        static func parse(_ text: String, referenceDate: Date) -> [ParsedPayment] {
            parseGenericBillList(text, channel: .wechat, referenceDate: referenceDate) { merchant, categoryText, amountLine in
                let context = [merchant, categoryText, amountLine.isIncome ? "收入 退款 群收款" : ""].joined(separator: " ")
                return (category(in: context), nil)
            }
        }
    }

    private static func looksLikeBillList(_ text: String) -> Bool {
        let listMarkers = [
            "搜索交易记录", "收支分析", "本月已省", "全部账单", "查找交易", "收支统计"
        ]
        if listMarkers.contains(where: { text.contains($0) }) {
            return true
        }

        let signedAmountMatches = matches(pattern: #"(?m)^[+＋\-−]\s*[¥￥]?\s*[0-9,]+(?:\.[0-9]{1,2})?\s*$"#, in: text)
        let timeMatches = matches(pattern: #"(今天|昨天|\d{1,2}月\d{1,2}日|\d{1,2}-\d{1,2})\s+\d{1,2}:\d{2}"#, in: text)
        return signedAmountMatches.count >= 2 && timeMatches.count >= 2
    }

    private static func normalizedBillLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func firstAmount(in text: String) -> Decimal? {
        let preferredPatterns = [
            #"交易金额\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            #"金额[:：\s]*[¥￥]?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#,
            #"消费[:：\s]*[¥￥]?\s*([0-9,]+(?:\.[0-9]{1,2})?)"#
        ]
        for pattern in preferredPatterns {
            if let amount = matchDecimal(pattern: pattern, in: text) {
                return amount
            }
        }

        let fallbackPatterns = [
            #"(?:(?:¥|￥|人民币|CNY)\s*)([0-9,]+(?:\.[0-9]{1,2})?)"#,
            #"([0-9,]+(?:\.[0-9]{1,2})?)\s*元"#
        ]
        for pattern in fallbackPatterns {
            if let amount = matchDecimal(pattern: pattern, in: text) {
                return amount
            }
        }
        return nil
    }

    private static func matchDecimal(pattern: String, in text: String) -> Decimal? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Decimal(string: String(text[range]).replacingOccurrences(of: ",", with: ""))
    }

    fileprivate static func channel(in text: String, preferredChannel: PaymentChannel? = nil) -> PaymentChannel {
        if let preferredChannel {
            return preferredChannel
        }
        if text.contains("支付宝") { return .alipay }
        if text.contains("余额宝") || text.contains("收支分析") || text.contains("搜索交易记录") { return .alipay }
        if text.contains("微信") { return .wechat }
        if text.contains("云闪付") || text.contains("银联") { return .unionPay }
        if text.contains("银行") || text.contains("信用卡") || text.contains("卡号") { return .bankCard }
        return .other
    }

    private static func billListChannel(in text: String, preferredChannel: PaymentChannel?) -> PaymentChannel {
        if let preferredChannel {
            return preferredChannel
        }
        if text.contains("全部账单") || text.contains("查找交易") || text.contains("收支统计") {
            return .wechat
        }
        return channel(in: text)
    }

    private static func merchant(in text: String, channel: PaymentChannel) -> String {
        if let merchant = lineValue(after: "商户名称", in: text) {
            return merchant
        }

        let merchantPatterns = [
            #"向\s*([^，,。；;\n\r]+?)\s*(?:支付|付款|转账|消费)"#,
            #"(?:付款给|支付给|转账给|给)\s*([^，,。；;\n\r]+?)(?:\s*[¥￥]?\s*[0-9,]+(?:\.[0-9]{1,2})?|\s*(?:支付|付款|转账|消费)|$)"#,
            #"收款方[:：\s]*([^，,。；;\n\r]+)"#,
            #"商户[:：\s]*([^，,。；;\n\r]+)"#
        ]
        for pattern in merchantPatterns {
            if let merchant = firstCapturedText(pattern: pattern, in: text) {
                return cleanedNotificationMerchant(merchant)
            }
        }

        let markers = ["向", "在", "商户", "收款方"]
        for marker in markers {
            guard let markerRange = text.range(of: marker) else { continue }
            let suffix = text[markerRange.upperBound...]
                .prefix { !$0.isWhitespace && $0 != "，" && $0 != "," && $0 != "。" }
            if !suffix.isEmpty {
                return String(suffix).replacingOccurrences(of: "支付", with: "")
            }
        }
        return channel.rawValue
    }

    private static func firstCapturedText(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func cleanedNotificationMerchant(_ merchant: String) -> String {
        merchant
            .replacingOccurrences(of: "支付", with: "")
            .replacingOccurrences(of: "付款", with: "")
            .replacingOccurrences(of: "转账", with: "")
            .replacingOccurrences(of: "消费", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func category(in text: String) -> ExpenseCategory {
        PaymentRuleEngine.defaultCategory(for: text)
    }

    private static func billAmountLine(
        from line: String,
        lines: [String],
        amountIndex: Int,
        lowerBound: Int
    ) -> BillAmountLine? {
        if let signed = signedBillAmountLine(from: line) {
            return signed
        }

        guard let amount = unsignedBillAmount(from: line) else { return nil }
        let searchStart = max(lowerBound, amountIndex - 5)
        let searchEnd = min(lines.count - 1, amountIndex + 2)
        let nearbyText = (searchStart...searchEnd)
            .map { lines[$0] }
            .joined(separator: " ")

        guard nearbyText.contains("退款")
            || nearbyText.contains("收益")
            || nearbyText.contains("收入")
            || nearbyText.contains("群收款")
        else { return nil }

        return BillAmountLine(amount: amount, isIncome: true, originalText: line)
    }

    private static func signedBillAmountLine(from line: String) -> BillAmountLine? {
        let pattern = #"^([+＋\-−])\s*[¥￥]?\s*([0-9,]+(?:\.[0-9]{1,2})?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let signRange = Range(match.range(at: 1), in: line),
              let amountRange = Range(match.range(at: 2), in: line),
              let amount = Decimal(string: String(line[amountRange]).replacingOccurrences(of: ",", with: ""))
        else { return nil }

        let sign = String(line[signRange])
        return BillAmountLine(amount: amount, isIncome: sign == "+" || sign == "＋", originalText: line)
    }

    private static func unsignedBillAmount(from line: String) -> Decimal? {
        let pattern = #"^[¥￥]?\s*([0-9,]+(?:\.[0-9]{1,2})?)$"#
        return matchDecimal(pattern: pattern, in: line)
    }

    private static func isBillAmountBoundaryLine(_ line: String) -> Bool {
        line.range(of: #"^[+＋\-−]?\s*[¥￥]?\s*[0-9,]+(?:\.[0-9]{1,2})$"#, options: .regularExpression) != nil
    }

    private static func nextAmountIndex(in lines: [String], after amountIndex: Int) -> Int? {
        guard amountIndex + 1 < lines.count else { return nil }
        return ((amountIndex + 1)..<lines.count).first { isBillAmountBoundaryLine(lines[$0]) }
    }

    private static func isBillTimeLine(_ line: String) -> Bool {
        line.contains("今天") || line.contains("昨天") || line.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil
    }

    private static func cleanedBillMerchant(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[-−]\s*⋯$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[-−]\s*\.\.\.$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\.\.\.\.$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+\([¥￥]?[0-9,]+(?:\.[0-9]{1,2})?\)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldIgnoreBillMerchant(_ merchant: String) -> Bool {
        let ignoredFragments = ["支出", "收入", "本月已省", "收支分析", "搜索", "筛选", "全部", "订单", "贴纸"]
        return ignoredFragments.contains { merchant.contains($0) }
    }

    private static func merchantNearAmount(
        _ lines: [String],
        amountIndex: Int,
        lowerBound: Int
    ) -> String {
        let searchStart = max(lowerBound, amountIndex - 5)
        for candidateIndex in stride(from: amountIndex - 1, through: searchStart, by: -1) {
            let candidate = cleanedBillMerchant(lines[candidateIndex])
            if isStandaloneBillCategoryLine(candidate),
               candidateIndex + 1 < amountIndex,
               ((candidateIndex + 1)..<amountIndex).contains(where: { isBillTimeLine(lines[$0]) }) {
                continue
            }
            if isBillMerchantCandidate(candidate) {
                return candidate
            }
        }
        return ""
    }

    private static func categoryNearAmount(
        _ lines: [String],
        amountIndex: Int,
        lowerBound: Int,
        upperBound: Int
    ) -> String? {
        if usesForwardMetadataSearch(lines, amountIndex: amountIndex) {
            return forwardCategoryNearAmount(lines, amountIndex: amountIndex, upperBound: upperBound)
        }

        let searchStart = max(lowerBound, amountIndex - 4)
        let previousCategoryIndex = stride(from: amountIndex - 1, through: searchStart, by: -1)
            .first { isStandaloneBillCategoryLine(lines[$0]) }
        if let previousCategoryIndex {
            return lines[previousCategoryIndex]
        }

        return forwardCategoryNearAmount(lines, amountIndex: amountIndex, upperBound: upperBound)
    }

    private static func timeLineNearAmount(
        _ lines: [String],
        amountIndex: Int,
        lowerBound: Int,
        upperBound: Int
    ) -> String? {
        if usesForwardMetadataSearch(lines, amountIndex: amountIndex) {
            return forwardTimeLineNearAmount(lines, amountIndex: amountIndex, upperBound: upperBound)
        }

        let searchStart = max(lowerBound, amountIndex - 4)
        let previousTimeIndex = stride(from: amountIndex - 1, through: searchStart, by: -1)
            .first { isBillTimeLine(lines[$0]) }
        if let previousTimeIndex {
            return lines[previousTimeIndex]
        }

        return forwardTimeLineNearAmount(lines, amountIndex: amountIndex, upperBound: upperBound)
    }

    private static func usesForwardMetadataSearch(_ lines: [String], amountIndex: Int) -> Bool {
        guard amountIndex > 0 else { return false }
        return isBillMerchantCandidate(cleanedBillMerchant(lines[amountIndex - 1]))
    }

    private static func forwardCategoryNearAmount(
        _ lines: [String],
        amountIndex: Int,
        upperBound: Int
    ) -> String? {
        guard amountIndex + 1 < upperBound else { return nil }
        let searchEnd = min(upperBound - 1, amountIndex + 5)
        return ((amountIndex + 1)...searchEnd)
            .first { isStandaloneBillCategoryLine(lines[$0]) }
            .map { lines[$0] }
    }

    private static func forwardTimeLineNearAmount(
        _ lines: [String],
        amountIndex: Int,
        upperBound: Int
    ) -> String? {
        guard amountIndex + 1 < upperBound else { return nil }
        let searchEnd = min(upperBound - 1, amountIndex + 6)
        return ((amountIndex + 1)...searchEnd)
            .first { isBillTimeLine(lines[$0]) }
            .map { lines[$0] }
    }

    private static func isBillMerchantCandidate(_ line: String) -> Bool {
        guard line.count >= 2, !shouldIgnoreBillMerchant(line) else { return false }
        if isBillTimeLine(line) || isBillAmountBoundaryLine(line) {
            return false
        }
        if line.range(of: #"^[<＞>·•。！!、\s]+$"#, options: .regularExpression) != nil {
            return false
        }
        if line.range(of: #"^￥?[0-9,]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private static func isBillCategoryLine(_ line: String) -> Bool {
        let categoryFragments = [
            "餐饮", "美食", "爱车", "养车", "文化", "休闲", "投资", "理财",
            "购物", "交通", "出行", "停车", "转账", "退款", "生活", "服务",
            "充值", "缴费", "商业服务", "车位", "日用", "百货", "收益", "群收款",
            "酒店", "住宿"
        ]
        return categoryFragments.contains { line.contains($0) }
    }

    private static func isStandaloneBillCategoryLine(_ line: String) -> Bool {
        let standaloneCategories: Set<String> = [
            "餐饮美食", "爱车养车", "文化休闲", "投资理财", "日用百货",
            "数码电器", "服饰装扮", "医疗健康", "教育培训", "退款",
            "充值缴费", "商业服务", "交通出行", "购物消费", "生活服务",
            "酒店住宿", "酒店旅游", "旅行住宿", "旅行交通", "转账", "消费", "收入"
        ]
        return standaloneCategories.contains(line)
    }

    fileprivate static func billDate(from line: String, now: Date = .now) -> Date? {
        let calendar = Calendar.current

        if let date = billDate(
            pattern: #"([0-9]{1,2})月([0-9]{1,2})日\s*([0-9]{1,2}):([0-9]{2})"#,
            line: line,
            now: now,
            calendar: calendar
        ) {
            return date
        }

        if let date = billDate(
            pattern: #"([0-9]{1,2})-([0-9]{1,2})\s*([0-9]{1,2}):([0-9]{2})"#,
            line: line,
            now: now,
            calendar: calendar
        ) {
            return date
        }

        let pattern = #"(今天|昨天)?\s*([0-9]{1,2}):([0-9]{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let hourRange = Range(match.range(at: 2), in: line),
              let minuteRange = Range(match.range(at: 3), in: line),
              let hour = Int(line[hourRange]),
              let minute = Int(line[minuteRange])
        else { return nil }

        let dayOffset = (Range(match.range(at: 1), in: line).map { String(line[$0]) } == "昨天") ? -1 : 0
        let baseDate = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate)
    }

    private static func billDate(
        pattern: String,
        line: String,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let monthRange = Range(match.range(at: 1), in: line),
              let dayRange = Range(match.range(at: 2), in: line),
              let hourRange = Range(match.range(at: 3), in: line),
              let minuteRange = Range(match.range(at: 4), in: line),
              let month = Int(line[monthRange]),
              let day = Int(line[dayRange]),
              let hour = Int(line[hourRange]),
              let minute = Int(line[minuteRange])
        else { return nil }

        return resolvedYearlessBillDate(
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            referenceDate: now,
            calendar: calendar
        )
    }

    fileprivate static func resolvedYearlessBillDate(
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let referenceYear = calendar.component(.year, from: referenceDate)
        let futureGrace = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        let candidates = [referenceYear - 1, referenceYear, referenceYear + 1].compactMap { year in
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
        }
        let nonFutureCandidates = candidates.filter { $0 <= futureGrace }
        return (nonFutureCandidates.isEmpty ? candidates : nonFutureCandidates)
            .min { abs($0.timeIntervalSince(referenceDate)) < abs($1.timeIntervalSince(referenceDate)) }
    }

    private static func occurredAt(in text: String) -> Date? {
        guard let dateText = lineValue(after: "交易日期", in: text) else { return nil }
        let timeText = lineValue(after: "交易时间", in: text) ?? "00时00分00秒"
        let normalized = "\(dateText) \(timeText)"
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: "时", with: ":")
            .replacingOccurrences(of: "分", with: ":")
            .replacingOccurrences(of: "秒", with: "")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: normalized)
    }

    private static func lineValue(after label: String, in text: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: label))[:：]?\\s*([^\\n\\r]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func matches(pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

private enum PaymentStructuredPayloadParser {
    static func containsStructuredPayload(in text: String) -> Bool {
        guard let json = extractJSON(from: text) else { return false }
        let normalized = json.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        return normalized.contains(#""payments":"#)
            || normalized.contains(#""transactions":"#)
            || normalized.contains(#""records":"#)
    }

    static func parse(
        text: String,
        preferredChannel: PaymentChannel?,
        referenceDate: Date
    ) -> [ParsedPayment] {
        guard let json = extractJSON(from: text),
              let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(StructuredPaymentPayload.self, from: data) else {
            return []
        }

        let rawItems = payload.payments ?? payload.transactions ?? payload.records ?? []
        return rawItems.compactMap { item -> ParsedPayment? in
            guard let amount = item.normalizedAmount,
                  amount > 0 else {
                return nil
            }

            let channel = channel(
                from: [item.channel, payload.source, payload.platform].compactMap { $0 }.joined(separator: " "),
                preferredChannel: preferredChannel
            )
            if let rawPayment = paymentFromRawBillRow(
                item: item,
                channel: channel,
                referenceDate: referenceDate
            ) {
                return rawPayment
            }

            let merchant = normalizedMerchant(item.merchant ?? item.title ?? item.payee ?? item.counterparty)
            guard !merchant.isEmpty else { return nil }
            guard !isGenericStructuredMerchant(merchant, channel: channel) else { return nil }
            let note = [
                item.note,
                item.direction,
                item.type,
                item.rawText
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            guard !shouldRejectStructuredTransaction(item: item, merchant: merchant, note: note) else {
                return nil
            }

            let category = category(from: item.category, merchant: merchant, note: item.note)
            let occurredAt = occurredAt(from: item, referenceDate: referenceDate)

            return ParsedPayment(
                amount: amount,
                merchant: merchant,
                channel: channel,
                note: note.isEmpty ? text : note,
                occurredAt: occurredAt,
                category: category,
                categoryRaw: item.category
            )
        }
    }

    private struct RawBillRowEvidence {
        let merchant: String
        let amount: Decimal
        let timeText: String?
        let categoryText: String?
        let noteText: String
    }

    private static func paymentFromRawBillRow(
        item: StructuredPaymentItem,
        channel: PaymentChannel,
        referenceDate: Date
    ) -> ParsedPayment? {
        let rawContext = [item.rawText, item.note]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard let evidence = rawBillRowEvidence(from: rawContext, channel: channel) else {
            return nil
        }

        let rawCategory = evidence.categoryText ?? item.category
        guard !shouldRejectStructuredTransaction(
            item: item,
            merchant: evidence.merchant,
            note: evidence.noteText
        ) else {
            return nil
        }

        let category = category(from: rawCategory, merchant: evidence.merchant, note: evidence.noteText)
        let structuredOccurredAt = occurredAt(from: item, referenceDate: referenceDate)
        let rawOccurredAt = evidence.timeText.flatMap { PaymentTextParser.billDate(from: $0, now: referenceDate) }
        return ParsedPayment(
            amount: evidence.amount,
            merchant: evidence.merchant,
            channel: channel,
            note: evidence.noteText,
            occurredAt: shouldPreferStructuredDate(for: evidence.timeText)
                ? (structuredOccurredAt ?? rawOccurredAt)
                : (rawOccurredAt ?? structuredOccurredAt),
            category: category,
            categoryRaw: rawCategory
        )
    }

    private static func rawBillRowEvidence(from text: String, channel: PaymentChannel) -> RawBillRowEvidence? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }

        let amountCandidates = lines.indices.compactMap { index -> (index: Int, amount: Decimal)? in
            guard let amount = signedAmount(from: lines[index]) else { return nil }
            return (index, amount)
        }
        guard let amountCandidate = amountCandidates.first else { return nil }

        let timeIndex = nearestTimeLineIndex(in: lines, around: amountCandidate.index)
        guard let merchant = merchantForRawBillRow(
            in: lines,
            amountIndex: amountCandidate.index,
            timeIndex: timeIndex,
            channel: channel
        ) else {
            return nil
        }

        let categoryText = categoryForRawBillRow(
            in: lines,
            merchant: merchant,
            amountIndex: amountCandidate.index,
            timeIndex: timeIndex
        )
        return RawBillRowEvidence(
            merchant: merchant,
            amount: amountCandidate.amount,
            timeText: timeIndex.map { lines[$0] },
            categoryText: categoryText,
            noteText: lines.joined(separator: "\n")
        )
    }

    private static func signedAmount(from line: String) -> Decimal? {
        let pattern = #"^[+＋\-−]\s*[¥￥]?\s*([0-9,]+(?:\.[0-9]{1,2})?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let amount = Decimal(string: String(line[range]).replacingOccurrences(of: ",", with: ""))
        else { return nil }
        return amount
    }

    private static func nearestTimeLineIndex(in lines: [String], around amountIndex: Int) -> Int? {
        lines.indices
            .filter { isRawBillTimeLine(lines[$0]) }
            .min { abs($0 - amountIndex) < abs($1 - amountIndex) }
    }

    private static func merchantForRawBillRow(
        in lines: [String],
        amountIndex: Int,
        timeIndex: Int?,
        channel: PaymentChannel
    ) -> String? {
        let anchor = min(amountIndex, timeIndex ?? amountIndex)
        if anchor > 0 {
            for index in stride(from: anchor - 1, through: 0, by: -1) {
                let candidate = normalizedRawBillMerchant(lines[index])
                if isRawBillMerchantCandidate(candidate, channel: channel) {
                    return candidate
                }
            }
        }

        for index in lines.indices where index != amountIndex && index != timeIndex {
            let candidate = normalizedRawBillMerchant(lines[index])
            if isRawBillMerchantCandidate(candidate, channel: channel) {
                return candidate
            }
        }
        return nil
    }

    private static func categoryForRawBillRow(
        in lines: [String],
        merchant: String,
        amountIndex: Int,
        timeIndex: Int?
    ) -> String? {
        lines.indices
            .filter { $0 != amountIndex && $0 != timeIndex && normalizedRawBillMerchant(lines[$0]) != merchant }
            .map { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { PaymentPlatformCategoryMapper.category(from: $0) != nil }
    }

    private static func isRawBillTimeLine(_ line: String) -> Bool {
        line.range(of: #"(?:今天|昨天|[0-9]{1,2}月[0-9]{1,2}日|[0-9]{1,2}-[0-9]{1,2})\s*[0-9]{1,2}:[0-9]{2}"#, options: .regularExpression) != nil
    }

    private static func shouldPreferStructuredDate(for rawTimeText: String?) -> Bool {
        let rawTimeText = rawTimeText ?? ""
        return rawTimeText.contains("今天") || rawTimeText.contains("昨天")
    }

    private static func normalizedRawBillMerchant(_ value: String) -> String {
        normalizedMerchant(value)
            .replacingOccurrences(of: #"[-−]\s*⋯$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\.\.\.$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isRawBillMerchantCandidate(_ line: String, channel: PaymentChannel) -> Bool {
        guard line.count >= 2 else { return false }
        if isGenericStructuredMerchant(line, channel: channel) { return false }
        if isRawBillTimeLine(line) { return false }
        if signedAmount(from: line) != nil { return false }
        if PaymentPlatformCategoryMapper.category(from: line) != nil { return false }
        let ignoredFragments = ["支出", "收入", "全部账单", "查找交易", "收支统计", "截图解析", "待复核", "置信度"]
        return !ignoredFragments.contains { line.contains($0) }
    }

    private static func isGenericStructuredMerchant(_ merchant: String, channel: PaymentChannel) -> Bool {
        let normalized = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericValues: Set<String> = [
            channel.rawValue,
            "微信支付",
            "支付宝",
            "云闪付",
            "银联",
            "账单"
        ]
        return genericValues.contains(normalized)
    }

    private static func shouldRejectStructuredTransaction(
        item: StructuredPaymentItem,
        merchant: String,
        note: String
    ) -> Bool {
        let rawContext = ([
            merchant,
            item.amountText,
            item.category,
            item.occurredAt,
            item.transactionTime,
            item.date,
            item.time,
            item.direction,
            item.type,
            item.note,
            item.rawText,
            note
        ] as [String?])
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        return isTerminalNonPaymentContext(rawContext)
            || isAlipaySummaryContext(rawContext, merchant: merchant)
    }

    private static func isTerminalNonPaymentContext(_ text: String) -> Bool {
        let terminalFragments = [
            "交易关闭",
            "订单关闭",
            "已关闭",
            "待付款",
            "等待付款",
            "未支付",
            "已取消",
            "交易取消",
            "支付失败"
        ]
        return terminalFragments.contains { text.contains($0) }
    }

    private static func isAlipaySummaryContext(_ text: String, merchant: String) -> Bool {
        let normalizedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let exactSummaryMerchants: Set<String> = [
            "支出",
            "收入",
            "总支出",
            "总收入",
            "本月支出",
            "本月收入",
            "月支出",
            "月收入",
            "合计",
            "总计",
            "收支分析",
            "收支统计"
        ]
        let merchantLooksLikeSummary = exactSummaryMerchants.contains(normalizedMerchant)
            || normalizedMerchant.contains("汇总")
            || normalizedMerchant.contains("合计")
            || normalizedMerchant.contains("总计")
            || normalizedMerchant.range(of: #"^[0-9]{1,2}\s*月(?:\s*(?:支出|收入))?$"#, options: .regularExpression) != nil

        if merchantLooksLikeSummary {
            return true
        }

        let compactText = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        if normalizedMerchant.contains("支出") || normalizedMerchant.contains("收入") || normalizedMerchant.contains("月") {
            if compactText.range(of: #"[0-9]{1,2}月支出[¥￥]?[0-9,]+(?:\.[0-9]{1,2})?"#, options: .regularExpression) != nil {
                return true
            }
            if compactText.contains("支出¥") && compactText.contains("收入¥") {
                return true
            }
        }
        if compactText.contains("本月已省") || compactText.contains("今年累计已省") {
            return true
        }
        return false
    }

    private static func extractJSON(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("```") {
            let withoutFence = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return extractJSON(from: withoutFence)
        }

        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end else {
            return nil
        }
        return String(trimmed[start...end])
    }

    private static func normalizedMerchant(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: #"^[-+＋−]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func channel(from text: String, preferredChannel: PaymentChannel?) -> PaymentChannel {
        let detected = PaymentTextParser.channel(in: text)
        if detected != .other {
            return detected
        }
        return preferredChannel ?? .other
    }

    private static func category(from rawCategory: String?, merchant: String, note: String?) -> ExpenseCategory {
        if let mapped = PaymentPlatformCategoryMapper.category(from: rawCategory) {
            return mapped.category
        }
        if let rawCategory,
           let category = ExpenseCategory.allCases.first(where: { rawCategory.contains($0.rawValue) || $0.rawValue.contains(rawCategory) }) {
            return category
        }
        return PaymentRuleEngine.defaultCategory(for: [merchant, rawCategory ?? "", note ?? ""].joined(separator: " "))
    }

    private static func occurredAt(from item: StructuredPaymentItem, referenceDate: Date) -> Date? {
        let rawContext = [item.rawText, item.note]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
        let candidates = [
            item.occurredAt,
            item.transactionTime,
            [item.date, item.time].compactMap { $0 }.joined(separator: " ")
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        for candidate in candidates {
            if let date = fullDate(from: candidate) {
                return normalizedStructuredDate(
                    date,
                    candidateText: candidate,
                    rawContext: rawContext,
                    referenceDate: referenceDate
                )
            }
            if let date = PaymentTextParser.billDate(from: candidate, now: referenceDate) {
                return date
            }
        }
        return nil
    }

    private static func normalizedStructuredDate(
        _ date: Date,
        candidateText: String,
        rawContext: String,
        referenceDate: Date
    ) -> Date {
        let calendar = Calendar.current
        let parsedYear = calendar.component(.year, from: date)
        let referenceYear = calendar.component(.year, from: referenceDate)
        guard abs(parsedYear - referenceYear) > 1,
              !containsExplicitYear(rawContext),
              let corrected = PaymentTextParser.resolvedYearlessBillDate(
                month: calendar.component(.month, from: date),
                day: calendar.component(.day, from: date),
                hour: calendar.component(.hour, from: date),
                minute: calendar.component(.minute, from: date),
                referenceDate: referenceDate,
                calendar: calendar
              ) else {
            return date
        }

        if containsExplicitYear(candidateText), !containsExplicitYear(rawContext) {
            return corrected
        }
        return date
    }

    private static func containsExplicitYear(_ text: String) -> Bool {
        text.range(of: #"(?:19|20)\d{2}\s*(?:年|-|/|\.)"#, options: .regularExpression) != nil
    }

    private static func fullDate(from text: String) -> Date? {
        let normalized = text
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "时", with: ":")
            .replacingOccurrences(of: "分", with: ":")
            .replacingOccurrences(of: "秒", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-M-d HH:mm:ss",
            "yyyy-M-d HH:mm",
            "yyyy-MM-dd",
            "yyyy-M-d"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum PaymentPlatformCategoryMapper {
    static func category(from label: String?) -> (category: ExpenseCategory, raw: String)? {
        let normalized = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { return nil }

        let exactMatches: [String: ExpenseCategory] = [
            "餐饮美食": .dining,
            "爱车养车": .commute,
            "交通出行": .commute,
            "日用百货": .shopping,
            "数码电器": .shopping,
            "服饰装扮": .shopping,
            "充值缴费": .housing,
            "生活服务": .housing,
            "医疗健康": .health,
            "文化休闲": .entertainment,
            "酒店住宿": .travel,
            "酒店旅游": .travel,
            "旅行交通": .travel,
            "教育培训": .education,
            "投资理财": .transfer,
            "转账": .transfer,
            "退款": .transfer,
            "宠物": .other,
            "商业服务": .other
        ]

        if let category = exactMatches[normalized] {
            return (category, normalized)
        }

        let fuzzyMatches: [(String, ExpenseCategory)] = [
            ("餐饮", .dining), ("美食", .dining),
            ("停车", .commute), ("爱车", .commute), ("交通", .commute),
            ("购物", .shopping), ("百货", .shopping), ("数码", .shopping), ("电器", .shopping),
            ("缴费", .housing), ("生活", .housing),
            ("医疗", .health), ("健康", .health),
            ("文化", .entertainment), ("休闲", .entertainment), ("娱乐", .entertainment),
            ("酒店", .travel), ("住宿", .travel), ("旅行", .travel),
            ("教育", .education), ("培训", .education),
            ("投资", .transfer), ("理财", .transfer), ("收益", .transfer), ("退款", .transfer),
            ("宠物", .other)
        ]

        if let match = fuzzyMatches.first(where: { normalized.contains($0.0) }) {
            return (match.1, normalized)
        }

        return nil
    }
}

private struct StructuredPaymentPayload: Decodable {
    var source: String?
    var platform: String?
    var payments: [StructuredPaymentItem]?
    var transactions: [StructuredPaymentItem]?
    var records: [StructuredPaymentItem]?
}

private struct StructuredPaymentItem: Decodable {
    var amountText: String?
    var merchant: String?
    var title: String?
    var payee: String?
    var counterparty: String?
    var channel: String?
    var category: String?
    var occurredAt: String?
    var transactionTime: String?
    var date: String?
    var time: String?
    var direction: String?
    var type: String?
    var note: String?
    var rawText: String?

    var normalizedAmount: Decimal? {
        guard let amountText else { return nil }
        let cleaned = amountText
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decimal = Decimal(string: cleaned.replacingOccurrences(of: "＋", with: "+")) else {
            return nil
        }
        return decimal < 0 ? -decimal : decimal
    }

    enum CodingKeys: String, CodingKey {
        case amount
        case amountText
        case merchant
        case title
        case payee
        case counterparty
        case channel
        case category
        case occurredAt
        case transactionTime
        case date
        case time
        case direction
        case type
        case note
        case rawText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amountText = Self.decodeAmountText(from: container)
        merchant = try? container.decode(String.self, forKey: .merchant)
        title = try? container.decode(String.self, forKey: .title)
        payee = try? container.decode(String.self, forKey: .payee)
        counterparty = try? container.decode(String.self, forKey: .counterparty)
        channel = try? container.decode(String.self, forKey: .channel)
        category = try? container.decode(String.self, forKey: .category)
        occurredAt = try? container.decode(String.self, forKey: .occurredAt)
        transactionTime = try? container.decode(String.self, forKey: .transactionTime)
        date = try? container.decode(String.self, forKey: .date)
        time = try? container.decode(String.self, forKey: .time)
        direction = try? container.decode(String.self, forKey: .direction)
        type = try? container.decode(String.self, forKey: .type)
        note = try? container.decode(String.self, forKey: .note)
        rawText = try? container.decode(String.self, forKey: .rawText)
    }

    private static func decodeAmountText(from container: KeyedDecodingContainer<CodingKeys>) -> String? {
        if let value = try? container.decode(String.self, forKey: .amount) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: .amount) {
            return String(value)
        }
        if let value = try? container.decode(Int.self, forKey: .amount) {
            return String(value)
        }
        if let value = try? container.decode(String.self, forKey: .amountText) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: .amountText) {
            return String(value)
        }
        return nil
    }
}
