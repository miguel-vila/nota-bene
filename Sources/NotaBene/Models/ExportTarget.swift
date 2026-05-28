import Foundation

public enum ExportTarget: String, CaseIterable, Codable, Identifiable, Sendable {
    case readwise
    case notion

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .readwise: return "Readwise"
        case .notion: return "Notion"
        }
    }

    public var shortDescription: String {
        switch self {
        case .readwise: return "Send highlights to your Readwise account."
        case .notion: return "Append highlights to a page in your Notion workspace."
        }
    }
}
