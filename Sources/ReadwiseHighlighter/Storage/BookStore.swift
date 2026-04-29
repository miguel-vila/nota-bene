import Foundation

public actor BookStore {
    public struct CacheState: Codable, Equatable, Sendable {
        public var library: [Book]
        public var libraryRefreshedAt: Date?
        public var recents: [Book]

        public init(
            library: [Book] = [],
            libraryRefreshedAt: Date? = nil,
            recents: [Book] = []
        ) {
            self.library = library
            self.libraryRefreshedAt = libraryRefreshedAt
            self.recents = recents
        }
    }

    public let url: URL
    private(set) public var state: CacheState

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let loaded = try? Self.decoder.decode(CacheState.self, from: data) {
            self.state = loaded
        } else {
            self.state = CacheState()
        }
    }

    public func setLibrary(_ books: [Book], at date: Date = Date()) throws {
        state.library = books
        state.libraryRefreshedAt = date
        try persist()
    }

    public func recordUsage(of book: Book, now: Date = Date(), maxRecents: Int = 10) throws {
        var updated = book
        updated.lastUsedAt = now
        var recents = state.recents.filter { $0.dedupKey != updated.dedupKey }
        recents.insert(updated, at: 0)
        if recents.count > maxRecents {
            recents = Array(recents.prefix(maxRecents))
        }
        state.recents = recents
        try persist()
    }

    public func libraryNeedsRefresh(maxAgeHours: Double, now: Date = Date()) -> Bool {
        guard let last = state.libraryRefreshedAt else { return true }
        return now.timeIntervalSince(last) > maxAgeHours * 3600
    }

    private func persist() throws {
        let data = try Self.encoder.encode(state)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func defaultURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("ReadwiseHighlighter", isDirectory: true)
            .appendingPathComponent("books.json")
    }
}
