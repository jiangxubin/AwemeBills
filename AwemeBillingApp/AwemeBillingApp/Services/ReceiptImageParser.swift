import Foundation
import CryptoKit
import UIKit
import Vision

struct OCRRecognitionProviderSnapshot: Identifiable {
    let provider: OCRRecognitionStatistics.Provider
    let attempts: Int
    let recognitionSuccesses: Int
    let parsedSuccesses: Int
    let failures: Int

    var id: OCRRecognitionStatistics.Provider { provider }
}

struct OCRProviderConfigurationSnapshot: Identifiable {
    let provider: OCRRecognitionStatistics.Provider
    let isConfigured: Bool
    let detail: String

    var id: OCRRecognitionStatistics.Provider { provider }
}

enum OCRProviderConfigurationDiagnostics {
    static func snapshot() -> [OCRProviderConfigurationSnapshot] {
        [
            OCRProviderConfigurationSnapshot(
                provider: .tencent,
                isConfigured: ReceiptImageParser.tencentOCRCredentials != nil,
                detail: ReceiptImageParser.tencentOCRCredentials == nil ? "未注入腾讯 SecretId/SecretKey" : "已注入"
            ),
            OCRProviderConfigurationSnapshot(
                provider: .glm,
                isConfigured: GLMReceiptOCRConfiguration.apiKey != nil,
                detail: GLMReceiptOCRConfiguration.apiKey == nil ? "未注入 GLM_OCR_API_KEY" : "已注入"
            ),
            OCRProviderConfigurationSnapshot(
                provider: .ocrSpace,
                isConfigured: OCRSpaceReceiptOCRConfiguration.apiKey != nil,
                detail: OCRSpaceReceiptOCRConfiguration.apiKey == nil ? "未注入 OCR_SPACE_API_KEY" : "已注入"
            ),
            OCRProviderConfigurationSnapshot(
                provider: .vision,
                isConfigured: true,
                detail: "系统兜底可用"
            )
        ]
    }
}

enum OCRRecognitionStatistics {
    enum Provider: String, CaseIterable, Identifiable {
        case glm = "GLM"
        case tencent = "腾讯 OCR"
        case ocrSpace = "OCR.space"
        case vision = "本机 Vision"
        case other = "其他"

        var id: String { rawValue }
    }

    static func snapshot(defaults: UserDefaults = .standard) -> [OCRRecognitionProviderSnapshot] {
        Provider.allCases.map { provider in
            OCRRecognitionProviderSnapshot(
                provider: provider,
                attempts: value(for: provider, field: "attempts", defaults: defaults),
                recognitionSuccesses: value(for: provider, field: "recognitionSuccesses", defaults: defaults),
                parsedSuccesses: value(for: provider, field: "parsedSuccesses", defaults: defaults),
                failures: value(for: provider, field: "failures", defaults: defaults)
            )
        }
    }

    static func recordAttempt(_ provider: Provider, defaults: UserDefaults = .standard) {
        increment(provider, field: "attempts", defaults: defaults)
    }

    static func recordRecognitionSuccess(_ provider: Provider, defaults: UserDefaults = .standard) {
        increment(provider, field: "recognitionSuccesses", defaults: defaults)
    }

    static func recordParsedSuccess(_ provider: Provider, defaults: UserDefaults = .standard) {
        increment(provider, field: "parsedSuccesses", defaults: defaults)
    }

    static func recordFailure(_ provider: Provider, defaults: UserDefaults = .standard) {
        increment(provider, field: "failures", defaults: defaults)
    }

    static func reset(defaults: UserDefaults = .standard) {
        for provider in Provider.allCases {
            for field in ["attempts", "recognitionSuccesses", "parsedSuccesses", "failures"] {
                defaults.removeObject(forKey: key(provider, field: field))
            }
        }
    }

    private static func increment(_ provider: Provider, field: String, defaults: UserDefaults) {
        defaults.set(value(for: provider, field: field, defaults: defaults) + 1, forKey: key(provider, field: field))
    }

    private static func value(for provider: Provider, field: String, defaults: UserDefaults) -> Int {
        defaults.integer(forKey: key(provider, field: field))
    }

    private static func key(_ provider: Provider, field: String) -> String {
        "ocr.recognition.statistics.\(provider.id).\(field)"
    }
}

struct ReceiptOCRTextCandidate {
    let source: String
    let text: String
    var merchantLogoPNGData: Data? = nil
}

protocol ReceiptOCRProvider {
    var displayName: String { get }
    var statisticsProvider: OCRRecognitionStatistics.Provider { get }
    func recognizeTextCandidates(from image: UIImage, preferredChannel: PaymentChannel?) async throws -> [ReceiptOCRTextCandidate]
}

extension ReceiptOCRProvider {
    var statisticsProvider: OCRRecognitionStatistics.Provider { .other }
}

enum ReceiptImageParser {
    static func parse(image: UIImage, preferredChannel: PaymentChannel? = nil) async throws -> ParsedPayment? {
        try await parseAll(image: image, preferredChannel: preferredChannel).first
    }

    static func parseAll(image: UIImage, preferredChannel: PaymentChannel? = nil) async throws -> [ParsedPayment] {
        try await parseAll(
            image: image,
            preferredChannel: preferredChannel,
            providers: defaultProviders()
        )
    }

    static func parseAll(
        image: UIImage,
        preferredChannel: PaymentChannel?,
        providers: [any ReceiptOCRProvider]
    ) async throws -> [ParsedPayment] {
        let preparedImage = image.awemeBillingPreparedForOCR()
        let fallbackLogoData = ReceiptImageSegmenter.merchantLogoData(
            from: preparedImage,
            preferredChannel: preferredChannel
        )
        var lastError: Error?

        for provider in providers {
            let statisticsProvider = provider.statisticsProvider
            OCRRecognitionStatistics.recordAttempt(statisticsProvider)
            do {
                let candidates = try await provider.recognizeTextCandidates(
                    from: preparedImage,
                    preferredChannel: preferredChannel
                )
                let nonEmptyCandidates = candidates.filter {
                    !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if nonEmptyCandidates.isEmpty {
                    OCRRecognitionStatistics.recordFailure(statisticsProvider)
                    continue
                }
                OCRRecognitionStatistics.recordRecognitionSuccess(statisticsProvider)

                var providerPayments: [ParsedPayment] = []
                let shouldDistributeFallbackLogos = nonEmptyCandidates.count == 1
                    && nonEmptyCandidates.first?.merchantLogoPNGData == nil
                for (candidateIndex, candidate) in nonEmptyCandidates.enumerated() {
                    let payments = PaymentTextParser.parseAll(candidate.text, preferredChannel: preferredChannel)
                    providerPayments.append(
                        contentsOf: payments.enumerated().map { paymentIndex, payment in
                            let logoData = candidate.merchantLogoPNGData
                                ?? fallbackLogoData[safe: shouldDistributeFallbackLogos ? paymentIndex : candidateIndex]
                            return payment.withMerchantLogoPNGData(logoData)
                        }
                    )
                }

                if !providerPayments.isEmpty {
                    OCRRecognitionStatistics.recordParsedSuccess(statisticsProvider)
                    return providerPayments
                }
            } catch {
                OCRRecognitionStatistics.recordFailure(statisticsProvider)
                lastError = error
                continue
            }
        }

        if let lastError {
            throw lastError
        }
        return []
    }

    static func parseOCRTexts(
        glmText: String? = nil,
        tencentText: String?,
        ocrSpaceText: String? = nil,
        visionText: String,
        preferredChannel: PaymentChannel? = nil
    ) -> [ParsedPayment] {
        if let tencentText {
            let tencentPayments = PaymentTextParser.parseAll(tencentText, preferredChannel: preferredChannel)
            if !tencentPayments.isEmpty {
                return tencentPayments
            }
        }

        if let glmText {
            let glmPayments = PaymentTextParser.parseAll(glmText, preferredChannel: preferredChannel)
            if !glmPayments.isEmpty {
                return glmPayments
            }
        }

        if let ocrSpaceText {
            let ocrSpacePayments = PaymentTextParser.parseAll(ocrSpaceText, preferredChannel: preferredChannel)
            if !ocrSpacePayments.isEmpty {
                return ocrSpacePayments
            }
        }

        return PaymentTextParser.parseAll(visionText, preferredChannel: preferredChannel)
    }

    private static func defaultProviders() -> [any ReceiptOCRProvider] {
        var providers: [any ReceiptOCRProvider] = []
        if let credentials = tencentOCRCredentials {
            providers.append(TencentReceiptOCRProvider(credentials: credentials))
        }
        if let apiKey = GLMReceiptOCRConfiguration.apiKey {
            providers.append(GLMReceiptOCRProvider(apiKey: apiKey))
        }
        if let apiKey = OCRSpaceReceiptOCRConfiguration.apiKey {
            providers.append(OCRSpaceReceiptOCRProvider(apiKey: apiKey))
        }
        providers.append(LocalVisionReceiptOCRProvider())
        return providers
    }

    #if DEBUG
    static func configuredGLMProviderForTesting() -> (any ReceiptOCRProvider)? {
        guard let apiKey = GLMReceiptOCRConfiguration.apiKey else { return nil }
        return GLMReceiptOCRProvider(apiKey: apiKey)
    }

    static func configuredTencentProviderForTesting() -> (any ReceiptOCRProvider)? {
        guard let credentials = tencentOCRCredentials else { return nil }
        return TencentReceiptOCRProvider(credentials: credentials)
    }
    #endif

    fileprivate static func recognizeTextWithTencentOCR(image: UIImage, credentials: TencentOCRCredentials) async throws -> String? {
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

    fileprivate static func recognizeTextWithTencentOCR(
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

        let text = TencentOCRTextRepair.repairedText(from: detections)
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
                    .compactMap { observation -> (text: String, box: CGRect)? in
                        guard let text = observation.topCandidates(1).first?.string else { return nil }
                        return (text, observation.boundingBox)
                    }
                    .sorted { lhs, rhs in
                        abs(lhs.box.midY - rhs.box.midY) > 0.012
                            ? lhs.box.midY > rhs.box.midY
                            : lhs.box.minX < rhs.box.minX
                    }
                    .map(\.text)
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            request.customWords = [
                "支付宝", "微信支付", "云闪付", "余额宝", "收支分析", "全部账单",
                "餐饮美食", "爱车养车", "日用百货", "充值缴费", "生活缴费",
                "上海耀汇充科技有限公司", "成都你六姐", "大润发", "中海环宇城",
                "城置美宿", "秦碗会", "美团", "已退款", "群收款"
            ]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImagePropertyOrientation)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    fileprivate static var tencentOCRCredentials: TencentOCRCredentials? {
        let environmentSecretId = ProcessInfo.processInfo.environment["TENCENT_OCR_SECRET_ID"]
        let environmentSecretKey = ProcessInfo.processInfo.environment["TENCENT_OCR_SECRET_KEY"]
        let bundleSecretId = Bundle.main.object(forInfoDictionaryKey: "TencentOCRSecretId") as? String
        let bundleSecretKey = Bundle.main.object(forInfoDictionaryKey: "TencentOCRSecretKey") as? String

        let secretId = (environmentSecretId
            ?? bundleSecretId
            ?? BundleRuntimeConfiguration.string(for: "TENCENT_OCR_SECRET_ID")
            ?? BundleRuntimeConfiguration.string(for: "TencentOCRSecretId"))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let secretKey = (environmentSecretKey
            ?? bundleSecretKey
            ?? BundleRuntimeConfiguration.string(for: "TENCENT_OCR_SECRET_KEY")
            ?? BundleRuntimeConfiguration.string(for: "TencentOCRSecretKey"))?
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

private struct GLMReceiptOCRProvider: ReceiptOCRProvider {
    let displayName = "智能识别"
    let statisticsProvider: OCRRecognitionStatistics.Provider = .glm
    let apiKey: String

    func recognizeTextCandidates(from image: UIImage, preferredChannel: PaymentChannel?) async throws -> [ReceiptOCRTextCandidate] {
        let text = try await GLMReceiptOCRService()
            .recognizeStructuredPayments(from: image, apiKey: apiKey, preferredChannel: preferredChannel)
        return [ReceiptOCRTextCandidate(source: displayName, text: text)]
    }
}

private struct TencentReceiptOCRProvider: ReceiptOCRProvider {
    let displayName = "智能识别"
    let statisticsProvider: OCRRecognitionStatistics.Provider = .tencent
    let credentials: TencentOCRCredentials

    func recognizeTextCandidates(from image: UIImage, preferredChannel: PaymentChannel?) async throws -> [ReceiptOCRTextCandidate] {
        let segments = ReceiptImageSegmenter.segmentedRows(from: image, preferredChannel: preferredChannel)
        var candidates: [ReceiptOCRTextCandidate] = []
        var lastError: Error?
        for (index, segment) in segments.enumerated() {
            do {
                guard let text = try await ReceiptImageParser.recognizeTextWithTencentOCR(image: segment.image, credentials: credentials) else {
                    continue
                }
                candidates.append(
                    ReceiptOCRTextCandidate(
                        source: "\(displayName)-\(index + 1)",
                        text: text,
                        merchantLogoPNGData: segment.merchantLogoPNGData
                    )
                )
            } catch {
                lastError = error
                continue
            }
        }
        if candidates.isEmpty, let lastError {
            throw lastError
        }
        return candidates
    }
}

private struct OCRSpaceReceiptOCRProvider: ReceiptOCRProvider {
    let displayName = "备用识别"
    let statisticsProvider: OCRRecognitionStatistics.Provider = .ocrSpace
    let apiKey: String

    func recognizeTextCandidates(from image: UIImage, preferredChannel: PaymentChannel?) async throws -> [ReceiptOCRTextCandidate] {
        let segments = ReceiptImageSegmenter.segmentedRows(from: image, preferredChannel: preferredChannel)
        var candidates: [ReceiptOCRTextCandidate] = []
        var lastError: Error?
        for (index, segment) in segments.enumerated() {
            do {
                let text = try await OCRSpaceReceiptOCRService().recognizeText(from: segment.image, apiKey: apiKey)
                candidates.append(
                    ReceiptOCRTextCandidate(
                        source: "\(displayName)-\(index + 1)",
                        text: text,
                        merchantLogoPNGData: segment.merchantLogoPNGData
                    )
                )
            } catch {
                lastError = error
                continue
            }
        }
        if candidates.isEmpty, let lastError {
            throw lastError
        }
        return candidates
    }
}

private struct LocalVisionReceiptOCRProvider: ReceiptOCRProvider {
    let displayName = "本机识别"
    let statisticsProvider: OCRRecognitionStatistics.Provider = .vision

    func recognizeTextCandidates(from image: UIImage, preferredChannel: PaymentChannel?) async throws -> [ReceiptOCRTextCandidate] {
        let segments = ReceiptImageSegmenter.segmentedRows(from: image, preferredChannel: preferredChannel)
        var candidates: [ReceiptOCRTextCandidate] = []
        var lastError: Error?
        for (index, segment) in segments.enumerated() {
            do {
                let text = try await ReceiptImageParser.recognizeText(image: segment.image)
                candidates.append(
                    ReceiptOCRTextCandidate(
                        source: "\(displayName)-\(index + 1)",
                        text: text,
                        merchantLogoPNGData: segment.merchantLogoPNGData
                    )
                )
            } catch {
                lastError = error
                continue
            }
        }
        if candidates.isEmpty, let lastError {
            throw lastError
        }
        return candidates
    }
}

struct ReceiptImageSegment {
    let image: UIImage
    let merchantLogoPNGData: Data?
}

enum ReceiptImageSegmenter {
    static func segments(from image: UIImage, preferredChannel: PaymentChannel?) -> [UIImage] {
        segmentedRows(from: image, preferredChannel: preferredChannel).map(\.image)
    }

    static func merchantLogoData(from image: UIImage, preferredChannel: PaymentChannel?) -> [Data] {
        let directLogos = directMerchantLogoPNGData(from: image)
        if directLogos.count >= 2 {
            return directLogos
        }
        return segmentedRows(from: image, preferredChannel: preferredChannel).compactMap(\.merchantLogoPNGData)
    }

    static func segmentedRows(from image: UIImage, preferredChannel: PaymentChannel?) -> [ReceiptImageSegment] {
        guard preferredChannel == nil || preferredChannel == .alipay || preferredChannel == .wechat,
              let cgImage = image.cgImage else {
            return [ReceiptImageSegment(image: image, merchantLogoPNGData: merchantLogoPNGData(from: image))]
        }

        let boundaries = separatorBoundaries(in: cgImage)
        guard boundaries.count >= 2 else {
            return [ReceiptImageSegment(image: image, merchantLogoPNGData: merchantLogoPNGData(from: image))]
        }

        let imageHeight = CGFloat(cgImage.height)
        let medianGap = medianGap(in: boundaries) ?? imageHeight * 0.12
        let padding = max(10, medianGap * 0.08)
        let minHeight = max(80, imageHeight * 0.035)
        var segments: [ReceiptImageSegment] = []
        var previousBoundary: CGFloat?

        for boundary in boundaries {
            let top = previousBoundary ?? max(0, boundary - medianGap)
            let paddedTop = max(0, top - padding)
            let paddedBottom = min(imageHeight, boundary + padding)
            if paddedBottom - paddedTop >= minHeight,
               let segment = crop(image, y: paddedTop, height: paddedBottom - paddedTop) {
                segments.append(
                    ReceiptImageSegment(
                        image: segment,
                        merchantLogoPNGData: merchantLogoPNGData(from: segment)
                    )
                )
            }
            previousBoundary = boundary
            if segments.count >= 12 { break }
        }

        if let lastBoundary = previousBoundary,
           segments.count < 12 {
            let paddedTop = max(0, lastBoundary - padding)
            let paddedBottom = min(imageHeight, lastBoundary + medianGap + padding)
            if paddedBottom - paddedTop >= minHeight,
               let segment = crop(image, y: paddedTop, height: paddedBottom - paddedTop) {
                segments.append(
                    ReceiptImageSegment(
                        image: segment,
                        merchantLogoPNGData: merchantLogoPNGData(from: segment)
                    )
                )
            }
        }

        if segments.count >= 2 {
            return segments
        }
        return [ReceiptImageSegment(image: image, merchantLogoPNGData: merchantLogoPNGData(from: image))]
    }

    private static func separatorBoundaries(in cgImage: CGImage) -> [CGFloat] {
        let originalWidth = cgImage.width
        let originalHeight = cgImage.height
        guard originalWidth > 0, originalHeight > 0 else { return [] }

        let analysisWidth = 360
        let scale = CGFloat(analysisWidth) / CGFloat(originalWidth)
        let analysisHeight = max(1, Int(CGFloat(originalHeight) * scale))
        let bytesPerPixel = 4
        let bytesPerRow = analysisWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: analysisHeight * bytesPerRow)

        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: analysisWidth,
                height: analysisHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: analysisWidth, height: analysisHeight))
            return true
        }
        guard didDraw else { return [] }

        let xStart = Int(CGFloat(analysisWidth) * 0.14)
        let xEnd = Int(CGFloat(analysisWidth) * 0.97)
        let yStart = Int(CGFloat(analysisHeight) * 0.16)
        let yEnd = Int(CGFloat(analysisHeight) * 0.96)
        var candidateRows: [Int] = []

        for y in yStart..<yEnd {
            var hits = 0
            var total = 0
            for x in stride(from: xStart, to: xEnd, by: 2) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                guard offset + 2 < pixels.count else { continue }
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                let maxValue = max(red, green, blue)
                let minValue = min(red, green, blue)
                let luminance = (red + green + blue) / 3
                let neutral = maxValue - minValue <= 10
                let lightSeparator = luminance >= 218 && luminance <= 248
                let darkSeparator = luminance >= 26 && luminance <= 62
                if neutral && (lightSeparator || darkSeparator) {
                    hits += 1
                }
                total += 1
            }
            guard total > 0 else { continue }
            if Double(hits) / Double(total) >= 0.46 {
                candidateRows.append(y)
            }
        }

        let mergedRows = mergeCloseRows(candidateRows)
        return mergedRows.map { CGFloat($0) / scale }
    }

    private static func mergeCloseRows(_ rows: [Int]) -> [Int] {
        guard !rows.isEmpty else { return [] }
        var groups: [[Int]] = []
        var currentGroup = [rows[0]]

        for row in rows.dropFirst() {
            if let previous = currentGroup.last, row - previous <= 3 {
                currentGroup.append(row)
            } else {
                groups.append(currentGroup)
                currentGroup = [row]
            }
        }
        groups.append(currentGroup)

        return groups
            .map { group in group.reduce(0, +) / group.count }
            .filterAdjacent(minDistance: 36)
    }

    private static func mergeRowGroups(_ rows: [Int], maxGap: Int) -> [[Int]] {
        guard !rows.isEmpty else { return [] }
        var groups: [[Int]] = []
        var currentGroup = [rows[0]]

        for row in rows.dropFirst() {
            if let previous = currentGroup.last, row - previous <= maxGap {
                currentGroup.append(row)
            } else {
                groups.append(currentGroup)
                currentGroup = [row]
            }
        }
        groups.append(currentGroup)
        return groups
    }

    private static func medianGap(in values: [CGFloat]) -> CGFloat? {
        let gaps = zip(values, values.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0 }
            .sorted()
        guard !gaps.isEmpty else { return nil }
        return gaps[gaps.count / 2]
    }

    private static func merchantLogoPNGData(from segment: UIImage) -> Data? {
        guard let cgImage = segment.cgImage else { return nil }
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        guard imageWidth > 120, imageHeight > 70 else { return nil }

        let searchRect = CGRect(
            x: imageWidth * 0.035,
            y: imageHeight * 0.08,
            width: imageWidth * 0.16,
            height: imageHeight * 0.68
        ).integral
        guard let logoBounds = logoColorBounds(in: cgImage, searchRect: searchRect) else { return nil }

        let expanded = logoBounds.insetBy(dx: -8, dy: -8)
        let side = min(
            max(max(expanded.width, expanded.height), min(imageWidth, imageHeight) * 0.22),
            min(imageWidth * 0.20, imageHeight * 0.82)
        )
        let square = CGRect(
            x: expanded.midX - side / 2,
            y: expanded.midY - side / 2,
            width: side,
            height: side
        )
        let clamped = clamp(square, inside: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)).integral

        guard let cropped = crop(segment, rect: clamped) else { return nil }
        return normalizedLogoPNGData(from: cropped)
    }

    private static func directMerchantLogoPNGData(from image: UIImage) -> [Data] {
        guard let cgImage = image.cgImage else { return [] }
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        guard imageWidth > 120, imageHeight > 240 else { return [] }

        let searchRect = CGRect(
            x: imageWidth * 0.03,
            y: imageHeight * 0.22,
            width: imageWidth * 0.17,
            height: imageHeight * 0.76
        ).integral
        let bounds = logoColorBoundsByRows(in: cgImage, searchRect: searchRect)

        return bounds.compactMap { logoBounds in
            let expanded = logoBounds.insetBy(dx: -8, dy: -8)
            let side = min(
                max(max(expanded.width, expanded.height), imageWidth * 0.055),
                min(imageWidth * 0.16, imageHeight * 0.09)
            )
            let square = CGRect(
                x: expanded.midX - side / 2,
                y: expanded.midY - side / 2,
                width: side,
                height: side
            )
            let clamped = clamp(square, inside: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)).integral
            guard let cropped = crop(image, rect: clamped) else { return nil }
            return normalizedLogoPNGData(from: cropped)
        }
    }

    private static func logoColorBoundsByRows(in cgImage: CGImage, searchRect: CGRect) -> [CGRect] {
        let rect = searchRect
            .intersection(CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
            .integral
        guard rect.width >= 12, rect.height >= 12,
              let cropped = cgImage.cropping(to: rect) else {
            return []
        }

        let width = cropped.width
        let height = cropped.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return [] }

        var candidateRows: [Int] = []
        for y in 0..<height {
            var hits = 0
            for x in stride(from: 0, to: width, by: 2) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                guard offset + 3 < pixels.count else { continue }
                if isLogoPixel(
                    red: Int(pixels[offset]),
                    green: Int(pixels[offset + 1]),
                    blue: Int(pixels[offset + 2]),
                    alpha: Int(pixels[offset + 3])
                ) {
                    hits += 1
                }
            }
            if hits >= 3 {
                candidateRows.append(y)
            }
        }

        return mergeRowGroups(candidateRows, maxGap: 10)
            .compactMap { group -> CGRect? in
                let minGroupY = max(0, (group.first ?? 0) - 4)
                let maxGroupY = min(height - 1, (group.last ?? 0) + 4)
                var minX = width
                var maxX = 0
                var minY = height
                var maxY = 0
                var hitCount = 0

                for y in minGroupY...maxGroupY {
                    for x in stride(from: 0, to: width, by: 2) {
                        let offset = y * bytesPerRow + x * bytesPerPixel
                        guard offset + 3 < pixels.count else { continue }
                        guard isLogoPixel(
                            red: Int(pixels[offset]),
                            green: Int(pixels[offset + 1]),
                            blue: Int(pixels[offset + 2]),
                            alpha: Int(pixels[offset + 3])
                        ) else { continue }
                        minX = min(minX, x)
                        maxX = max(maxX, x)
                        minY = min(minY, y)
                        maxY = max(maxY, y)
                        hitCount += 1
                    }
                }

                guard hitCount >= 12, maxX > minX, maxY > minY else { return nil }
                let bounds = CGRect(
                    x: rect.minX + CGFloat(minX),
                    y: rect.minY + CGFloat(minY),
                    width: CGFloat(maxX - minX + 2),
                    height: CGFloat(maxY - minY + 2)
                )
                guard bounds.width >= 8, bounds.height >= 8 else { return nil }
                return bounds
            }
            .filterAdjacentLogos(minDistance: CGFloat(cgImage.height) * 0.035)
    }

    private static func logoColorBounds(in cgImage: CGImage, searchRect: CGRect) -> CGRect? {
        let rect = searchRect
            .intersection(CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
            .integral
        guard rect.width >= 12, rect.height >= 12,
              let cropped = cgImage.cropping(to: rect) else {
            return nil
        }

        let width = cropped.width
        let height = cropped.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }

        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var hitCount = 0

        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                guard offset + 3 < pixels.count else { continue }
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                let alpha = Int(pixels[offset + 3])
                guard alpha > 30 else { continue }

                guard isLogoPixel(red: red, green: green, blue: blue, alpha: alpha) else { continue }

                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                hitCount += 1
            }
        }

        guard hitCount >= 12, maxX > minX, maxY > minY else { return nil }
        let bounds = CGRect(
            x: rect.minX + CGFloat(minX),
            y: rect.minY + CGFloat(minY),
            width: CGFloat(maxX - minX + 2),
            height: CGFloat(maxY - minY + 2)
        )
        guard bounds.width >= 8, bounds.height >= 8 else { return nil }
        return bounds
    }

    private static func isLogoPixel(red: Int, green: Int, blue: Int, alpha: Int) -> Bool {
        guard alpha > 30 else { return false }
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let chroma = maxValue - minValue
        let luminance = (red + green + blue) / 3
        let colorfulLogoPixel = chroma >= 26 && luminance <= 248
        let darkColoredLogoPixel = chroma >= 10 && luminance <= 88
        return colorfulLogoPixel || darkColoredLogoPixel
    }

    private static func normalizedLogoPNGData(from image: UIImage) -> Data? {
        let outputSize = CGSize(width: 96, height: 96)
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        let normalized = renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: outputSize))
            let inset: CGFloat = 6
            let available = outputSize.width - inset * 2
            let scale = min(available / max(image.size.width, 1), available / max(image.size.height, 1))
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let drawRect = CGRect(
                x: (outputSize.width - drawSize.width) / 2,
                y: (outputSize.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            image.draw(in: drawRect)
        }
        return normalized.pngData()
    }

    private static func clamp(_ rect: CGRect, inside bounds: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func crop(_ image: UIImage, y: CGFloat, height: CGFloat) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let rect = CGRect(
            x: 0,
            y: max(0, y).rounded(.down),
            width: CGFloat(cgImage.width),
            height: min(CGFloat(cgImage.height) - max(0, y), height).rounded(.up)
        )
        guard rect.height > 0,
              let cropped = cgImage.cropping(to: rect) else {
            return nil
        }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func crop(_ image: UIImage, rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let safeRect = rect.intersection(imageBounds).integral
        guard safeRect.width > 0, safeRect.height > 0,
              let cropped = cgImage.cropping(to: safeRect) else {
            return nil
        }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

private extension Array where Element == Int {
    func filterAdjacent(minDistance: Int) -> [Int] {
        reduce(into: []) { result, value in
            guard let last = result.last else {
                result.append(value)
                return
            }
            if value - last >= minDistance {
                result.append(value)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array where Element == CGRect {
    func filterAdjacentLogos(minDistance: CGFloat) -> [CGRect] {
        reduce(into: []) { result, rect in
            guard let last = result.last else {
                result.append(rect)
                return
            }
            if rect.midY - last.midY >= minDistance {
                result.append(rect)
            } else if rect.width * rect.height > last.width * last.height {
                result[result.count - 1] = rect
            }
        }
    }
}

private enum GLMReceiptOCRConfiguration {
    static var apiKey: String? {
        cleaned(ProcessInfo.processInfo.environment["GLM_OCR_API_KEY"])
            ?? cleaned(ProcessInfo.processInfo.environment["GLM_API_KEY"])
            ?? cleaned(ProcessInfo.processInfo.environment["ZHIPU_API_KEY"])
            ?? cleaned(Bundle.main.object(forInfoDictionaryKey: "GLM_OCR_API_KEY") as? String)
            ?? cleaned(Bundle.main.object(forInfoDictionaryKey: "GLM_API_KEY") as? String)
            ?? BundleRuntimeConfiguration.string(for: "GLM_OCR_API_KEY")
            ?? BundleRuntimeConfiguration.string(for: "GLM_API_KEY")
            ?? BundleRuntimeConfiguration.string(for: "ZHIPU_API_KEY")
    }

    private static func cleaned(_ key: String?) -> String? {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

private enum OCRSpaceReceiptOCRConfiguration {
    static var apiKey: String? {
        cleaned(ProcessInfo.processInfo.environment["OCR_SPACE_API_KEY"])
            ?? cleaned(Bundle.main.object(forInfoDictionaryKey: "OCR_SPACE_API_KEY") as? String)
            ?? BundleRuntimeConfiguration.string(for: "OCR_SPACE_API_KEY")
    }

    private static func cleaned(_ key: String?) -> String? {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

private enum BundleRuntimeConfiguration {
    static func string(for key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "LocalSecrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        let trimmed = (dictionary[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

private struct GLMReceiptOCRService {
    private let session: URLSession
    private let endpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
    private let modelName = "glm-4.6v-flash"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func recognizeStructuredPayments(
        from image: UIImage,
        apiKey: String,
        preferredChannel: PaymentChannel?
    ) async throws -> String {
        guard let imageData = compressedJPEGData(from: image) ?? image.pngData() else {
            throw ReceiptOCRProviderError.invalidImage
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 55
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GLMChatCompletionRequest(
                model: modelName,
                messages: [
                    GLMChatMessage(
                        role: "user",
                        content: [
                            .text(Self.prompt(preferredChannel: preferredChannel)),
                            .image("data:image/jpeg;base64,\(imageData.base64EncodedString())")
                        ]
                    )
                ],
                temperature: 0,
                maxTokens: 3200
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ReceiptOCRProviderError.remoteFailed
        }

        let decoded = try JSONDecoder().decode(GLMChatCompletionResponse.self, from: data)
        let text = decoded.choices
            .map(\.message.content.textValue)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ReceiptOCRProviderError.emptyResult
        }
        return text
    }

    private func compressedJPEGData(from image: UIImage) -> Data? {
        let maxBytes = 1_800_000
        for scale in [1.0, 0.9, 0.78, 0.64, 0.5] {
            let candidate = scale == 1.0 ? image : resized(image, scale: scale)
            for quality in [0.88, 0.76, 0.64, 0.5, 0.36] {
                guard let data = candidate.jpegData(compressionQuality: quality) else { continue }
                if data.count <= maxBytes {
                    return data
                }
            }
        }
        return image.jpegData(compressionQuality: 0.24)
    }

    private func resized(_ image: UIImage, scale: CGFloat) -> UIImage {
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func prompt(preferredChannel: PaymentChannel?) -> String {
        let sourceHint = preferredChannel.map { "用户选择的来源倾向是：\($0.rawValue)。如果截图内容冲突，以截图内容为准。" }
            ?? "用户未选择来源，请从截图内容自行判断微信、支付宝、云闪付、银行卡或其他渠道。"
        let currentYear = Calendar.current.component(.year, from: Date())
        return """
        你是消费账单截图结构化识别器。请从图片中提取所有可见的消费、退款、收入、转账或收益记录，忽略顶部汇总金额、筛选按钮、搜索框、广告气泡和导航栏。
        \(sourceHint)

        只输出 JSON，不要 Markdown，不要解释。JSON 结构必须是：
        {
          "source": "微信支付/支付宝/云闪付/银行卡/其他",
          "payments": [
            {
              "merchant": "商户或交易对象",
              "amount": "-55.10",
              "direction": "expense/income/refund/transfer",
              "channel": "微信支付/支付宝/云闪付/银行卡/其他",
              "category": "餐饮/交通/购物/居家/健康/娱乐/旅行/学习/转账/其他",
              "occurredAt": "yyyy-MM-dd HH:mm",
              "note": "截图中与该笔记录有关的可见补充文字",
              "rawText": "只包含该笔交易所在分隔线区块内的原始可见文字"
            }
          ]
        }

        规则：
        1. 列表中每一行带金额的交易都要提取，不要只提取最大金额。
        2. 金额必须保留截图中的正负号；如果只有数字但旁边是退款、收益、收入、群收款，按正数输出。
        3. 对微信账单暗色列表，黄色 + 金额是收入或退款，白色 - 金额是支出；红色“已退款”只是备注，不要把备注金额当作主交易金额。
        4. 对支付宝账单，右侧主金额是本笔金额，“已退款(¥x)”放进 note；上方月度支出/收入汇总不要作为交易；“交易关闭、待付款、已取消”的订单不要作为实际消费或收入导入。
        5. 微信和支付宝列表中的浅灰色分隔线是强边界：每个分隔线区块内只取该区块的商户、标签、时间、金额和备注，不要跨区块串行，不要借用上一个或下一个区块的标签/时间。
        6. 支付宝列表每条记录通常按从上到下排列为“商户/交易对象、平台标签、时间”，金额在同一视觉区块右侧；category 必须来自同一区块内紧邻商户下方的标签。如果不确定，category 留空或写“其他”，不要从相邻记录借标签。
        7. 支付宝的“餐饮美食、数码电器、日用百货、爱车养车、文化休闲”等平台标签请放入 category 字段，原样保留。
        8. 例如同一张支付宝列表中“C河间门市-pos1 / 日用百货 / 今天 13:38 / -14.35”和“美团 / 餐饮美食 / 今天 12:34 / -221.00”是两条由灰线隔开的独立记录，不能把“日用百货”放到美团上。
        9. 如果截图显示“今天/昨天”或“05-31 / 5月31日”这类不带年份的时间，以当前导入上下文 \(currentYear) 年为参考，跨年边界取最接近当前日期的合理年份，不要臆造 2024、2025 等截图中没有出现的年份；无法确定日期时仍填写可见的月日和时间。
        10. 商户文字被省略号截断时，保留可见部分，不要编造。
        11. merchant 必须是本条记录的商户、交易对象或收款方，不要把“微信支付”“支付宝”这种支付渠道名称填成 merchant；如果某个区块只有汇总金额、占位符或看不清商户，就不要输出这条记录。
        12. rawText 必须和 merchant、amount、occurredAt 同属于同一个视觉分隔线区块；如果 rawText 里的主金额和你准备输出的 amount 冲突，以 rawText 所在区块的右侧主金额为准。
        """
    }
}

struct TencentOCRTextDetection {
    let text: String
    let centerX: CGFloat
    let centerY: CGFloat
    let height: CGFloat

    init?(rawDetection: [String: Any]) {
        let text = (rawDetection["DetectedText"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }

        let points = (rawDetection["Polygon"] as? [[String: Any]]) ?? []
        let xValues = points.compactMap { Self.number($0["X"]) }
        let yValues = points.compactMap { Self.number($0["Y"]) }
        guard !xValues.isEmpty, !yValues.isEmpty else {
            self.text = text
            self.centerX = 0
            self.centerY = 0
            self.height = 0
            return
        }

        self.text = text
        self.centerX = xValues.reduce(0, +) / CGFloat(xValues.count)
        self.centerY = yValues.reduce(0, +) / CGFloat(yValues.count)
        self.height = max(0, (yValues.max() ?? 0) - (yValues.min() ?? 0))
    }

    init(text: String, centerX: CGFloat, centerY: CGFloat, height: CGFloat = 18) {
        self.text = text
        self.centerX = centerX
        self.centerY = centerY
        self.height = height
    }

    private static func number(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        if let double = value as? Double { return CGFloat(double) }
        if let int = value as? Int { return CGFloat(int) }
        if let string = value as? String, let double = Double(string) { return CGFloat(double) }
        return nil
    }
}

enum TencentOCRTextRepair {
    static func repairedText(from rawDetections: [[String: Any]]) -> String {
        repairedText(from: rawDetections.compactMap(TencentOCRTextDetection.init(rawDetection:)))
    }

    static func repairedText(from detections: [TencentOCRTextDetection]) -> String {
        let nonEmptyDetections = detections
            .map { TencentOCRTextDetection(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), centerX: $0.centerX, centerY: $0.centerY, height: $0.height) }
            .filter { !$0.text.isEmpty }
        guard !nonEmptyDetections.isEmpty else { return "" }

        let rowTolerance = max(8, medianHeight(in: nonEmptyDetections) * 0.72)
        var rows: [[TencentOCRTextDetection]] = []

        for detection in nonEmptyDetections.sorted(by: { $0.centerY < $1.centerY }) {
            if let rowIndex = rows.indices.min(by: {
                abs(rows[$0].averageCenterY - detection.centerY) < abs(rows[$1].averageCenterY - detection.centerY)
            }), abs(rows[rowIndex].averageCenterY - detection.centerY) <= rowTolerance {
                rows[rowIndex].append(detection)
            } else {
                rows.append([detection])
            }
        }

        return rows
            .sorted { $0.averageCenterY < $1.averageCenterY }
            .flatMap { row in
                row.sorted { $0.centerX < $1.centerX }.map(\.text)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func medianHeight(in detections: [TencentOCRTextDetection]) -> CGFloat {
        let heights = detections
            .map(\.height)
            .filter { $0 > 0 }
            .sorted()
        guard !heights.isEmpty else { return 18 }
        return heights[heights.count / 2]
    }
}

private extension Array where Element == TencentOCRTextDetection {
    var averageCenterY: CGFloat {
        guard !isEmpty else { return 0 }
        return reduce(CGFloat(0)) { $0 + $1.centerY } / CGFloat(count)
    }
}

private struct OCRSpaceReceiptOCRService {
    func recognizeText(from image: UIImage, apiKey: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw ReceiptOCRProviderError.invalidImage
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.ocr.space/parse/image")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartFormDataBuilder(boundary: boundary)
            .appendField(name: "apikey", value: apiKey)
            .appendField(name: "language", value: "chs")
            .appendField(name: "OCREngine", value: "2")
            .appendField(name: "isOverlayRequired", value: "false")
            .appendFile(name: "file", filename: "receipt.jpg", mimeType: "image/jpeg", data: data)
            .finish()

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ReceiptOCRProviderError.remoteFailed
        }
        let decoded = try JSONDecoder().decode(OCRSpaceResponse.self, from: responseData)
        if decoded.isErroredOnProcessing == true {
            throw ReceiptOCRProviderError.remoteFailed
        }
        let text = (decoded.parsedResults ?? [])
            .compactMap(\.parsedText)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ReceiptOCRProviderError.emptyResult
        }
        return text
    }
}

private enum ReceiptOCRProviderError: Error {
    case invalidImage
    case emptyResult
    case remoteFailed
}

private struct GLMChatCompletionRequest: Encodable {
    let model: String
    let messages: [GLMChatMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct GLMChatMessage: Encodable {
    let role: String
    let content: [GLMChatContent]
}

private enum GLMChatContent: Encodable {
    case text(String)
    case image(String)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(url):
            try container.encode("image_url", forKey: .type)
            try container.encode(GLMImageURL(url: url), forKey: .imageURL)
        }
    }
}

private struct GLMImageURL: Encodable {
    let url: String
}

private struct GLMChatCompletionResponse: Decodable {
    let choices: [GLMChoice]
}

private struct GLMChoice: Decodable {
    let message: GLMResponseMessage
}

private struct GLMResponseMessage: Decodable {
    let content: GLMResponseContent
}

private enum GLMResponseContent: Decodable {
    case text(String)
    case parts([GLMResponsePart])

    var textValue: String {
        switch self {
        case let .text(text):
            return text
        case let .parts(parts):
            return parts.compactMap(\.text).joined(separator: "\n")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = .parts((try? container.decode([GLMResponsePart].self)) ?? [])
    }
}

private struct GLMResponsePart: Decodable {
    let text: String?
}

private struct OCRSpaceResponse: Decodable {
    let parsedResults: [OCRSpaceParsedResult]?
    let isErroredOnProcessing: Bool?

    enum CodingKeys: String, CodingKey {
        case parsedResults = "ParsedResults"
        case isErroredOnProcessing = "IsErroredOnProcessing"
    }
}

private struct OCRSpaceParsedResult: Decodable {
    let parsedText: String?

    enum CodingKeys: String, CodingKey {
        case parsedText = "ParsedText"
    }
}

private struct MultipartFormDataBuilder {
    private let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func appendField(name: String, value: String) -> MultipartFormDataBuilder {
        var copy = self
        copy.data.append("--\(boundary)\r\n")
        copy.data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        copy.data.append("\(value)\r\n")
        return copy
    }

    func appendFile(name: String, filename: String, mimeType: String, data fileData: Data) -> MultipartFormDataBuilder {
        var copy = self
        copy.data.append("--\(boundary)\r\n")
        copy.data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        copy.data.append("Content-Type: \(mimeType)\r\n\r\n")
        copy.data.append(fileData)
        copy.data.append("\r\n")
        return copy
    }

    func finish() -> Data {
        var copy = data
        copy.append("--\(boundary)--\r\n")
        return copy
    }
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

private extension Data {
    mutating func append(_ string: String) {
        append(contentsOf: Data(string.utf8))
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
