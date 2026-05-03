#if canImport(SwiftUI)
import Foundation
import SwiftUI

@MainActor
public final class CaptureFlow: ObservableObject {
    public enum Stage: Equatable {
        case capture
        case preview
        case extracting
        case extractionFailed
        case review
        case submitting
        case saved
    }

    public struct EditableHighlight: Identifiable, Equatable {
        public let id: UUID
        public var text: String
        public var pageNumberInput: String
        public var note: String

        public init(
            id: UUID = UUID(),
            text: String = "",
            pageNumberInput: String = "",
            note: String = ""
        ) {
            self.id = id
            self.text = text
            self.pageNumberInput = pageNumberInput
            self.note = note
        }

        public func parsedPageNumber() -> Int? {
            let trimmed = pageNumberInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Int(trimmed)
        }

        public var trimmedText: String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var trimmedNote: String {
            note.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var noteForSubmission: String? {
            let trimmed = trimmedNote
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    public static let maxPagesPerCapture = 2

    @Published public var stage: Stage = .capture
    @Published public var book: Book
    @Published public var images: [Data] = []
    @Published public var highlights: [EditableHighlight] = []
    @Published public var lastError: String?
    @Published public var didDetectEmptyHighlight: Bool = false
    @Published public var lastSavedHighlights: [EditableHighlight] = []

    public init(book: Book) {
        self.book = book
    }

    public func setBook(_ book: Book) {
        self.book = book
    }

    public func acceptPhoto(_ data: Data) {
        guard images.count < Self.maxPagesPerCapture else { return }
        images.append(data)
        stage = .preview
    }

    public func turnPage() {
        guard canTurnPage else { return }
        stage = .capture
    }

    public func retake() {
        images = []
        stage = .capture
    }

    public func removeLastImage() {
        guard !images.isEmpty else { return }
        images.removeLast()
        if images.isEmpty {
            stage = .capture
        }
    }

    public var canTurnPage: Bool {
        images.count < Self.maxPagesPerCapture
    }

    public func startExtraction() async {
        guard !images.isEmpty else { return }
        stage = .extracting
        lastError = nil
    }

    public func failExtraction(_ message: String) {
        lastError = message
        stage = .extractionFailed
    }

    public func retryExtraction() {
        guard !images.isEmpty else { return }
        lastError = nil
        stage = .extracting
    }

    public func backToPreview() {
        guard !images.isEmpty else { return }
        lastError = nil
        stage = .preview
    }

    public func applyExtraction(_ result: ExtractionResult) {
        let mapped = result.highlights
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map {
                EditableHighlight(
                    text: $0.text,
                    pageNumberInput: $0.pageNumber.map(String.init) ?? "",
                    note: $0.note ?? ""
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

    public func mergeHighlight(at index: Int) {
        guard index > 0, index < highlights.count else { return }
        let lower = highlights.remove(at: index)
        var upper = highlights[index - 1]
        upper.text = Self.combineText(upper.text, lower.text)
        upper.pageNumberInput = upper.pageNumberInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? lower.pageNumberInput
            : upper.pageNumberInput
        upper.note = Self.combineNote(upper.note, lower.note)
        highlights[index - 1] = upper
    }

    private static func combineText(_ a: String, _ b: String) -> String {
        let trimmedA = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedB = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedA.isEmpty { return b }
        if trimmedB.isEmpty { return a }
        return trimmedA + " " + trimmedB
    }

    private static func combineNote(_ a: String, _ b: String) -> String {
        let trimmedA = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedB = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedA.isEmpty { return b }
        if trimmedB.isEmpty { return a }
        return a + "\n\n" + b
    }

    public func reset(keepingBook keep: Bool = true) {
        images = []
        highlights = []
        didDetectEmptyHighlight = false
        lastError = nil
        stage = .capture
        if !keep {
            // Caller should swap the book.
        }
    }

    public func markSaved(_ snapshot: [EditableHighlight]) {
        lastSavedHighlights = snapshot
        images = []
        highlights = []
        didDetectEmptyHighlight = false
        lastError = nil
        stage = .saved
    }

    public var savableHighlights: [EditableHighlight] {
        highlights.filter { !$0.trimmedText.isEmpty }
    }

    public var canSave: Bool {
        !savableHighlights.isEmpty
    }
}
#endif
