import XCTest
@testable import ReadwiseHighlighter

final class GeminiClientTests: XCTestCase {
    func test_makeBody_includesInlineDataAndArraySchema() throws {
        let body = try GeminiClient.makeBody(
            imageData: Data([0x01, 0x02, 0x03]),
            mimeType: "image/png",
            prompt: "extract"
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        let inline = try XCTUnwrap(parts.first?["inline_data"] as? [String: Any])
        XCTAssertEqual(inline["mime_type"] as? String, "image/png")
        XCTAssertEqual(inline["data"] as? String, Data([0x01, 0x02, 0x03]).base64EncodedString())
        XCTAssertEqual(parts.last?["text"] as? String, "extract")

        let gen = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        XCTAssertEqual(gen["responseMimeType"] as? String, "application/json")
        let schema = try XCTUnwrap(gen["responseSchema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let highlights = try XCTUnwrap(properties["highlights"] as? [String: Any])
        XCTAssertEqual(highlights["type"] as? String, "array")
        let items = try XCTUnwrap(highlights["items"] as? [String: Any])
        let itemProps = try XCTUnwrap(items["properties"] as? [String: Any])
        XCTAssertNotNil(itemProps["text"])
        XCTAssertNotNil(itemProps["page_number"])
    }

    func test_parseResponse_extractsArray() throws {
        let envelope = """
        {
          "candidates": [{
            "content": {
              "parts": [{"text": "{\\"highlights\\": [{\\"text\\": \\"a quote\\", \\"page_number\\": 7}, {\\"text\\": \\"another\\", \\"page_number\\": null}]}"}]
            }
          }]
        }
        """.data(using: .utf8)!
        let result = try GeminiClient.parseResponse(envelope)
        XCTAssertEqual(result.highlights.count, 2)
        XCTAssertEqual(result.highlights[0].text, "a quote")
        XCTAssertEqual(result.highlights[0].pageNumber, 7)
        XCTAssertEqual(result.highlights[1].text, "another")
        XCTAssertNil(result.highlights[1].pageNumber)
    }

    func test_parseResponse_emptyHighlights() throws {
        let envelope = """
        {
          "candidates": [{
            "content": {
              "parts": [{"text": "{\\"highlights\\": []}"}]
            }
          }]
        }
        """.data(using: .utf8)!
        let result = try GeminiClient.parseResponse(envelope)
        XCTAssertTrue(result.highlights.isEmpty)
    }

    func test_parseResponse_throwsOnMissingContent() {
        let data = "{\"candidates\": []}".data(using: .utf8)!
        XCTAssertThrowsError(try GeminiClient.parseResponse(data)) { error in
            guard case GeminiError.missingContent = error else {
                return XCTFail("expected missingContent, got \(error)")
            }
        }
    }

    func test_extractHighlight_invalidKey_throws() async throws {
        let mock = MockHTTPClient { _ in
            MockHTTPClient.status(401)
        }
        let client = GeminiClient(
            apiKey: "wrong",
            http: mock,
            baseURL: URL(string: "https://example.test/v1beta")!
        )
        do {
            _ = try await client.extractHighlight(from: Data([0xFF]))
            XCTFail("expected throw")
        } catch GeminiError.invalidKey {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_extractHighlight_setsApiKeyHeader() async throws {
        let envelope = """
        {"candidates":[{"content":{"parts":[{"text":"{\\"highlights\\":[{\\"text\\":\\"x\\"}]}"}]}}]}
        """.data(using: .utf8)!
        let mock = MockHTTPClient { _ in
            MockHTTPClient.ok(envelope)
        }
        let client = GeminiClient(
            apiKey: "secret-key",
            http: mock,
            baseURL: URL(string: "https://example.test/v1beta")!
        )
        _ = try await client.extractHighlight(from: Data([0x00]))
        XCTAssertEqual(mock.requests.first?.value(forHTTPHeaderField: "x-goog-api-key"), "secret-key")
        let path = mock.requests.first?.url?.path ?? ""
        XCTAssertTrue(path.contains(":generateContent"), "path was \(path)")
    }
}
