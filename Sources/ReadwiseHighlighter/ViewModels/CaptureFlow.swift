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

    public struct EditableHighlight: Identifiable, Equatable {
        public let id: UUID
        public var text: String
        public var pageNumberInput: String

        public init(id: UUID = UUID(), text: String = "", pageNumberInput: String = "") {
            self.id = id
            self.text = text
            self.pageNumberInput = pageNumberInput
        }

        public func parsedPageNumber() -> Int? {
            let trimmed = pageNumberInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Int(trimmed)
        }

        public var trimmedText: String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @Published public var stage: Stage = .capture
    @Published public var book: Book
    @Published public var imageData: Data?
    @Published public var highlights: [EditableHighlight] = []
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
        let mapped = result.highlights.map {
            EditableHighlight(
                text: $0.text,
                pageNumberInput: $0.pageNumber.map(String.init) ?? ""
            )
        }
        if mapped.isEmpty {
            highlights = [EditableHighlight()]
            didDetectEmptyHighlight = true
        } else {
            highlights = mapped
            didDetectEmptyHighlight = false
        }
        stage = .review
    }

    public func skipExtraction() {
        highlights = [EditableHighlight()]
        didDetectEmptyHighlight = true
        stage = .review
    }

    public func addBlankHighlight() {
        highlights.append(EditableHighlight())
    }

    public func removeHighlight(id: UUID) {
        highlights.removeAll { $0.id == id }
        if highlights.isEmpty {
            highlights = [EditableHighlight()]
        }
    }

    public func reset(keepingBook keep: Bool = true) {
        imageData = nil
        highlights = []
        didDetectEmptyHighlight = false
        lastError = nil
        stage = .capture
        if !keep {
            // Caller should swap the book.
        }
    }

    public var savableHighlights: [EditableHighlight] {
        highlights.filter { !$0.trimmedText.isEmpty }
    }

    public var canSave: Bool {
        !savableHighlights.isEmpty
    }
}
#endif
