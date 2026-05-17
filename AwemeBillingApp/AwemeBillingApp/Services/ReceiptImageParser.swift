import Foundation
import UIKit
import Vision

enum ReceiptImageParser {
    static func parse(image: UIImage) async throws -> ParsedPayment? {
        try await parseAll(image: image).first
    }

    static func parseAll(image: UIImage) async throws -> [ParsedPayment] {
        if let ocrSpaceAPIKey, !ocrSpaceAPIKey.isEmpty {
            if let text = try? await recognizeTextWithOCRSpace(image: image, apiKey: ocrSpaceAPIKey),
               !text.isEmpty {
                let payments = PaymentTextParser.parseAll(text)
                if !payments.isEmpty {
                    return payments
                }
            }
        }

        let text = try await recognizeText(image: image)
        return PaymentTextParser.parseAll(text)
    }

    static func recognizeText(image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImagePropertyOrientation)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func recognizeTextWithOCRSpace(image: UIImage, apiKey: String) async throws -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.82) else { return nil }

        let formItems = [
            URLQueryItem(name: "base64Image", value: "data:image/jpeg;base64,\(imageData.base64EncodedString())"),
            URLQueryItem(name: "language", value: "chs"),
            URLQueryItem(name: "isOverlayRequired", value: "false"),
            URLQueryItem(name: "detectOrientation", value: "true"),
            URLQueryItem(name: "scale", value: "true"),
            URLQueryItem(name: "OCREngine", value: "2")
        ]

        var components = URLComponents()
        components.queryItems = formItems

        let url = URL(string: "https://api.ocr.space/parse/image")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let parsedResults = root["ParsedResults"] as? [[String: Any]]
        else { return nil }

        if root["IsErroredOnProcessing"] as? Bool == true {
            return nil
        }

        let text = parsedResults
            .compactMap { $0["ParsedText"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static var ocrSpaceAPIKey: String? {
        let environmentKey = ProcessInfo.processInfo.environment["OCR_SPACE_API_KEY"]
        if let environmentKey, !environmentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (Bundle.main.object(forInfoDictionaryKey: "OCRSpaceAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
