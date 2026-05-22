import Foundation

public enum ExtractionError: Error, Equatable {
    case invalidKey
    case requestFailed(status: Int, body: String)
    case missingContent(payload: String)
    case decoding(reason: String, payload: String)

    public static func payloadPreview(_ data: Data, limit: Int = 2000) -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            return "<non-utf8 response, \(data.count) bytes>"
        }
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "… (truncated, full size \(data.count) bytes)"
    }
}
