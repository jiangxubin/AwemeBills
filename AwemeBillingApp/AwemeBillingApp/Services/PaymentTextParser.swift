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
        let listPayments = parseAlipayBillList(text)
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

    private static func parseAlipayBillList(_ text: String) -> [ParsedPayment] {
        guard text.contains("搜索交易记录") || text.contains("收支分析") || text.contains("本月已省") else {
            return []
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var payments: [ParsedPayment] = []
        var previousTransactionBoundaryIndex = -1

        for index in lines.indices {
            guard let amount = expenseAmount(fromBillAmountLine: lines[index]) else {
                if isBillAmountBoundaryLine(lines[index]) {
                    previousTransactionBoundaryIndex = index
                }
                continue
            }

            let lowerBound = previousTransactionBoundaryIndex + 1
            let timeIndex = stride(from: index - 1, through: lowerBound, by: -1)
                .first { isBillTimeLine(lines[$0]) }

            let merchantIndex: Int
            let categoryIndex: Int?

            if let timeIndex, timeIndex - 2 >= lowerBound {
                merchantIndex = timeIndex - 2
                categoryIndex = timeIndex - 1
            } else if index - 2 >= lowerBound {
                merchantIndex = index - 2
                categoryIndex = index - 1
            } else {
                previousTransactionBoundaryIndex = index
                continue
            }

            let merchant = cleanedBillMerchant(lines[merchantIndex])
            guard !merchant.isEmpty, !shouldIgnoreBillMerchant(merchant) else {
                previousTransactionBoundaryIndex = index
                continue
            }

            let categoryText = categoryIndex.map { lines[$0] } ?? ""
            let context = [merchant, categoryText].joined(separator: " ")
            payments.append(
                ParsedPayment(
                    amount: amount,
                    merchant: merchant,
                    channel: .alipay,
                    note: [merchant, categoryText, timeIndex.map { lines[$0] } ?? "", lines[index]]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n"),
                    occurredAt: timeIndex.flatMap { billDate(from: lines[$0]) },
                    category: category(in: context)
                )
            )
            previousTransactionBoundaryIndex = index
        }

        return payments
    }

    private static func firstAmount(in text: String) -> Decimal? {
        let preferredPatterns = [
            #"交易金额\s*([0-9]+(?:\.[0-9]{1,2})?)"#,
            #"金额[:：\s]*[¥￥]?\s*([0-9]+(?:\.[0-9]{1,2})?)"#,
            #"消费[:：\s]*[¥￥]?\s*([0-9]+(?:\.[0-9]{1,2})?)"#
        ]
        for pattern in preferredPatterns {
            if let amount = matchDecimal(pattern: pattern, in: text) {
                return amount
            }
        }

        let fallbackPatterns = [
            #"(?:(?:¥|￥|人民币|CNY)\s*)([0-9]+(?:\.[0-9]{1,2})?)"#,
            #"([0-9]+(?:\.[0-9]{1,2})?)\s*元"#
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
        return Decimal(string: String(text[range]))
    }

    private static func channel(in text: String) -> PaymentChannel {
        if text.contains("支付宝") { return .alipay }
        if text.contains("余额宝") || text.contains("收支分析") || text.contains("搜索交易记录") { return .alipay }
        if text.contains("微信") { return .wechat }
        if text.contains("云闪付") || text.contains("银联") { return .unionPay }
        if text.contains("银行") || text.contains("信用卡") || text.contains("卡号") { return .bankCard }
        return .other
    }

    private static func merchant(in text: String, channel: PaymentChannel) -> String {
        if let merchant = lineValue(after: "商户名称", in: text) {
            return merchant
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

    private static func category(in text: String) -> ExpenseCategory {
        if text.contains("餐饮") || text.contains("美食") || text.contains("咖啡") || text.contains("外卖") || text.contains("大米先生") || text.contains("你六姐") { return .dining }
        if text.contains("停车") || text.contains("爱车") || text.contains("养车") || text.contains("地铁") || text.contains("公交") || text.contains("打车") { return .commute }
        if text.contains("文化") || text.contains("休闲") || text.contains("电影") { return .entertainment }
        if text.contains("交易类型") && text.contains("消费") { return .shopping }
        if text.contains("转账") { return .transfer }
        return .other
    }

    private static func expenseAmount(fromBillAmountLine line: String) -> Decimal? {
        let pattern = #"^[-−]\s*([0-9]+(?:\.[0-9]{1,2})?)$"#
        return matchDecimal(pattern: pattern, in: line)
    }

    private static func isBillAmountBoundaryLine(_ line: String) -> Bool {
        line.range(of: #"^[+＋]?\s*[0-9]+(?:\.[0-9]{1,2})$"#, options: .regularExpression) != nil
    }

    private static func isBillTimeLine(_ line: String) -> Bool {
        line.contains("今天") || line.contains("昨天") || line.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil
    }

    private static func cleanedBillMerchant(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[-−]\s*⋯$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[-−]\s*\.\.\.$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldIgnoreBillMerchant(_ merchant: String) -> Bool {
        let ignoredFragments = ["支出", "收入", "本月已省", "收支分析", "搜索", "筛选", "全部", "退款", "转账", "订单"]
        return ignoredFragments.contains { merchant.contains($0) }
    }

    private static func billDate(from line: String, now: Date = .now) -> Date? {
        let pattern = #"(今天|昨天)?\s*([0-9]{1,2}):([0-9]{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let hourRange = Range(match.range(at: 2), in: line),
              let minuteRange = Range(match.range(at: 3), in: line),
              let hour = Int(line[hourRange]),
              let minute = Int(line[minuteRange])
        else { return nil }

        let dayOffset = (Range(match.range(at: 1), in: line).map { String(line[$0]) } == "昨天") ? -1 : 0
        let calendar = Calendar.current
        let baseDate = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate)
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
}
