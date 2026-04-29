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
    You are extracting a highlighted passage from a photograph of a book page.

    Return only the text marked with highlighter, pen, pencil, brackets, or underline.
    Do not include any surrounding unmarked text.
    Preserve original punctuation verbatim.
    Treat line wraps as single spaces — do not include hyphenation artifacts.

    If a page number is clearly visible and unambiguous, return it as an integer.
    Otherwise return null.

    If no highlight is detected, return an empty string for highlighted_text.
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
                        "highlighted_text": ["type": "string"],
                        "page_number": ["type": "integer", "nullable": true]
                    ],
                    "required": ["highlighted_text"]
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
            let highlighted = (json["highlighted_text"] as? String) ?? ""
            let page = json["page_number"] as? Int
            return ExtractionResult(highlightedText: highlighted, pageNumber: page)
        }
        throw GeminiError.decoding("payload not valid JSON")
    }
}
