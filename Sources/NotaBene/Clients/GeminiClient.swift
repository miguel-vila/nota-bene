import Foundation

public actor GeminiClient: HighlightExtractor {
    public static let defaultModel = "gemini-2.5-flash"

    public enum ModelPreset: String, CaseIterable, Identifiable, Sendable {
        case flash = "gemini-2.5-flash"
        case pro = "gemini-2.5-pro"
        case flashLite = "gemini-2.5-flash-lite"

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .flash: return "2.5 Flash — fast, recommended default"
            case .pro: return "2.5 Pro — most accurate, slower and pricier"
            case .flashLite: return "2.5 Flash Lite — cheapest, smaller"
            }
        }
    }

    public static func defaultPrompt(forPageCount count: Int) -> String {
        ExtractionPrompts.defaultPrompt(forPageCount: count)
    }

    private let apiKey: String
    private let model: String
    private let http: HTTPClient
    private let baseURL: URL

    public init(
        apiKey: String,
        model: String = GeminiClient.defaultModel,
        http: HTTPClient = URLSession.shared,
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
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
        let resolvedPrompt = Self.defaultPrompt(forPageCount: images.count)
        let url = baseURL.appendingPathComponent("models/\(model):generateContent")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try Self.makeBody(images: images, mimeType: mimeType, prompt: resolvedPrompt)

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

    public static func makeBody(images: [Data], mimeType: String, prompt: String) throws -> Data {
        var parts: [[String: Any]] = images.map { data in
            ["inline_data": [
                "mime_type": mimeType,
                "data": data.base64EncodedString()
            ]]
        }
        parts.append(["text": prompt])

        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "object",
                    "properties": [
                        "highlights": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "text": ["type": "string"],
                                    "page_number": ["type": "integer", "nullable": true],
                                    "note": ["type": "string", "nullable": true]
                                ],
                                "required": ["text"]
                            ]
                        ]
                    ],
                    "required": ["highlights"]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    public static func parseResponse(_ data: Data) throws -> ExtractionResult {
        struct Envelope: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }

        let envelopePreview = ExtractionError.payloadPreview(data)
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw ExtractionError.decoding(reason: "envelope: \(error)", payload: envelopePreview)
        }

        guard let parts = envelope.candidates?.first?.content?.parts,
              let text = parts.compactMap(\.text).first,
              let textData = text.data(using: .utf8) else {
            throw ExtractionError.missingContent(payload: envelopePreview)
        }
        let innerPreview = ExtractionError.payloadPreview(textData)

        if let strict = try? JSONDecoder().decode(ExtractionResult.self, from: textData) {
            return strict
        }
        if let json = try? JSONSerialization.jsonObject(with: textData) as? [String: Any] {
            if let rawHighlights = json["highlights"] as? [[String: Any]] {
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
            // Backwards-compat with the old single-highlight shape, if any layer still emits it.
            if let single = json["highlighted_text"] as? String {
                return ExtractionResult(highlights: [
                    .init(text: single, pageNumber: json["page_number"] as? Int)
                ])
            }
        }
        throw ExtractionError.decoding(reason: "payload not valid JSON", payload: innerPreview)
    }
}

public typealias GeminiError = ExtractionError
