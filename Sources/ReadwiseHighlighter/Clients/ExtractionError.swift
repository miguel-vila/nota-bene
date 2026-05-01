import Foundation

public enum ExtractionError: Error, Equatable {
    case invalidKey
    case requestFailed(status: Int, body: String)
    case missingContent
    case decoding(String)
}
