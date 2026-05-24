import Foundation
import CryptoKit
import UIKit
import Vision

enum ReceiptImageParser {
    static func parse(image: UIImage) async throws -> ParsedPayment? {
        try await parseAll(image: image).first
    }

    static func parseAll(image: UIImage) async throws -> [ParsedPayment] {
        let preparedImage = image.awemeBillingPreparedForOCR()

        if let credentials = tencentOCRCredentials {
            if let text = try? await recognizeTextWithTencentOCR(image: preparedImage, credentials: credentials),
               !text.isEmpty {
                let payments = PaymentTextParser.parseAll(text)
                if !payments.isEmpty {
                    return payments
                }
            }
        }

        if let ocrSpaceAPIKey, !ocrSpaceAPIKey.isEmpty {
            if let text = try? await recognizeTextWithOCRSpace(image: preparedImage, apiKey: ocrSpaceAPIKey),
               !text.isEmpty {
                let payments = PaymentTextParser.parseAll(text)
                if !payments.isEmpty {
                    return payments
                }
            }
        }

        let text = try await recognizeText(image: preparedImage)
        return PaymentTextParser.parseAll(text)
    }

    private static func recognizeTextWithTencentOCR(image: UIImage, credentials: TencentOCRCredentials) async throws -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.82) else { return nil }

        for action in ["GeneralAccurateOCR", "GeneralBasicOCR"] {
            if let text = try await recognizeTextWithTencentOCR(
                imageData: imageData,
                credentials: credentials,
                action: action
            ), !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private static func recognizeTextWithTencentOCR(
        imageData: Data,
        credentials: TencentOCRCredentials,
        action: String
    ) async throws -> String? {
        var payload: [String: Any] = [
            "ImageBase64": imageData.base64EncodedString()
        ]
        if action == "GeneralAccurateOCR" {
            payload["EnableDetectSplit"] = true
        }

        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        guard let payloadString = String(data: payloadData, encoding: .utf8) else { return nil }

        let timestamp = Int(Date().timeIntervalSince1970)
        let endpoint = "ocr.tencentcloudapi.com"
        let authorization = TencentCloudSignature.authorization(
            payload: payloadString,
            action: action,
            endpoint: endpoint,
            timestamp: timestamp,
            credentials: credentials
        )

        var request = URLRequest(url: URL(string: "https://\(endpoint)")!)
        request.httpMethod = "POST"
        request.httpBody = payloadData
        request.timeoutInterval = 20
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint, forHTTPHeaderField: "Host")
        request.setValue(action, forHTTPHeaderField: "X-TC-Action")
        request.setValue("2018-11-19", forHTTPHeaderField: "X-TC-Version")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-TC-Timestamp")
        request.setValue("zh-CN", forHTTPHeaderField: "X-TC-Language")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let response = root["Response"] as? [String: Any],
            response["Error"] == nil,
            let detections = response["TextDetections"] as? [[String: Any]]
        else { return nil }

        let text = detections
            .compactMap { $0["DetectedText"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
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

        let bundleKey = (Bundle.main.object(forInfoDictionaryKey: "OCRSpaceAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bundleKey, !bundleKey.isEmpty, !bundleKey.hasPrefix("$(") else { return nil }
        return bundleKey
    }

    private static var tencentOCRCredentials: TencentOCRCredentials? {
        let environmentSecretId = ProcessInfo.processInfo.environment["TENCENT_OCR_SECRET_ID"]
        let environmentSecretKey = ProcessInfo.processInfo.environment["TENCENT_OCR_SECRET_KEY"]
        let bundleSecretId = Bundle.main.object(forInfoDictionaryKey: "TencentOCRSecretId") as? String
        let bundleSecretKey = Bundle.main.object(forInfoDictionaryKey: "TencentOCRSecretKey") as? String

        let secretId = (environmentSecretId ?? bundleSecretId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let secretKey = (environmentSecretKey ?? bundleSecretKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let secretId,
            let secretKey,
            !secretId.isEmpty,
            !secretKey.isEmpty,
            !secretId.hasPrefix("$("),
            !secretKey.hasPrefix("$(")
        else { return nil }

        return TencentOCRCredentials(secretId: secretId, secretKey: secretKey)
    }
}

private struct TencentOCRCredentials {
    let secretId: String
    let secretKey: String
}

private enum TencentCloudSignature {
    static func authorization(
        payload: String,
        action: String,
        endpoint: String,
        timestamp: Int,
        credentials: TencentOCRCredentials
    ) -> String {
        let algorithm = "TC3-HMAC-SHA256"
        let service = "ocr"
        let date = utcDateString(from: TimeInterval(timestamp))
        let credentialScope = "\(date)/\(service)/tc3_request"
        let signedHeaders = "content-type;host;x-tc-action"
        let canonicalHeaders = [
            "content-type:application/json; charset=utf-8",
            "host:\(endpoint)",
            "x-tc-action:\(action.lowercased())"
        ].joined(separator: "\n") + "\n"

        let canonicalRequest = [
            "POST",
            "/",
            "",
            canonicalHeaders,
            signedHeaders,
            sha256Hex(payload)
        ].joined(separator: "\n")

        let stringToSign = [
            algorithm,
            String(timestamp),
            credentialScope,
            sha256Hex(canonicalRequest)
        ].joined(separator: "\n")

        let secretDate = hmacSHA256(Data("TC3\(credentials.secretKey)".utf8), Data(date.utf8))
        let secretService = hmacSHA256(secretDate, Data(service.utf8))
        let secretSigning = hmacSHA256(secretService, Data("tc3_request".utf8))
        let signature = hmacSHA256Hex(secretSigning, Data(stringToSign.utf8))

        return "\(algorithm) Credential=\(credentials.secretId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    private static func utcDateString(from timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).hexString
    }

    private static func hmacSHA256(_ key: Data, _ data: Data) -> Data {
        let key = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    private static func hmacSHA256Hex(_ key: Data, _ data: Data) -> String {
        hmacSHA256(key, data).hexString
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

extension UIImage {
    func awemeBillingPreparedForOCR(maxPixelDimension: CGFloat = 1800) -> UIImage {
        guard let cgImage else { return self }

        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let maxPixel = max(pixelWidth, pixelHeight)
        guard maxPixel > maxPixelDimension else { return self }

        let ratio = maxPixelDimension / maxPixel
        let targetSize = CGSize(width: pixelWidth * ratio, height: pixelHeight * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private extension Sequence where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
