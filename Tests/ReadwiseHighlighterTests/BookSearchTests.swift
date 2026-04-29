import XCTest
@testable import ReadwiseHighlighter

final class BookSearchTests: XCTestCase {
    func test_merge_putsReadwiseFirstAndDedupes() {
        let rw = [
            Book(id: "rw:1", title: "Dune", author: "Herbert", source: .readwise),
            Book(id: "rw:2", title: "Project Hail Mary", author: "Weir", source: .readwise),
        ]
        let ol = [
            Book(id: "ol:1", title: "DUNE", author: "herbert", source: .openLibrary),
            Book(id: "ol:2", title: "Foundation", author: "Asimov", source: .openLibrary),
        ]
        let merged = BookSearch.merge(readwise: rw, openLibrary: ol)
        XCTAssertEqual(merged.map(\.id), ["rw:1", "rw:2", "ol:2"])
    }

    func test_filterLibrary_matchesTitleOrAuthor() {
        let books = [
            Book(id: "1", title: "Dune", author: "Frank Herbert", source: .readwise),
            Book(id: "2", title: "Foundation", author: "Isaac Asimov", source: .readwise),
            Book(id: "3", title: "Dune Messiah", author: "Frank Herbert", source: .readwise),
        ]
        XCTAssertEqual(BookSearch.filterLibrary(books, query: "asimov").map(\.id), ["2"])
        XCTAssertEqual(BookSearch.filterLibrary(books, query: "dune").map(\.id), ["1", "3"])
        XCTAssertEqual(BookSearch.filterLibrary(books, query: "").map(\.id), [])
    }
}
