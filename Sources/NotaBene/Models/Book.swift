import Foundation

public struct Book: Codable, Identifiable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        case readwise
        case openLibrary = "open_library"
        case manual
    }

    public let id: String
    public var title: String
    public var author: String?
    public var source: Source
    public var lastUsedAt: Date?
    public var coverURL: URL?
    public var readwiseID: Int?

    public init(
        id: String,
        title: String,
        author: String?,
        source: Source,
        lastUsedAt: Date? = nil,
        coverURL: URL? = nil,
        readwiseID: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.source = source
        self.lastUsedAt = lastUsedAt
        self.coverURL = coverURL
        self.readwiseID = readwiseID
    }

    public static func openLibraryCoverURL(coverID: Int, size: String = "M") -> URL? {
        URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-\(size).jpg")
    }

    public static func dedupKey(title: String, author: String?) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let a = (author ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(t)|\(a)"
    }

    public var dedupKey: String { Self.dedupKey(title: title, author: author) }

    public var sourceLabel: String {
        switch source {
        case .readwise: return "In your library"
        case .openLibrary, .manual: return "New book"
        }
    }
}
