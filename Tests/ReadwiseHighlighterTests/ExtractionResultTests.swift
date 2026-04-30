import XCTest
@testable import ReadwiseHighlighter

final class ExtractionResultTests: XCTestCase {
    func test_decodes_arrayOfHighlights() throws {
        let json = """
        {"highlights": [
          {"text": "hello", "page_number": 42, "note": "agree!"},
          {"text": "world", "page_number": null, "note": null}
        ]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ExtractionResult.self, from: json)
        XCTAssertEqual(result.highlights.count, 2)
        XCTAssertEqual(result.highlights[0].text, "hello")
        XCTAssertEqual(result.highlights[0].pageNumber, 42)
        XCTAssertEqual(result.highlights[0].note, "agree!")
        XCTAssertEqual(result.highlights[1].text, "world")
        XCTAssertNil(result.highlights[1].pageNumber)
        XCTAssertNil(result.highlights[1].note)
    }

    func test_decodes_omitsNote() throws {
        let json = """
        {"highlights": [{"text": "hello", "page_number": 1}]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ExtractionResult.self, from: json)
        XCTAssertNil(result.highlights[0].note)
    }

    func test_decodes_emptyHighlights() throws {
        let json = """
        {"highlights": []}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ExtractionResult.self, from: json)
        XCTAssertTrue(result.highlights.isEmpty)
    }
}
