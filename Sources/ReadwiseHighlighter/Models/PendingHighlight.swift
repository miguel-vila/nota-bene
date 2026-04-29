import Foundation

public struct PendingHighlight: Equatable, Sendable {
    public var book: Book
    public var imageData: Data?
    public var extractedText: String
    public var pageNumber: Int?

    public init(
        book: Book,
        imageData: Data? = nil,
        extractedText: String = "",
        pageNumber: Int? = nil
    ) {
        self.book = book
        self.imageData = imageData
        self.extractedText = extractedText
        self.pageNumber = pageNumber
    }
}
