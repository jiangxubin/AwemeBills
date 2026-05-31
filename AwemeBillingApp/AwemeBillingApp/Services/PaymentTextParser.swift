import Foundation

struct ParsedPayment {
    let amount: Decimal
    let merchant: String
    let channel: PaymentChannel
    let note: String
    let occurredAt: Date?
    let category: ExpenseCategory
}

enum PaymentTextParser {
    static func parseAll(_ text: String) -> [ParsedPayment] {
        let listPayments = parseBillList(text)
        if !listPayments.isEmpty {
            return listPayments
        }

        return parse(text).map { [$0] } ?? []
    }

    static func parse(_ text: String) -> ParsedPayment? {
        guard let amount = firstAmount(in: text) else { return nil }
        let channel = channel(in: text)
        let merchant = merchant(in: text, channel: channel)
        return ParsedPayment(
            amount: amount,
            merchant: merchant,
            channel: channel,
            note: text,
            occurredAt: occurredAt(in: text),
            category: category(in: text)
        )
    }

    private struct BillAmountLine {
        let amount: Decimal
        let isIncome: Bool
        let originalText: String
    }

    private static func parseBillList(_ text: String) -> [ParsedPayment] {
        guard looksLikeBillList(text) else {
            return []
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var payments: [ParsedPayment] = []
        var previousAmountIndex = -1
        let channel = billListChannel(in: text)

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

            let categoryText = categoryNearAmount(lines, amountIndex: index, lowerBound: lowerBound) ?? ""
            let timeLine = timeLineNearAmount(lines, amountIndex: index, lowerBound: lowerBound)
            let context = [merchant, categoryText, amountLine.isIncome ? "收入 退款" : ""].joined(separator: " ")
            payments.append(
                ParsedPayment(
                    amount: amountLine.amount,
                    merchant: merchant,
                    channel: channel,
                    note: [merchant, categoryText, timeLine ?? "", amountLine.originalText]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n"),
                    occurredAt: timeLine.flatMap { billDate(from: $0) },
                    category: category(in: context)
                )
            )
            previousAmountIndex = index
        }

        return payments
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

    private static func channel(in text: String) -> PaymentChannel {
        if text.contains("支付宝") { return .alipay }
        if text.contains("余额宝") || text.contains("收支分析") || text.contains("搜索交易记录") { return .alipay }
        if text.contains("微信") { return .wechat }
        if text.contains("云闪付") || text.contains("银联") { return .unionPay }
        if text.contains("银行") || text.contains("信用卡") || text.contains("卡号") { return .bankCard }
        return .other
    }

    private static func billListChannel(in text: String) -> PaymentChannel {
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
        let nearbyText = (searchStart...amountIndex)
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
        lowerBound: Int
    ) -> String? {
        let searchStart = max(lowerBound, amountIndex - 4)
        return stride(from: amountIndex - 1, through: searchStart, by: -1)
            .first { isStandaloneBillCategoryLine(lines[$0]) }
            .map { lines[$0] }
    }

    private static func timeLineNearAmount(
        _ lines: [String],
        amountIndex: Int,
        lowerBound: Int
    ) -> String? {
        let searchStart = max(lowerBound, amountIndex - 4)
        return stride(from: amountIndex - 1, through: searchStart, by: -1)
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
            "充值", "缴费", "商业服务", "车位", "日用", "百货", "收益", "群收款"
        ]
        return categoryFragments.contains { line.contains($0) }
    }

    private static func isStandaloneBillCategoryLine(_ line: String) -> Bool {
        let standaloneCategories: Set<String> = [
            "餐饮美食", "爱车养车", "文化休闲", "投资理财", "日用百货",
            "退款", "充值缴费", "商业服务", "交通出行", "购物消费",
            "生活服务", "转账", "消费", "收入"
        ]
        return standaloneCategories.contains(line)
    }

    private static func billDate(from line: String, now: Date = .now) -> Date? {
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

        let year = calendar.component(.year, from: now)
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
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
