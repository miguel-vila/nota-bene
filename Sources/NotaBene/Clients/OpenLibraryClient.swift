import Foundation

public actor OpenLibraryClient {
    private let http: HTTPClient
    private let baseURL: URL

    public init(
        http: HTTPClient = URLSession.shared,
        baseURL: URL = URL(string: "https://openlibrary.org")!
    ) {
        self.http = http
        self.baseURL = baseURL
    }

    public func search(query: String, limit: Int = 10) async throws -> [Book] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/search.json"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "fields", value: "title,author_name,key,cover_i")
        ]
        guard let url = components.url else { return [] }
        let request = URLRequest(url: url)
        let (data, _) = try await http.data(for: request)
        return try Self.parse(data)
    }

    public static func parse(_ data: Data) throws -> [Book] {
        struct Response: Decodable {
            struct Doc: Decodable {
                let title: String?
                let author_name: [String]?
                let key: String?
                let cover_i: Int?
            }
            let docs: [Doc]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.docs.compactMap { doc in
            guard let title = doc.title, !title.isEmpty else { return nil }
            let author = doc.author_name?.first
            let id = "ol:" + (doc.key ?? UUID().uuidString)
            let coverURL = doc.cover_i.flatMap { Book.openLibraryCoverURL(coverID: $0) }
            return Book(
                id: id,
                title: title,
                author: author,
                source: .openLibrary,
                coverURL: coverURL
            )
        }
    }
}
