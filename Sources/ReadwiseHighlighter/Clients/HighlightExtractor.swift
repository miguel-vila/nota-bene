import Foundation

public protocol HighlightExtractor: Sendable {
    func extractHighlights(
        fromImages images: [Data],
        mimeType: String
    ) async throws -> ExtractionResult
}
