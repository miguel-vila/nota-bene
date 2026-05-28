import Foundation

public enum NotionError: Error, Equatable {
    case invalidToken
    case requestFailed(status: Int, body: String)
    case decoding(reason: String, payload: String)
}

public actor NotionClient {
    public struct HighlightInput: Sendable, Equatable {
        public let text: String
        public let pageNumber: Int?
        public let note: String?

        public init(text: String, pageNumber: Int?, note: String?) {
            self.text = text
            self.pageNumber = pageNumber
            self.note = note
        }
    }

    public struct PageReference: Sendable, Hashable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public static let apiVersion = "2022-06-28"

    private let token: String
    private let http: HTTPClient
    private let baseURL: URL

    public init(
        token: String,
        http: HTTPClient = URLSession.shared,
        baseURL: URL = URL(string: "https://api.notion.com")!
    ) {
        self.token = token
        self.http = http
        self.baseURL = baseURL
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    // MARK: Auth

    public func validateToken() async throws -> Bool {
        let url = baseURL.appendingPathComponent("/v1/users/me")
        var request = URLRequest(url: url)
        authorize(&request)
        let (_, response) = try await http.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else { return false }
        if 200..<300 ~= httpResp.statusCode { return true }
        if httpResp.statusCode == 401 { return false }
        throw NotionError.requestFailed(status: httpResp.statusCode, body: "")
    }

    // MARK: Search pages (parent-page picker)

    public func searchTopLevelPages() async throws -> [PageReference] {
        let url = baseURL.appendingPathComponent("/v1/search")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        authorize(&request)
        request.httpBody = try Self.makeSearchBody()
        let (data, response) = try await http.data(for: request)
        try Self.validate(response: response, body: data)
        return try Self.decodeSearchResults(from: data)
    }

    // MARK: Find or create book page

    public func findOrCreateBookPage(parentPageID: String, book: Book) async throws -> String {
        let title = Self.bookPageTitle(book: book)
        if let existing = try await findChildPage(parentPageID: parentPageID, title: title) {
            return existing
        }
        return try await createBookPage(parentPageID: parentPageID, book: book)
    }

    public func findChildPage(parentPageID: String, title: String) async throws -> String? {
        var startCursor: String?
        repeat {
            let url = try Self.childrenURL(
                baseURL: baseURL,
                parentPageID: parentPageID,
                startCursor: startCursor
            )
            var request = URLRequest(url: url)
            authorize(&request)
            let (data, response) = try await http.data(for: request)
            try Self.validate(response: response, body: data)
            let (matchID, next) = try Self.findChildPageInBlocks(data: data, title: title)
            if let matchID { return matchID }
            startCursor = next
        } while startCursor != nil
        return nil
    }

    public func createBookPage(parentPageID: String, book: Book) async throws -> String {
        let url = baseURL.appendingPathComponent("/v1/pages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        authorize(&request)
        request.httpBody = try Self.makeCreatePageBody(parentPageID: parentPageID, book: book)
        let (data, response) = try await http.data(for: request)
        try Self.validate(response: response, body: data)
        return try Self.decodePageID(from: data)
    }

    // MARK: Append highlights

    public func appendHighlights(pageID: String, highlights: [HighlightInput]) async throws {
        guard !highlights.isEmpty else { return }
        let url = baseURL.appendingPathComponent("/v1/blocks/\(pageID)/children")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 30
        authorize(&request)
        request.httpBody = try Self.makeAppendBody(highlights)
        let (data, response) = try await http.data(for: request)
        try Self.validate(response: response, body: data)
    }

    // MARK: Static body builders / parsers (pure, testable)

    static func bookPageTitle(book: Book) -> String {
        if let author = book.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            return "\(book.title) — \(author)"
        }
        return book.title
    }

    static func childrenURL(baseURL: URL, parentPageID: String, startCursor: String?) throws -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/v1/blocks/\(parentPageID)/children"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = [URLQueryItem(name: "page_size", value: "100")]
        if let startCursor {
            items.append(URLQueryItem(name: "start_cursor", value: startCursor))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw NotionError.requestFailed(status: -1, body: "Could not build children URL")
        }
        return url
    }

    static func makeSearchBody() throws -> Data {
        let body: [String: Any] = [
            "filter": ["value": "page", "property": "object"],
            "sort": ["direction": "descending", "timestamp": "last_edited_time"],
            "page_size": 50
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func makeCreatePageBody(parentPageID: String, book: Book) throws -> Data {
        let body: [String: Any] = [
            "parent": ["page_id": parentPageID],
            "properties": [
                "title": [
                    "title": [["text": ["content": bookPageTitle(book: book)]]]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func makeAppendBody(_ highlights: [HighlightInput]) throws -> Data {
        var children: [[String: Any]] = []
        for h in highlights {
            children.append([
                "object": "block",
                "type": "quote",
                "quote": [
                    "rich_text": [["type": "text", "text": ["content": h.text]]]
                ]
            ])
            if let meta = metadataLine(for: h) {
                children.append([
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [[
                            "type": "text",
                            "text": ["content": meta],
                            "annotations": ["color": "gray"]
                        ]]
                    ]
                ])
            }
        }
        return try JSONSerialization.data(withJSONObject: ["children": children])
    }

    static func metadataLine(for h: HighlightInput) -> String? {
        var parts: [String] = []
        if let page = h.pageNumber { parts.append("P. \(page)") }
        if let note = h.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            parts.append("Note: \(note)")
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " — ")
    }

    static func validate(response: URLResponse, body: Data) throws {
        guard let httpResp = response as? HTTPURLResponse else {
            throw NotionError.requestFailed(status: -1, body: "")
        }
        if 200..<300 ~= httpResp.statusCode { return }
        if httpResp.statusCode == 401 { throw NotionError.invalidToken }
        throw NotionError.requestFailed(
            status: httpResp.statusCode,
            body: String(data: body, encoding: .utf8) ?? ""
        )
    }

    static func decodeSearchResults(from data: Data) throws -> [PageReference] {
        struct Property: Decodable {
            let type: String?
            let title: [TitleNode]?
        }
        struct TitleNode: Decodable {
            let plain_text: String?
        }
        struct Page: Decodable {
            let id: String
            let object: String
            let archived: Bool?
            let properties: [String: Property]?
        }
        struct ResultsPage: Decodable {
            let results: [Page]
        }
        let payload: ResultsPage
        do {
            payload = try JSONDecoder().decode(ResultsPage.self, from: data)
        } catch {
            throw NotionError.decoding(
                reason: error.localizedDescription,
                payload: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return payload.results.compactMap { page in
            guard page.object == "page", page.archived != true else { return nil }
            let title = page.properties?.values
                .first(where: { $0.type == "title" })?
                .title?
                .compactMap { $0.plain_text }
                .joined() ?? "Untitled"
            return PageReference(id: page.id, title: title.isEmpty ? "Untitled" : title)
        }
    }

    static func decodePageID(from data: Data) throws -> String {
        struct PageResp: Decodable { let id: String }
        do {
            return try JSONDecoder().decode(PageResp.self, from: data).id
        } catch {
            throw NotionError.decoding(
                reason: error.localizedDescription,
                payload: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    static func findChildPageInBlocks(
        data: Data,
        title: String
    ) throws -> (id: String?, nextCursor: String?) {
        struct Block: Decodable {
            let id: String
            let type: String
            let child_page: ChildPage?
        }
        struct ChildPage: Decodable {
            let title: String
        }
        struct Page: Decodable {
            let results: [Block]
            let next_cursor: String?
            let has_more: Bool?
        }
        let payload: Page
        do {
            payload = try JSONDecoder().decode(Page.self, from: data)
        } catch {
            throw NotionError.decoding(
                reason: error.localizedDescription,
                payload: String(data: data, encoding: .utf8) ?? ""
            )
        }
        let match = payload.results.first { $0.type == "child_page" && $0.child_page?.title == title }
        let next = (payload.has_more ?? false) ? payload.next_cursor : nil
        return (match?.id, next)
    }
}
