import Foundation

public enum GeminiError: Error, Equatable {
    case invalidKey
    case requestFailed(status: Int, body: String)
    case missingContent
    case decoding(String)
}

public actor GeminiClient {
    public static let defaultModel = "gemini-2.5-flash"
    public static let defaultPrompt = """
    You are extracting highlighted passages from a photograph of a book page.

    A single page may contain zero, one, or multiple distinct passages physically
    marked by the reader with highlighter, pen, pencil, brackets, or underline.
    Return every distinct passage you find as a separate entry in the highlights
    array, in the order they appear on the page (top to bottom, then left to right).

    Only return passages that show a hand-applied mark. Ignore typographic emphasis
    that is part of the printed book itself — italics, bold, small caps, drop caps,
    pull quotes, chapter epigraphs, captions, and headings are NOT highlights unless
    the reader has additionally marked them by hand. A hand-applied mark looks like
    an irregular ink/graphite stroke, a translucent highlighter overlay, a margin
    bracket, or an underline drawn by hand (often slightly crooked or extending
    beyond the text baseline). When in doubt, treat the text as unmarked.

    For each passage:
    - Include only the marked text. Do not include surrounding unmarked text.
    - Preserve original punctuation verbatim. Do not add quotation marks or emphasis
      markers (e.g. asterisks, underscores) for printed italics or bold.
    - Treat line wraps as single spaces — do not include hyphenation artifacts.
    - If a page number is clearly visible and unambiguous, return it as an integer
      in page_number. Otherwise return null. The same page_number can repeat across
      passages on the same page.

    If two marks are clearly part of the same continuous sentence or paragraph,
    treat them as a single passage. If they are separated by unmarked text or are
    on different lines/paragraphs, treat them as separate passages.

    If no highlight is detected on the page, return an empty highlights array.
    """

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

    public func extractHighlight(
        from imageData: Data,
        mimeType: String = "image/jpeg",
        prompt: String = GeminiClient.defaultPrompt
    ) async throws -> ExtractionResult {
        let url = baseURL.appendingPathComponent("models/\(model):generateContent")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try Self.makeBody(imageData: imageData, mimeType: mimeType, prompt: prompt)

        let (data, response) = try await http.data(for: request)
        guard let resp = response as? HTTPURLResponse else {
            throw GeminiError.requestFailed(status: -1, body: "no response")
        }
        if resp.statusCode == 401 || resp.statusCode == 403 {
            throw GeminiError.invalidKey
        }
        guard 200..<300 ~= resp.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.requestFailed(status: resp.statusCode, body: body)
        }
        return try Self.parseResponse(data)
    }

    public static func makeBody(imageData: Data, mimeType: String, prompt: String) throws -> Data {
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inline_data": [
                        "mime_type": mimeType,
                        "data": imageData.base64EncodedString()
                    ]],
                    ["text": prompt]
                ]
            ]],
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
                                    "page_number": ["type": "integer", "nullable": true]
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

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw GeminiError.decoding("envelope: \(error)")
        }

        guard let parts = envelope.candidates?.first?.content?.parts,
              let text = parts.compactMap(\.text).first,
              let textData = text.data(using: .utf8) else {
            throw GeminiError.missingContent
        }

        if let strict = try? JSONDecoder().decode(ExtractionResult.self, from: textData) {
            return strict
        }
        if let json = try? JSONSerialization.jsonObject(with: textData) as? [String: Any] {
            if let rawHighlights = json["highlights"] as? [[String: Any]] {
                let highlights = rawHighlights.compactMap { item -> ExtractionResult.Highlight? in
                    guard let text = item["text"] as? String else { return nil }
                    return ExtractionResult.Highlight(text: text, pageNumber: item["page_number"] as? Int)
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
        throw GeminiError.decoding("payload not valid JSON")
    }
}
