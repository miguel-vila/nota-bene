import XCTest
@testable import NotaBene

final class NotionClientTests: XCTestCase {
    // MARK: Body builders

    func test_makeAppendBody_emitsQuoteBlocksWithMetadataParagraph() throws {
        let highlights = [
            NotionClient.HighlightInput(text: "first quote", pageNumber: 42, note: "key idea"),
            NotionClient.HighlightInput(text: "bare quote", pageNumber: nil, note: nil)
        ]
        let data = try NotionClient.makeAppendBody(highlights)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let children = try XCTUnwrap(json["children"] as? [[String: Any]])
        // 2 blocks for the first (quote + metadata), 1 for the second (quote only).
        XCTAssertEqual(children.count, 3)

        let firstQuote = children[0]
        XCTAssertEqual(firstQuote["type"] as? String, "quote")
        let firstRichText = try XCTUnwrap(
            ((firstQuote["quote"] as? [String: Any])?["rich_text"]) as? [[String: Any]]
        )
        XCTAssertEqual((firstRichText.first?["text"] as? [String: Any])?["content"] as? String, "first quote")

        let metadata = children[1]
        XCTAssertEqual(metadata["type"] as? String, "paragraph")
        let metaRichText = try XCTUnwrap(
            ((metadata["paragraph"] as? [String: Any])?["rich_text"]) as? [[String: Any]]
        )
        let metaContent = (metaRichText.first?["text"] as? [String: Any])?["content"] as? String
        XCTAssertEqual(metaContent, "P. 42 — Note: key idea")

        let secondQuote = children[2]
        XCTAssertEqual(secondQuote["type"] as? String, "quote")
    }

    func test_metadataLine_variants() {
        let pageOnly = NotionClient.HighlightInput(text: "_", pageNumber: 12, note: nil)
        XCTAssertEqual(NotionClient.metadataLine(for: pageOnly), "P. 12")

        let noteOnly = NotionClient.HighlightInput(text: "_", pageNumber: nil, note: "see ch.4")
        XCTAssertEqual(NotionClient.metadataLine(for: noteOnly), "Note: see ch.4")

        let both = NotionClient.HighlightInput(text: "_", pageNumber: 7, note: "ref")
        XCTAssertEqual(NotionClient.metadataLine(for: both), "P. 7 — Note: ref")

        let neither = NotionClient.HighlightInput(text: "_", pageNumber: nil, note: nil)
        XCTAssertNil(NotionClient.metadataLine(for: neither))

        let blankNote = NotionClient.HighlightInput(text: "_", pageNumber: nil, note: "   ")
        XCTAssertNil(NotionClient.metadataLine(for: blankNote))
    }

    func test_bookPageTitle_includesAuthorWhenPresent() {
        let withAuthor = Book(id: "1", title: "Dune", author: "Herbert", source: .manual)
        XCTAssertEqual(NotionClient.bookPageTitle(book: withAuthor), "Dune — Herbert")

        let noAuthor = Book(id: "2", title: "Solo", author: nil, source: .manual)
        XCTAssertEqual(NotionClient.bookPageTitle(book: noAuthor), "Solo")

        let blankAuthor = Book(id: "3", title: "Quiet", author: "   ", source: .manual)
        XCTAssertEqual(NotionClient.bookPageTitle(book: blankAuthor), "Quiet")
    }

    func test_makeCreatePageBody_setsParentAndTitle() throws {
        let book = Book(id: "1", title: "Dune", author: "Herbert", source: .manual)
        let data = try NotionClient.makeCreatePageBody(parentPageID: "parent-1", book: book)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["parent"] as? [String: Any])?["page_id"] as? String, "parent-1")
        let titleProp = try XCTUnwrap(((json["properties"] as? [String: Any])?["title"]) as? [String: Any])
        let titleArr = try XCTUnwrap(titleProp["title"] as? [[String: Any]])
        let content = (titleArr.first?["text"] as? [String: Any])?["content"] as? String
        XCTAssertEqual(content, "Dune — Herbert")
    }

    func test_childrenURL_includesPaginationCursorWhenSet() throws {
        let base = URL(string: "https://example.com")!
        let first = try NotionClient.childrenURL(baseURL: base, parentPageID: "p1", startCursor: nil)
        XCTAssertTrue(first.absoluteString.contains("/v1/blocks/p1/children"))
        XCTAssertTrue(first.absoluteString.contains("page_size=100"))
        XCTAssertFalse(first.absoluteString.contains("start_cursor"))

        let second = try NotionClient.childrenURL(baseURL: base, parentPageID: "p1", startCursor: "abc")
        XCTAssertTrue(second.absoluteString.contains("start_cursor=abc"))
    }

    // MARK: Validation

    func test_validate_passesOn2xx() throws {
        let resp = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        XCTAssertNoThrow(try NotionClient.validate(response: resp, body: Data()))
    }

    func test_validate_mapsUnauthorizedToInvalidToken() {
        let resp = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!
        XCTAssertThrowsError(try NotionClient.validate(response: resp, body: Data())) { error in
            XCTAssertEqual(error as? NotionError, .invalidToken)
        }
    }

    func test_validate_mapsOtherStatusToRequestFailed() {
        let resp = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 503,
            httpVersion: nil,
            headerFields: nil
        )!
        let body = Data("server boom".utf8)
        XCTAssertThrowsError(try NotionClient.validate(response: resp, body: body)) { error in
            guard case let NotionError.requestFailed(status, payload) = error else {
                XCTFail("Wrong error: \(error)")
                return
            }
            XCTAssertEqual(status, 503)
            XCTAssertEqual(payload, "server boom")
        }
    }

    // MARK: Decoding

    func test_decodeSearchResults_extractsTitlesAndIDs() throws {
        let payload = """
        {
          "results": [
            {
              "id": "page-a",
              "object": "page",
              "archived": false,
              "properties": {
                "title": { "type": "title", "title": [{"plain_text": "Library"}] }
              }
            },
            {
              "id": "page-b",
              "object": "page",
              "archived": true,
              "properties": { "title": { "type": "title", "title": [{"plain_text": "Old"}] } }
            },
            {
              "id": "block-c",
              "object": "block",
              "properties": null
            }
          ]
        }
        """.data(using: .utf8)!
        let pages = try NotionClient.decodeSearchResults(from: payload)
        XCTAssertEqual(pages.map(\.id), ["page-a"])
        XCTAssertEqual(pages.map(\.title), ["Library"])
    }

    func test_decodePageID_returnsIdField() throws {
        let payload = #"{"id": "page-xyz", "object": "page"}"#.data(using: .utf8)!
        let id = try NotionClient.decodePageID(from: payload)
        XCTAssertEqual(id, "page-xyz")
    }

    func test_findChildPageInBlocks_returnsMatchingID() throws {
        let payload = """
        {
          "results": [
            {"id": "x1", "type": "paragraph"},
            {"id": "x2", "type": "child_page", "child_page": {"title": "Other"}},
            {"id": "x3", "type": "child_page", "child_page": {"title": "Dune — Herbert"}}
          ],
          "has_more": false,
          "next_cursor": null
        }
        """.data(using: .utf8)!
        let (id, next) = try NotionClient.findChildPageInBlocks(data: payload, title: "Dune — Herbert")
        XCTAssertEqual(id, "x3")
        XCTAssertNil(next)
    }

    func test_findChildPageInBlocks_returnsNextCursorWhenNoMatchAndHasMore() throws {
        let payload = """
        {
          "results": [
            {"id": "x1", "type": "child_page", "child_page": {"title": "Other"}}
          ],
          "has_more": true,
          "next_cursor": "cursor-42"
        }
        """.data(using: .utf8)!
        let (id, next) = try NotionClient.findChildPageInBlocks(data: payload, title: "Wanted")
        XCTAssertNil(id)
        XCTAssertEqual(next, "cursor-42")
    }

    // MARK: End-to-end with MockHTTPClient

    func test_validateToken_returnsTrueOn200() async throws {
        let mock = MockHTTPClient { _ in MockHTTPClient.ok(Data()) }
        let client = NotionClient(token: "tok", http: mock, baseURL: URL(string: "https://example.com")!)
        let ok = try await client.validateToken()
        XCTAssertTrue(ok)
    }

    func test_validateToken_returnsFalseOn401() async throws {
        let mock = MockHTTPClient { _ in MockHTTPClient.status(401) }
        let client = NotionClient(token: "tok", http: mock, baseURL: URL(string: "https://example.com")!)
        let ok = try await client.validateToken()
        XCTAssertFalse(ok)
    }

    func test_findOrCreateBookPage_returnsExistingWhenChildMatches() async throws {
        let book = Book(id: "1", title: "Dune", author: "Herbert", source: .manual)
        let expectedTitle = NotionClient.bookPageTitle(book: book)
        let childrenResponse = """
        {
          "results": [
            {"id": "found-page", "type": "child_page", "child_page": {"title": "\(expectedTitle)"}}
          ],
          "has_more": false,
          "next_cursor": null
        }
        """.data(using: .utf8)!

        let mock = MockHTTPClient { req in
            // Only GET children should be hit; POST /v1/pages should NOT.
            XCTAssertEqual(req.httpMethod ?? "GET", "GET")
            XCTAssertTrue(req.url?.absoluteString.contains("/blocks/parent-1/children") == true)
            return MockHTTPClient.ok(childrenResponse)
        }
        let client = NotionClient(token: "tok", http: mock, baseURL: URL(string: "https://example.com")!)
        let id = try await client.findOrCreateBookPage(parentPageID: "parent-1", book: book)
        XCTAssertEqual(id, "found-page")
        XCTAssertEqual(mock.requests.count, 1)
    }

    func test_findOrCreateBookPage_createsPageWhenNoMatch() async throws {
        let book = Book(id: "1", title: "Solo", author: nil, source: .manual)
        let empty = #"{"results": [], "has_more": false}"#.data(using: .utf8)!
        let createResp = #"{"id": "new-page"}"#.data(using: .utf8)!

        let mock = MockHTTPClient { req in
            if req.httpMethod == "POST", req.url?.path == "/v1/pages" {
                return MockHTTPClient.ok(createResp)
            }
            return MockHTTPClient.ok(empty)
        }
        let client = NotionClient(token: "tok", http: mock, baseURL: URL(string: "https://example.com")!)
        let id = try await client.findOrCreateBookPage(parentPageID: "parent-1", book: book)
        XCTAssertEqual(id, "new-page")
    }

    func test_findChildPage_paginatesUntilMatchFound() async throws {
        let book = Book(id: "1", title: "Wanted", author: nil, source: .manual)
        let title = NotionClient.bookPageTitle(book: book)
        let firstPage = """
        {
          "results": [{"id": "other", "type": "child_page", "child_page": {"title": "Else"}}],
          "has_more": true,
          "next_cursor": "cur-1"
        }
        """.data(using: .utf8)!
        let secondPage = """
        {
          "results": [{"id": "match-id", "type": "child_page", "child_page": {"title": "\(title)"}}],
          "has_more": false
        }
        """.data(using: .utf8)!

        var calls = 0
        let mock = MockHTTPClient { _ in
            calls += 1
            return calls == 1 ? MockHTTPClient.ok(firstPage) : MockHTTPClient.ok(secondPage)
        }
        let client = NotionClient(token: "tok", http: mock, baseURL: URL(string: "https://example.com")!)
        let id = try await client.findChildPage(parentPageID: "p1", title: title)
        XCTAssertEqual(id, "match-id")
        XCTAssertEqual(mock.requests.count, 2)
    }

    func test_appendHighlights_sendsPatchWithChildrenBody() async throws {
        let mock = MockHTTPClient { _ in MockHTTPClient.ok(Data()) }
        let client = NotionClient(token: "tok", http: mock, baseURL: URL(string: "https://example.com")!)
        try await client.appendHighlights(pageID: "p1", highlights: [
            NotionClient.HighlightInput(text: "hi", pageNumber: 1, note: nil)
        ])
        XCTAssertEqual(mock.requests.count, 1)
        let req = mock.requests[0]
        XCTAssertEqual(req.httpMethod, "PATCH")
        XCTAssertTrue(req.url?.absoluteString.contains("/v1/blocks/p1/children") == true)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Notion-Version"), NotionClient.apiVersion)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_appendHighlights_emptyArrayIsNoop() async throws {
        let mock = MockHTTPClient { _ in MockHTTPClient.ok(Data()) }
        let client = NotionClient(token: "tok", http: mock, baseURL: URL(string: "https://example.com")!)
        try await client.appendHighlights(pageID: "p1", highlights: [])
        XCTAssertEqual(mock.requests.count, 0)
    }
}
