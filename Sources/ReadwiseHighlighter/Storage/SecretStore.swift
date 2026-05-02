import Foundation

public protocol SecretStore: AnyObject, Sendable {
    func read(_ key: String) throws -> String?
    func write(_ value: String, for key: String) throws
    func delete(_ key: String) throws
}

public enum SecretKey {
    public static let gemini = "readwise_highlighter.gemini_key"
    public static let claude = "readwise_highlighter.claude_key"
    public static let readwise = "readwise_highlighter.readwise_key"
}

public enum PreferenceKey {
    public static let geminiModel = "readwise_highlighter.gemini_model"
    public static let claudeModel = "readwise_highlighter.claude_model"
    public static let provider = "readwise_highlighter.provider"
    public static let debugMode = "readwise_highlighter.debug_mode"
    public static let experimentalMergeHighlights = "readwise_highlighter.experimental_merge_highlights"
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
