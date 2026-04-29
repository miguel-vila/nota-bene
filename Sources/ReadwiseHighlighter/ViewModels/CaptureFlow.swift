#if canImport(SwiftUI)
import Foundation
import SwiftUI

@MainActor
public final class CaptureFlow: ObservableObject {
    public enum Stage: Equatable {
        case capture
        case preview
        case extracting
        case review
        case submitting
    }

    @Published public var stage: Stage = .capture
    @Published public var book: Book
    @Published public var imageData: Data?
    @Published public var extractedText: String = ""
    @Published public var pageNumber: Int?
    @Published public var pageNumberInput: String = ""
    @Published public var lastError: String?
    @Published public var didDetectEmptyHighlight: Bool = false

    public init(book: Book) {
        self.book = book
    }

    public func setBook(_ book: Book) {
        self.book = book
    }

    public func acceptPhoto(_ data: Data) {
        imageData = data
        stage = .preview
    }

    public func retake() {
        imageData = nil
        stage = .capture
    }

    public func startExtraction() async {
        guard imageData != nil else { return }
        stage = .extracting
        lastError = nil
    }

    public func applyExtraction(_ result: ExtractionResult) {
        extractedText = result.highlightedText
        pageNumber = result.pageNumber
        pageNumberInput = result.pageNumber.map(String.init) ?? ""
        didDetectEmptyHighlight = result.highlightedText.isEmpty
        stage = .review
    }

    public func skipExtraction() {
        extractedText = ""
        pageNumber = nil
        pageNumberInput = ""
        didDetectEmptyHighlight = true
        stage = .review
    }

    public func reset(keepingBook keep: Bool = true) {
        imageData = nil
        extractedText = ""
        pageNumber = nil
        pageNumberInput = ""
        didDetectEmptyHighlight = false
        lastError = nil
        stage = .capture
        if !keep {
            // Caller should swap the book.
        }
    }

    public func parsedPageNumber() -> Int? {
        let trimmed = pageNumberInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    public var canSave: Bool {
        !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
#endif
