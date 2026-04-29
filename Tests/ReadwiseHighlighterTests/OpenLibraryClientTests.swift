import XCTest
@testable import ReadwiseHighlighter

final class OpenLibraryClientTests: XCTestCase {
    func test_parse_extractsDocsAndPicksFirstAuthor() throws {
        let json = """
        {"docs":[
          {"title":"Dune","author_name":["Frank Herbert","Other"],"key":"/works/OL1W","cover_i":1234},
          {"title":"Foundation","author_name":["Isaac Asimov"],"key":"/works/OL2W"},
          {"title":null}
        ]}
        """.data(using: .utf8)!
        let books = try OpenLibraryClient.parse(json)
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(books[0].title, "Dune")
        XCTAssertEqual(books[0].author, "Frank Herbert")
        XCTAssertEqual(books[0].coverURL?.absoluteString,
                       "https://covers.openlibrary.org/b/id/1234-M.jpg")
        XCTAssertEqual(books[0].source, .openLibrary)
        XCTAssertEqual(books[0].id, "ol:/works/OL1W")
        XCTAssertNil(books[1].coverURL)
    }

    func test_search_emptyQueryReturnsEmpty() async throws {
        let mock = MockHTTPClient { _ in MockHTTPClient.ok(Data("{\"docs\":[]}".utf8)) }
        let client = OpenLibraryClient(http: mock,
                                        baseURL: URL(string: "https://example.test")!)
        let books = try await client.search(query: "   ")
        XCTAssertTrue(books.isEmpty)
        XCTAssertEqual(mock.requests.count, 0)
    }

    func test_search_buildsExpectedQuery() async throws {
        let mock = MockHTTPClient { _ in
            MockHTTPClient.ok(Data("{\"docs\":[]}".utf8))
        }
        let client = OpenLibraryClient(http: mock,
                                        baseURL: URL(string: "https://example.test")!)
        _ = try await client.search(query: "dune", limit: 5)
        let url = try XCTUnwrap(mock.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues:
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["q"], "dune")
        XCTAssertEqual(items["limit"], "5")
        XCTAssertEqual(items["fields"], "title,author_name,key,cover_i")
        XCTAssertEqual(components.path, "/search.json")
    }
}
