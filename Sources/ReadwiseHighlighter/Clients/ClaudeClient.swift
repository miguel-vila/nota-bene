import Foundation

public actor ClaudeClient: HighlightExtractor {
    public static let defaultModel = "claude-sonnet-4-6"
    public static let apiVersion = "2023-06-01"
    public static let maxTokens = 4096
    public static let toolName = "report_highlights"

    public enum ModelPreset: String, CaseIterable, Identifiable, Sendable {
        case sonnet = "claude-sonnet-4-6"
        case opus = "claude-opus-4-7"
        case haiku = "claude-haiku-4-5"

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .sonnet: return "Sonnet 4.6 — recommended default"
            case .opus: return "Opus 4.7 — most accurate, slower and pricier"
            case .haiku: return "Haiku 4.5 — fastest, cheapest"
            }
        }
    }

    private let apiKey: String
    private let model: String
    private let http: HTTPClient
    private let baseURL: URL

    public init(
        apiKey: String,
        model: String = ClaudeClient.defaultModel,
        http: HTTPClient = URLSession.shared,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.http = http
        self.baseURL = baseURL
    }

    public func extractHighlights(
        fromImages images: [Data],
        mimeType: String = "image/jpeg"
    ) async throws -> ExtractionResult {
        guard !images.isEmpty else {
            return ExtractionResult(highlights: [])
        }
        let prompt = ExtractionPrompts.defaultPrompt(forPageCount: images.count)
        let url = baseURL.appendingPathComponent("messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try Self.makeBody(
            model: model,
            images: images,
            mimeType: mimeType,
            systemPrompt: prompt
        )

        let (data, response) = try await http.data(for: request)
        guard let resp = response as? HTTPURLResponse else {
            throw ExtractionError.requestFailed(status: -1, body: "no response")
        }
        if resp.statusCode == 401 || resp.statusCode == 403 {
            throw ExtractionError.invalidKey
        }
        guard 200..<300 ~= resp.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ExtractionError.requestFailed(status: resp.statusCode, body: body)
        }
        return try Self.parseResponse(data)
    }

    public static func makeBody(
        model: String,
        images: [Data],
        mimeType: String,
        systemPrompt: String
    ) throws -> Data {
        var content: [[String: Any]] = images.map { data in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mimeType,
                    "data": data.base64EncodedString()
                ]
            ]
        }
        content.append([
            "type": "text",
            "text": """
            Extract the highlighted passages from the attached page(s) and report them via the \(toolName) tool.

            Pass the highlights field as a real JSON array of objects in the tool input — do not encode the array as a JSON string. Each text value may itself contain double quotes; include them as ordinary characters inside the string (the JSON serializer will escape them). Do not pre-escape, double-escape, or wrap the array in extra quotes.
            """
        ])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "tools": [[
                "name": toolName,
                "description": "Report the highlighted passages extracted from the photographed pages. The `highlights` field MUST be a JSON array of objects (not a JSON-encoded string). Quotation marks inside any `text` value should appear as ordinary characters; do not pre-escape them.",
                "input_schema": ClaudeHighlightSchema.inputSchema
            ]],
            "tool_choice": ["type": "tool", "name": toolName],
            "messages": [[
                "role": "user",
                "content": content
            ]]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    public static func parseResponse(_ data: Data) throws -> ExtractionResult {
        let preview = ExtractionError.payloadPreview(data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionError.decoding(reason: "response not valid JSON", payload: preview)
        }
        guard let blocks = json["content"] as? [[String: Any]] else {
            throw ExtractionError.missingContent(payload: preview)
        }
        guard let toolUse = blocks.first(where: {
            ($0["type"] as? String) == "tool_use" && ($0["name"] as? String) == toolName
        }) else {
            throw ExtractionError.missingContent(payload: preview)
        }
        guard let input = toolUse["input"] as? [String: Any] else {
            throw ExtractionError.decoding(reason: "tool_use payload missing input object", payload: preview)
        }
        let rawHighlights: [[String: Any]]
        if let array = input["highlights"] as? [[String: Any]] {
            rawHighlights = array
        } else if let stringified = input["highlights"] as? String {
            // Claude occasionally returns the tool input as a JSON-encoded string
            // instead of the actual array, sometimes with unescaped quotes inside
            // a highlight's text. Try strict parse first, then a schema-aware
            // structural parser, then the character-walker repair as a last
            // resort, and only fail if all three miss.
            let stringData = stringified.data(using: .utf8) ?? Data()
            if let parsed = try? JSONSerialization.jsonObject(with: stringData) as? [[String: Any]] {
                rawHighlights = parsed
            } else if let structured = ClaudeHighlightArrayParser.parse(stringified) {
                rawHighlights = structured
            } else if let repaired = JSONRepair.parseLeniently(stringified) as? [[String: Any]] {
                rawHighlights = repaired
            } else {
                throw ExtractionError.decoding(
                    reason: "highlights field is a string but not valid JSON",
                    payload: ExtractionError.payloadPreview(stringData)
                )
            }
        } else {
            throw ExtractionError.decoding(reason: "tool_use payload missing highlights array", payload: preview)
        }
        let highlights = rawHighlights.compactMap { item -> ExtractionResult.Highlight? in
            guard let text = item["text"] as? String else { return nil }
            return ExtractionResult.Highlight(
                text: text,
                pageNumber: item["page_number"] as? Int,
                note: item["note"] as? String
            )
        }
        return ExtractionResult(highlights: highlights)
    }
}
