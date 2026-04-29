import Foundation

public struct ExtractionResult: Codable, Equatable, Sendable {
    public struct Highlight: Codable, Equatable, Sendable {
        public let text: String
        public let pageNumber: Int?

        public init(text: String, pageNumber: Int?) {
            self.text = text
            self.pageNumber = pageNumber
        }

        private enum CodingKeys: String, CodingKey {
            case text
            case pageNumber = "page_number"
        }
    }

    public let highlights: [Highlight]

    public init(highlights: [Highlight]) {
        self.highlights = highlights
    }
}
