import Foundation

public struct NotionConnection: Codable, Equatable, Sendable {
    public var workspaceID: String
    public var workspaceName: String?
    public var workspaceIcon: URL?
    public var botID: String
    public var parentPageID: String?
    public var parentPageTitle: String?
    public var bookPageCache: [String: String]
    public var connectedAt: Date

    public init(
        workspaceID: String,
        workspaceName: String? = nil,
        workspaceIcon: URL? = nil,
        botID: String,
        parentPageID: String? = nil,
        parentPageTitle: String? = nil,
        bookPageCache: [String: String] = [:],
        connectedAt: Date = Date()
    ) {
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.workspaceIcon = workspaceIcon
        self.botID = botID
        self.parentPageID = parentPageID
        self.parentPageTitle = parentPageTitle
        self.bookPageCache = bookPageCache
        self.connectedAt = connectedAt
    }

    public var isFullyConfigured: Bool {
        parentPageID != nil
    }

    public func cachedPageID(forBookID id: String) -> String? {
        bookPageCache[id]
    }

    public mutating func setCachedPageID(_ pageID: String, forBookID id: String) {
        bookPageCache[id] = pageID
    }
}
