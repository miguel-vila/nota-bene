import XCTest
@testable import ReadwiseHighlighter

final class ClaudeClientTests: XCTestCase {
    func test_makeBody_singleImageHasSystemPromptAndToolForcedJSON() throws {
        let body = try ClaudeClient.makeBody(
            model: "claude-sonnet-4-6",
            images: [Data([0x01, 0x02, 0x03])],
            mimeType: "image/png",
            systemPrompt: "extract"
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "claude-sonnet-4-6")
        XCTAssertEqual(json["system"] as? String, "extract")
        XCTAssertNotNil(json["max_tokens"] as? Int)

        // tool_choice forces the tool.
        let toolChoice = try XCTUnwrap(json["tool_choice"] as? [String: Any])
        XCTAssertEqual(toolChoice["type"] as? String, "tool")
        XCTAssertEqual(toolChoice["name"] as? String, ClaudeClient.toolName)

        // Tool defines the structured output schema.
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["name"] as? String, ClaudeClient.toolName)
        let schema = try XCTUnwrap(tools[0]["input_schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let highlights = try XCTUnwrap(properties["highlights"] as? [String: Any])
        XCTAssertEqual(highlights["type"] as? String, "array")
        let items = try XCTUnwrap(highlights["items"] as? [String: Any])
        let itemProps = try XCTUnwrap(items["properties"] as? [String: Any])
        XCTAssertNotNil(itemProps["text"])
        XCTAssertNotNil(itemProps["page_number"])
        XCTAssertNotNil(itemProps["note"])

        // User content: image part(s) then text part.
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "image")
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, Data([0x01, 0x02, 0x03]).base64EncodedString())
        XCTAssertEqual(content[1]["type"] as? String, "text")
    }

    func test_makeBody_multipleImagesAreOrderedBeforeText() throws {
        let body = try ClaudeClient.makeBody(
            model: "claude-sonnet-4-6",
            images: [Data([0xAA]), Data([0xBB])],
            mimeType: "image/jpeg",
            systemPrompt: "extract"
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 3)
        let firstSource = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(firstSource["data"] as? String, Data([0xAA]).base64EncodedString())
        let secondSource = try XCTUnwrap(content[1]["source"] as? [String: Any])
        XCTAssertEqual(secondSource["data"] as? String, Data([0xBB]).base64EncodedString())
        XCTAssertEqual(content[2]["type"] as? String, "text")
    }

    func test_parseResponse_extractsToolUseHighlights() throws {
        let envelope = """
        {
          "id": "msg_01",
          "type": "message",
          "role": "assistant",
          "content": [
            {
              "type": "tool_use",
              "id": "toolu_01",
              "name": "report_highlights",
              "input": {
                "highlights": [
                  {"text": "a quote", "page_number": 7, "note": "hmm"},
                  {"text": "another", "page_number": null, "note": null}
                ]
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let result = try ClaudeClient.parseResponse(envelope)
        XCTAssertEqual(result.highlights.count, 2)
        XCTAssertEqual(result.highlights[0].text, "a quote")
        XCTAssertEqual(result.highlights[0].pageNumber, 7)
        XCTAssertEqual(result.highlights[0].note, "hmm")
        XCTAssertEqual(result.highlights[1].text, "another")
        XCTAssertNil(result.highlights[1].pageNumber)
        XCTAssertNil(result.highlights[1].note)
    }

    func test_parseResponse_emptyHighlights() throws {
        let envelope = """
        {
          "content": [
            {"type": "tool_use", "name": "report_highlights", "input": {"highlights": []}}
          ]
        }
        """.data(using: .utf8)!
        let result = try ClaudeClient.parseResponse(envelope)
        XCTAssertTrue(result.highlights.isEmpty)
    }

    func test_parseResponse_recoversWhenHighlightsIsStringifiedArray() throws {
        // Claude sometimes returns the tool `input` field with `highlights` as a
        // JSON-encoded string instead of an actual array. The parser should
        // re-decode the string so the user doesn't see a spurious failure.
        let envelope = """
        {
          "content": [
            {
              "type": "tool_use",
              "name": "report_highlights",
              "input": {
                "highlights": "[{\\"text\\":\\"a quote\\",\\"page_number\\":7,\\"note\\":null},{\\"text\\":\\"another\\",\\"page_number\\":null,\\"note\\":\\"hmm\\"}]"
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let result = try ClaudeClient.parseResponse(envelope)
        XCTAssertEqual(result.highlights.count, 2)
        XCTAssertEqual(result.highlights[0].text, "a quote")
        XCTAssertEqual(result.highlights[0].pageNumber, 7)
        XCTAssertNil(result.highlights[0].note)
        XCTAssertEqual(result.highlights[1].text, "another")
        XCTAssertNil(result.highlights[1].pageNumber)
        XCTAssertEqual(result.highlights[1].note, "hmm")
    }
    
    func test_parseResponse_incorrectQuotesHandling() throws {
        // Sometimes claude outputs invalid json containing a quote. This is invalid json
        // but we have some repair logic that should fix it
        let envelope = #"""
        {
           "model":"claude-sonnet-4-6",
           "id":"msg_01RRwqBXNmVgW4QV3GyQ5oMh",
           "type":"message",
           "role":"assistant",
           "content":[
              {
                 "type":"tool_use",
                 "id":"toolu_01CuHUrJRB51JjrRKnYfUJbZ",
                 "name":"report_highlights",
                 "input":{
                    "highlights":"[\n  {\n    \"text\": \"There is an antidote to this misuse of data. First, make the reports as simple as possible so that everyone understands them. Remember the saying \"Metrics are people, too.\"\",\n    \"page_number\": 144,\n    \"note\": null\n  },\n  {\n    \"text\": \"This is why cohort-based reports are the gold standard of learning metrics: they turn complex actions into people-based reports. Each cohort analysis says: among the people who used our product in this period, here's how many of them exhibited each of the behaviors we care about.\",\n    \"page_number\": 144,\n    \"note\": null\n  },\n  {\n    \"text\": \"Accessibility also refers to widespread access to the reports. Grockit did this especially well. Every day their system automatically generated a document containing the latest data for every single one of their split-test experiments and other leap-of-faith metrics.\",\n    \"page_number\": 145,\n    \"note\": null\n  }\n]"
                 },
                 "caller":{
                    "type":"direct"
                 }
              }
           ],
           "stop_reason":"tool_use",
           "stop_sequence":null,
           "stop_details":null,
           "usage":{
              "input_tokens":5338,
              "cache_creation_input_tokens":0,
              "cache_read_input_tokens":0,
              "cache_creation":{
                 "ephemeral_5m_input_tokens":0,
                 "ephemeral_1h_input_tokens":0
              },
              "output_tokens":268,
              "service_tier":"standard",
              "inference_geo":"global"
           }
        }
        """#.data(using: .utf8)!
        let result = try ClaudeClient.parseResponse(envelope)
        XCTAssertEqual(result.highlights.count, 3)
    }
    
    func test_parseResponse_incorrectQuotesHandling2() throws {
        let envelope = #"""
            {
               "model":"claude-sonnet-4-6",
               "id":"msg_01RRwqBXNmVgW4QV3GyQ5oMh",
               "type":"message",
               "role":"assistant",
               "content":[
                  {
                     "type":"tool_use",
                     "id":"toolu_01CuHUrJRB51JjrRKnYfUJbZ",
                     "name":"report_highlights",
                     "input":{
                        "highlights":"[{\"text\": \"the fiat currency system was responsible for four \"economic ills\": inflation, instability, undisciplined state expenditure, and economic nationalism.\", \"page_number\": 134, \"note\": null}]"
                     },
                     "caller":{
                        "type":"direct"
                     }
                  }
               ],
               "stop_reason":"tool_use",
               "stop_sequence":null,
               "stop_details":null,
               "usage":{
                  "input_tokens":5338,
                  "cache_creation_input_tokens":0,
                  "cache_read_input_tokens":0,
                  "cache_creation":{
                     "ephemeral_5m_input_tokens":0,
                     "ephemeral_1h_input_tokens":0
                  },
                  "output_tokens":268,
                  "service_tier":"standard",
                  "inference_geo":"global"
               }
            }
            """#.data(using: .utf8)!
        let result = try ClaudeClient.parseResponse(envelope)
        XCTAssertEqual(result.highlights.count, 1)
    }

    func test_parseResponse_throwsOnMissingToolUse() {
        let data = """
        {"content": [{"type": "text", "text": "hello"}]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try ClaudeClient.parseResponse(data)) { error in
            guard case ExtractionError.missingContent(let payload) = error else {
                return XCTFail("expected missingContent, got \(error)")
            }
            XCTAssertFalse(payload.isEmpty, "payload should be captured for debugging")
        }
    }

    func test_extractHighlights_invalidKey_throws() async throws {
        let mock = MockHTTPClient { _ in MockHTTPClient.status(401) }
        let client = ClaudeClient(
            apiKey: "wrong",
            http: mock,
            baseURL: URL(string: "https://example.test/v1")!
        )
        do {
            _ = try await client.extractHighlights(fromImages: [Data([0xFF])])
            XCTFail("expected throw")
        } catch ExtractionError.invalidKey {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_extractHighlights_setsAuthHeaders() async throws {
        let envelope = """
        {"content":[{"type":"tool_use","name":"report_highlights","input":{"highlights":[{"text":"x"}]}}]}
        """.data(using: .utf8)!
        let mock = MockHTTPClient { _ in MockHTTPClient.ok(envelope) }
        let client = ClaudeClient(
            apiKey: "secret-key",
            http: mock,
            baseURL: URL(string: "https://example.test/v1")!
        )
        _ = try await client.extractHighlights(fromImages: [Data([0x00])])
        let req = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "secret-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), ClaudeClient.apiVersion)
        let path = req.url?.path ?? ""
        XCTAssertTrue(path.hasSuffix("/messages"), "path was \(path)")
    }

    func test_extractHighlights_emptyImagesReturnsEmptyWithoutNetwork() async throws {
        let mock = MockHTTPClient { _ in MockHTTPClient.status(500) }
        let client = ClaudeClient(
            apiKey: "k",
            http: mock,
            baseURL: URL(string: "https://example.test/v1")!
        )
        let result = try await client.extractHighlights(fromImages: [])
        XCTAssertTrue(result.highlights.isEmpty)
        XCTAssertEqual(mock.requests.count, 0)
    }
}
