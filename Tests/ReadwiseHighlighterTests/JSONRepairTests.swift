import XCTest
@testable import ReadwiseHighlighter

final class JSONRepairTests: XCTestCase {
    func test_escapeStrayQuotes_leavesWellFormedObjectUnchanged() {
        let source = #"{"text":"hello","page":7}"#
        XCTAssertEqual(JSONRepair.escapeStrayQuotes(in: source), source)
    }

    func test_escapeStrayQuotes_leavesWellFormedArrayUnchanged() {
        let source = #"[{"a":"b"},{"c":null,"d":42}]"#
        XCTAssertEqual(JSONRepair.escapeStrayQuotes(in: source), source)
    }

    func test_escapeStrayQuotes_preservesAlreadyEscapedQuotes() {
        let source = #"{"text":"He said \"hi\" today"}"#
        XCTAssertEqual(JSONRepair.escapeStrayQuotes(in: source), source)
    }

    func test_escapeStrayQuotes_preservesBackslashAndOtherEscapes() {
        let source = #"{"text":"line1\nline2\twith \\ backslash"}"#
        XCTAssertEqual(JSONRepair.escapeStrayQuotes(in: source), source)
    }

    func test_escapeStrayQuotes_repairsMidStringBareQuotes() {
        let source = #"{"text":"He said "hi" today"}"#
        let repaired = JSONRepair.escapeStrayQuotes(in: source)
        let parsed = try? JSONSerialization.jsonObject(with: Data(repaired.utf8)) as? [String: String]
        XCTAssertEqual(parsed?["text"], #"He said "hi" today"#)
    }

    func test_escapeStrayQuotes_repairsTrailingInnerQuoteBeforeComma() {
        // The Claude failure shape: an inner quoted phrase ends right before
        // the closing quote of the JSON string, producing `."",` at the seam.
        let source = #"{"text":"Metrics are people, too."","page":144}"#
        let repaired = JSONRepair.escapeStrayQuotes(in: source)
        let parsed = try? JSONSerialization.jsonObject(with: Data(repaired.utf8)) as? [String: Any]
        XCTAssertEqual(parsed?["text"] as? String, #"Metrics are people, too.""#)
        XCTAssertEqual(parsed?["page"] as? Int, 144)
    }

    func test_parseLeniently_recoversClaudeRealWorldPayload() {
        let stringified = #"""
        [
          {
            "text": "There is an antidote to this misuse of data. First, make the reports as simple as possible so that everyone understands them. Remember the saying "Metrics are people, too."",
            "page_number": 144,
            "note": null
          },
          {
            "text": "This is why cohort-based reports are the gold standard.",
            "page_number": 144,
            "note": null
          }
        ]
        """#
        let parsed = JSONRepair.parseLeniently(stringified) as? [[String: Any]]
        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(parsed?[0]["page_number"] as? Int, 144)
        let firstText = parsed?[0]["text"] as? String ?? ""
        XCTAssertTrue(firstText.contains(#""Metrics are people, too.""#), "got: \(firstText)")
    }

    func test_parseLeniently_returnsValueForAlreadyValidJSON() {
        let source = #"[{"text":"clean","page_number":1,"note":null}]"#
        let parsed = JSONRepair.parseLeniently(source) as? [[String: Any]]
        XCTAssertEqual(parsed?.count, 1)
        XCTAssertEqual(parsed?[0]["text"] as? String, "clean")
    }

    func test_parseLeniently_returnsNilForUnrepairableGarbage() {
        XCTAssertNil(JSONRepair.parseLeniently("this is not json at all {{{"))
    }
}
