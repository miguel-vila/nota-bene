import Foundation

public protocol SecretStore: AnyObject, Sendable {
    func read(_ key: String) throws -> String?
    func write(_ value: String, for key: String) throws
    func delete(_ key: String) throws
}

public enum SecretKey {
    public static let gemini = "notabene.gemini_key"
    public static let claude = "notabene.claude_key"
    public static let readwise = "notabene.readwise_key"
    public static let notionAccessToken = "notabene.notion_access_token"
}

public enum PreferenceKey {
    public static let geminiModel = "notabene.gemini_model"
    public static let claudeModel = "notabene.claude_model"
    public static let provider = "notabene.provider"
    public static let debugMode = "notabene.debug_mode"
    public static let experimentalMergeHighlights = "notabene.experimental_merge_highlights"
    public static let enabledExportTargets = "notabene.enabled_export_targets"
    public static let notionConnection = "notabene.notion_connection"
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func read(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    public func write(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    public func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}
