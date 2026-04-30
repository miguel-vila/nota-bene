import Foundation

public struct ExtractionResult: Codable, Equatable, Sendable {
    public struct Highlight: Codable, Equatable, Sendable {
        public let text: String
        public let pageNumber: Int?
        public let note: String?

        public init(text: String, pageNumber: Int?, note: String? = nil) {
            self.text = text
            self.pageNumber = pageNumber
            self.note = note
        }

        private enum CodingKeys: String, CodingKey {
            case text
            case pageNumber = "page_number"
            case note
        }
    }

    public let highlights: [Highlight]

    public init(highlights: [Highlight]) {
        self.highlights = highlights
    }
}
