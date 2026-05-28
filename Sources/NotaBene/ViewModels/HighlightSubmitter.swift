import Foundation

public struct HighlightDraft: Sendable, Equatable {
    public let text: String
    public let pageNumber: Int?
    public let note: String?

    public init(text: String, pageNumber: Int?, note: String?) {
        self.text = text
        self.pageNumber = pageNumber
        self.note = note
    }
}

public protocol HighlightDestination: Sendable {
    var target: ExportTarget { get }
    func submit(book: Book, highlights: [HighlightDraft]) async throws
}

public struct ReadwiseDestination: HighlightDestination {
    public let target: ExportTarget = .readwise
    private let client: ReadwiseClient

    public init(client: ReadwiseClient) {
        self.client = client
    }

    public func submit(book: Book, highlights: [HighlightDraft]) async throws {
        let inputs = highlights.map {
            ReadwiseClient.HighlightInput(
                text: $0.text,
                title: book.title,
                author: book.author,
                pageNumber: $0.pageNumber,
                note: $0.note
            )
        }
        try await client.createHighlights(inputs)
    }
}

public actor NotionBookPageCache {
    private var cache: [String: String]

    public init(initial: [String: String] = [:]) {
        self.cache = initial
    }

    public func lookup(bookID: String) -> String? { cache[bookID] }

    public func store(pageID: String, bookID: String) {
        cache[bookID] = pageID
    }

    public func snapshot() -> [String: String] { cache }
}

public struct NotionDestination: HighlightDestination {
    public let target: ExportTarget = .notion
    private let client: NotionClient
    private let parentPageID: String
    private let cache: NotionBookPageCache

    public init(
        client: NotionClient,
        parentPageID: String,
        cache: NotionBookPageCache
    ) {
        self.client = client
        self.parentPageID = parentPageID
        self.cache = cache
    }

    public func submit(book: Book, highlights: [HighlightDraft]) async throws {
        let pageID: String
        if let cached = await cache.lookup(bookID: book.id) {
            pageID = cached
        } else {
            pageID = try await client.findOrCreateBookPage(parentPageID: parentPageID, book: book)
            await cache.store(pageID: pageID, bookID: book.id)
        }
        let inputs = highlights.map {
            NotionClient.HighlightInput(
                text: $0.text,
                pageNumber: $0.pageNumber,
                note: $0.note
            )
        }
        try await client.appendHighlights(pageID: pageID, highlights: inputs)
    }
}

public struct SubmissionFailure: Sendable, Equatable {
    public let target: ExportTarget
    public let message: String

    public init(target: ExportTarget, message: String) {
        self.target = target
        self.message = message
    }
}

public struct SubmissionResult: Sendable, Equatable {
    public let succeeded: Set<ExportTarget>
    public let failures: [SubmissionFailure]

    public init(succeeded: Set<ExportTarget>, failures: [SubmissionFailure]) {
        self.succeeded = succeeded
        self.failures = failures
    }

    public var isAllSuccess: Bool { failures.isEmpty }
}

public enum HighlightSubmitter {
    public static func submit(
        book: Book,
        highlights: [HighlightDraft],
        destinations: [any HighlightDestination],
        debugIncludesBody: Bool = false
    ) async -> SubmissionResult {
        guard !destinations.isEmpty else {
            return SubmissionResult(succeeded: [], failures: [])
        }
        return await withTaskGroup(of: (ExportTarget, Result<Void, Error>).self) { group in
            for destination in destinations {
                group.addTask {
                    do {
                        try await destination.submit(book: book, highlights: highlights)
                        return (destination.target, .success(()))
                    } catch {
                        return (destination.target, .failure(error))
                    }
                }
            }
            var succeeded: Set<ExportTarget> = []
            var failures: [SubmissionFailure] = []
            for await (target, result) in group {
                switch result {
                case .success:
                    succeeded.insert(target)
                case .failure(let error):
                    failures.append(SubmissionFailure(
                        target: target,
                        message: message(for: error, target: target, includeBody: debugIncludesBody)
                    ))
                }
            }
            return SubmissionResult(succeeded: succeeded, failures: failures)
        }
    }

    static func message(for error: Error, target: ExportTarget, includeBody: Bool) -> String {
        switch error {
        case ReadwiseError.invalidToken:
            return "Readwise token rejected — update it in Settings."
        case ReadwiseError.requestFailed(let status, let body):
            let detail = includeBody && !body.isEmpty ? "\n\n\(body)" : ""
            return "Readwise returned HTTP \(status).\(detail)"
        case NotionError.invalidToken:
            return "Notion access expired — reconnect in Settings."
        case NotionError.requestFailed(let status, let body):
            let detail = includeBody && !body.isEmpty ? "\n\n\(body)" : ""
            return "Notion returned HTTP \(status).\(detail)"
        case NotionError.decoding(let reason, _):
            return "Couldn't parse Notion response: \(reason)"
        default:
            return "\(target.label) error: \(error.localizedDescription)"
        }
    }
}
