import XCTest
@testable import ReadwiseHighlighter

final class ExtractionResultTests: XCTestCase {
    func test_decodes_snakeCaseFields() throws {
        let json = """
        {"highlighted_text": "hello", "page_number": 42}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ExtractionResult.self, from: json)
        XCTAssertEqual(result.highlightedText, "hello")
        XCTAssertEqual(result.pageNumber, 42)
    }

    func test_decodes_nullPageNumber() throws {
        let json = """
        {"highlighted_text": "hello", "page_number": null}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ExtractionResult.self, from: json)
        XCTAssertNil(result.pageNumber)
    }
}
