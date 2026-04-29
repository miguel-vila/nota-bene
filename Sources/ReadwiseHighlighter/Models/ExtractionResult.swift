import Foundation

public struct ExtractionResult: Codable, Equatable, Sendable {
    public let highlightedText: String
    public let pageNumber: Int?

    public init(highlightedText: String, pageNumber: Int?) {
        self.highlightedText = highlightedText
        self.pageNumber = pageNumber
    }

    private enum CodingKeys: String, CodingKey {
        case highlightedText = "highlighted_text"
        case pageNumber = "page_number"
    }
}
