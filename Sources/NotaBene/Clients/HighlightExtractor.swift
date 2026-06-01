import Foundation

public struct ExtractionTrace: Sendable {
    public let result: ExtractionResult
    public let rawResponseBody: String
    public let latencyMillis: Int
    public let requestMime: String

    public init(
        result: ExtractionResult,
        rawResponseBody: String,
        latencyMillis: Int,
        requestMime: String
    ) {
        self.result = result
        self.rawResponseBody = rawResponseBody
        self.latencyMillis = latencyMillis
        self.requestMime = requestMime
    }
}

public protocol HighlightExtractor: Sendable {
    func extractWithTrace(
        fromImages images: [Data],
        mimeType: String
    ) async throws -> ExtractionTrace
}

public extension HighlightExtractor {
    func extractHighlights(
        fromImages images: [Data],
        mimeType: String = "image/jpeg"
    ) async throws -> ExtractionResult {
        try await extractWithTrace(fromImages: images, mimeType: mimeType).result
    }
}
