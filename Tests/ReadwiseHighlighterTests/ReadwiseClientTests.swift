import XCTest
@testable import ReadwiseHighlighter

final class ReadwiseClientTests: XCTestCase {
    func test_makeBody_includesPageLocationWhenSet() throws {
        let input = ReadwiseClient.HighlightInput(
            text: "passage",
            title: "Dune",
            author: "Herbert",
            pageNumber: 99
        )
        let data = try ReadwiseClient.makeBody(input)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let highlights = try XCTUnwrap(json["highlights"] as? [[String: Any]])
        let h = try XCTUnwrap(highlights.first)
        XCTAssertEqual(h["text"] as? String, "passage")
        XCTAssertEqual(h["title"] as? String, "Dune")
        XCTAssertEqual(h["author"] as? String, "Herbert")
        XCTAssertEqual(h["source_type"] as? String, "physical_book_capture")
        XCTAssertEqual(h["category"] as? String, "books")
        XCTAssertEqual(h["location"] as? Int, 99)
        XCTAssertEqual(h["location_type"] as? String, "page")
    }

    func test_makeBody_omitsPageWhenNil() throws {
        let input = ReadwiseClient.HighlightInput(
            text: "passage",
            title: "Dune",
            author: nil,
            pageNumber: nil
        )
        let data = try ReadwiseClient.makeBody(input)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let highlights = try XCTUnwrap(json["highlights"] as? [[String: Any]])
        let h = try XCTUnwrap(highlights.first)
        XCTAssertNil(h["location"])
        XCTAssertNil(h["location_type"])
        XCTAssertNil(h["author"])
    }

    func test_validateToken_returnsTrueOn204() async throws {
        let mock = MockHTTPClient { _ in MockHTTPClient.status(204) }
        let client = ReadwiseClient(token: "tok", http: mock,
                                     baseURL: URL(string: "https://example.test")!)
        let ok = try await client.validateToken()
        XCTAssertTrue(ok)
    }

    func test_validateToken_returnsFalseOn401() async throws {
        let mock = MockHTTPClient { _ in MockHTTPClient.status(401) }
        let client = ReadwiseClient(token: "tok", http: mock,
                                     baseURL: URL(string: "https://example.test")!)
        let ok = try await client.validateToken()
        XCTAssertFalse(ok)
    }

    func test_validateToken_setsAuthorizationHeader() async throws {
        let mock = MockHTTPClient { _ in MockHTTPClient.status(204) }
        let client = ReadwiseClient(token: "abc", http: mock,
                                     baseURL: URL(string: "https://example.test")!)
        _ = try await client.validateToken()
        XCTAssertEqual(mock.requests.first?.value(forHTTPHeaderField: "Authorization"),
                       "Token abc")
    }

    func test_listBooks_followsPagination() async throws {
        let page1 = """
        {"next": "https://example.test/api/v2/books/?page=2",
         "results":[{"id":1,"title":"A","author":"X","cover_image_url":"https://img.test/1.jpg"}]}
        """.data(using: .utf8)!
        let page2 = """
        {"next": null, "results":[{"id":2,"title":"B","author":null}]}
        """.data(using: .utf8)!

        var calls = 0
        let mock = MockHTTPClient { request in
            calls += 1
            let data: Data = (request.url?.absoluteString.contains("page=2") ?? false) ? page2 : page1
            return MockHTTPClient.ok(data)
        }
        let client = ReadwiseClient(token: "t", http: mock,
                                     baseURL: URL(string: "https://example.test")!)
        let books = try await client.listBooks()
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(books.map(\.id), ["rw:1", "rw:2"])
        XCTAssertEqual(books.first?.source, .readwise)
        XCTAssertEqual(books.first?.coverURL?.absoluteString, "https://img.test/1.jpg")
        XCTAssertNil(books.last?.coverURL)
    }

    func test_listBooks_invalidToken_throws() async {
        let mock = MockHTTPClient { _ in MockHTTPClient.status(401) }
        let client = ReadwiseClient(token: "t", http: mock,
                                     baseURL: URL(string: "https://example.test")!)
        do {
            _ = try await client.listBooks()
            XCTFail("expected throw")
        } catch ReadwiseError.invalidToken {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_createHighlight_postsToHighlightsEndpoint() async throws {
        let mock = MockHTTPClient { _ in MockHTTPClient.status(200) }
        let client = ReadwiseClient(token: "t", http: mock,
                                     baseURL: URL(string: "https://example.test")!)
        try await client.createHighlight(.init(
            text: "hi", title: "Dune", author: "Herbert", pageNumber: 1
        ))
        let request = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url?.path.hasPrefix("/api/v2/highlights") ?? false,
                      "url path was \(request.url?.path ?? "nil")")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}
