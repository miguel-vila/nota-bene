import Foundation

public enum ReadwiseError: Error, Equatable {
    case invalidToken
    case requestFailed(status: Int, body: String)
}

public actor ReadwiseClient {
    public struct HighlightInput: Sendable {
        public let text: String
        public let title: String
        public let author: String?
        public let pageNumber: Int?
        public let sourceType: String
        public let category: String

        public init(
            text: String,
            title: String,
            author: String?,
            pageNumber: Int?,
            sourceType: String = "physical_book_capture",
            category: String = "books"
        ) {
            self.text = text
            self.title = title
            self.author = author
            self.pageNumber = pageNumber
            self.sourceType = sourceType
            self.category = category
        }
    }

    private let token: String
    private let http: HTTPClient
    private let baseURL: URL

    public init(
        token: String,
        http: HTTPClient = URLSession.shared,
        baseURL: URL = URL(string: "https://readwise.io")!
    ) {
        self.token = token
        self.http = http
        self.baseURL = baseURL
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
    }

    public func validateToken() async throws -> Bool {
        let url = baseURL.appendingPathComponent("/api/v2/auth/")
        var request = URLRequest(url: url)
        authorize(&request)
        let (_, response) = try await http.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else { return false }
        if httpResp.statusCode == 204 || (200..<300 ~= httpResp.statusCode) { return true }
        if httpResp.statusCode == 401 || httpResp.statusCode == 403 { return false }
        throw ReadwiseError.requestFailed(status: httpResp.statusCode, body: "")
    }

    public func listBooks(category: String = "books") async throws -> [Book] {
        struct Page: Decodable {
            struct Result: Decodable {
                let id: Int
                let title: String?
                let author: String?
                let cover_image_url: String?
            }
            let next: String?
            let results: [Result]
        }

        var collected: [Book] = []
        var nextURL: URL? = {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("/api/v2/books/"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "category", value: category),
                URLQueryItem(name: "page_size", value: "1000")
            ]
            return components.url
        }()

        while let current = nextURL {
            var request = URLRequest(url: current)
            authorize(&request)
            let (data, response) = try await http.data(for: request)
            guard let httpResp = response as? HTTPURLResponse else {
                throw ReadwiseError.requestFailed(status: -1, body: "")
            }
            if httpResp.statusCode == 401 || httpResp.statusCode == 403 {
                throw ReadwiseError.invalidToken
            }
            guard 200..<300 ~= httpResp.statusCode else {
                throw ReadwiseError.requestFailed(
                    status: httpResp.statusCode,
                    body: String(data: data, encoding: .utf8) ?? ""
                )
            }
            let page = try JSONDecoder().decode(Page.self, from: data)
            for r in page.results {
                guard let title = r.title, !title.isEmpty else { continue }
                collected.append(Book(
                    id: "rw:\(r.id)",
                    title: title,
                    author: r.author,
                    source: .readwise,
                    coverURL: r.cover_image_url.flatMap(URL.init(string:)),
                    readwiseID: r.id
                ))
            }
            nextURL = page.next.flatMap(URL.init(string:))
        }
        return collected
    }

    public func createHighlight(_ input: HighlightInput) async throws {
        let url = baseURL.appendingPathComponent("/api/v2/highlights/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        authorize(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.makeBody(input)
        let (data, response) = try await http.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else {
            throw ReadwiseError.requestFailed(status: -1, body: "")
        }
        if httpResp.statusCode == 401 || httpResp.statusCode == 403 {
            throw ReadwiseError.invalidToken
        }
        guard 200..<300 ~= httpResp.statusCode else {
            throw ReadwiseError.requestFailed(
                status: httpResp.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    public static func makeBody(_ input: HighlightInput) throws -> Data {
        var highlight: [String: Any] = [
            "text": input.text,
            "title": input.title,
            "source_type": input.sourceType,
            "category": input.category
        ]
        if let author = input.author, !author.isEmpty {
            highlight["author"] = author
        }
        if let page = input.pageNumber {
            highlight["location"] = page
            highlight["location_type"] = "page"
        }
        return try JSONSerialization.data(withJSONObject: ["highlights": [highlight]])
    }
}
