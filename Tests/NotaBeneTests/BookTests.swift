import XCTest
@testable import NotaBene

final class BookTests: XCTestCase {
    func test_dedupKey_isCaseAndWhitespaceInsensitive() {
        let a = Book(id: "1", title: "  The Pragmatic Programmer ", author: "Hunt", source: .readwise)
        let b = Book(id: "2", title: "the pragmatic programmer", author: "HUNT", source: .openLibrary)
        XCTAssertEqual(a.dedupKey, b.dedupKey)
    }

    func test_dedupKey_distinguishesDifferentAuthors() {
        let a = Book(id: "1", title: "Meditations", author: "Aurelius", source: .readwise)
        let b = Book(id: "2", title: "Meditations", author: "Descartes", source: .openLibrary)
        XCTAssertNotEqual(a.dedupKey, b.dedupKey)
    }

    func test_sourceLabel() {
        XCTAssertEqual(Book(id: "1", title: "x", author: nil, source: .readwise).sourceLabel,
                       "In your library")
        XCTAssertEqual(Book(id: "2", title: "x", author: nil, source: .openLibrary).sourceLabel,
                       "New book")
        XCTAssertEqual(Book(id: "3", title: "x", author: nil, source: .manual).sourceLabel,
                       "New book")
    }
}
