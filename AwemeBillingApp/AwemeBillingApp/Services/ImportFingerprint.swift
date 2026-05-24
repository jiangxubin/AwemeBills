import CryptoKit
import Foundation

enum ImportFingerprint {
    static func text(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return sha256(normalized)
    }

    static func candidate(payment: ParsedPayment, rawText: String) -> String {
        [
            normalizedMerchant(payment.merchant),
            String(ExpenseRecordMaintenance.centsValue(from: payment.amount)),
            payment.channel.rawValue,
            payment.occurredAt.map { minuteText(from: $0) } ?? "",
            text(rawText)
        ].joined(separator: "|")
    }

    private static func normalizedMerchant(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }

    private static func minuteText(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return [
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        ].map(String.init).joined(separator: "-")
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
