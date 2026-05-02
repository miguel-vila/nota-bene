#if canImport(SwiftUI)
import Foundation
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    public enum Phase: Equatable {
        case setup
        case ready
    }

    @Published public var phase: Phase = .setup
    @Published public var geminiKeyMasked: String = ""
    @Published public var claudeKeyMasked: String = ""
    @Published public var readwiseKeyMasked: String = ""
    @Published public var provider: LLMProvider {
        didSet {
            defaults.set(provider.rawValue, forKey: PreferenceKey.provider)
            refreshKeyState()
        }
    }
    @Published public var geminiModel: String {
        didSet { defaults.set(geminiModel, forKey: PreferenceKey.geminiModel) }
    }
    @Published public var claudeModel: String {
        didSet { defaults.set(claudeModel, forKey: PreferenceKey.claudeModel) }
    }
    @Published public var debugMode: Bool {
        didSet { defaults.set(debugMode, forKey: PreferenceKey.debugMode) }
    }

    public let secretStore: SecretStore
    public private(set) var bookStore: BookStore
    public let openLibrary: OpenLibraryClient
    private let defaults: UserDefaults

    public var libraryRefreshIntervalHours: Double = 12

    public init(
        secretStore: SecretStore,
        bookStore: BookStore,
        openLibrary: OpenLibraryClient = OpenLibraryClient(),
        defaults: UserDefaults = .standard
    ) {
        self.secretStore = secretStore
        self.bookStore = bookStore
        self.openLibrary = openLibrary
        self.defaults = defaults

        let storedProvider = defaults.string(forKey: PreferenceKey.provider)
            .flatMap(LLMProvider.init(rawValue:)) ?? .default
        self.provider = storedProvider

        let storedGemini = defaults.string(forKey: PreferenceKey.geminiModel)
        self.geminiModel = (storedGemini?.isEmpty == false ? storedGemini! : GeminiClient.defaultModel)

        let storedClaude = defaults.string(forKey: PreferenceKey.claudeModel)
        self.claudeModel = (storedClaude?.isEmpty == false ? storedClaude! : ClaudeClient.defaultModel)

        self.debugMode = defaults.bool(forKey: PreferenceKey.debugMode)

        refreshKeyState()
    }

    public var currentModel: String {
        switch provider {
        case .gemini: return geminiModel
        case .claude: return claudeModel
        }
    }

    public func setCurrentModel(_ model: String) {
        switch provider {
        case .gemini: geminiModel = model
        case .claude: claudeModel = model
        }
    }

    public func resetCurrentModelToDefault() {
        switch provider {
        case .gemini: geminiModel = GeminiClient.defaultModel
        case .claude: claudeModel = ClaudeClient.defaultModel
        }
    }

    public func resetGeminiModelToDefault() {
        geminiModel = GeminiClient.defaultModel
    }

    public var currentProviderKeyMasked: String {
        switch provider {
        case .gemini: return geminiKeyMasked
        case .claude: return claudeKeyMasked
        }
    }

    public func refreshKeyState() {
        let gemini = (try? secretStore.read(SecretKey.gemini)) ?? nil
        let claude = (try? secretStore.read(SecretKey.claude)) ?? nil
        let readwise = (try? secretStore.read(SecretKey.readwise)) ?? nil
        geminiKeyMasked = Self.mask(gemini)
        claudeKeyMasked = Self.mask(claude)
        readwiseKeyMasked = Self.mask(readwise)
        let providerKey: String? = {
            switch provider {
            case .gemini: return gemini
            case .claude: return claude
            }
        }()
        phase = (providerKey?.isEmpty == false && readwise?.isEmpty == false) ? .ready : .setup
    }

    public func saveGeminiKey(_ value: String) throws {
        try persist(value, for: SecretKey.gemini)
    }

    public func saveClaudeKey(_ value: String) throws {
        try persist(value, for: SecretKey.claude)
    }

    public func saveReadwiseKey(_ value: String) throws {
        try persist(value, for: SecretKey.readwise)
    }

    public func saveCurrentProviderKey(_ value: String) throws {
        switch provider {
        case .gemini: try saveGeminiKey(value)
        case .claude: try saveClaudeKey(value)
        }
    }

    public func clearGeminiKey() throws {
        try secretStore.delete(SecretKey.gemini)
        refreshKeyState()
    }

    public func clearClaudeKey() throws {
        try secretStore.delete(SecretKey.claude)
        refreshKeyState()
    }

    public func clearReadwiseKey() throws {
        try secretStore.delete(SecretKey.readwise)
        refreshKeyState()
    }

    public func currentGeminiClient() -> GeminiClient? {
        guard let key = (try? secretStore.read(SecretKey.gemini)) ?? nil, !key.isEmpty else {
            return nil
        }
        return GeminiClient(apiKey: key, model: geminiModel)
    }

    public func currentClaudeClient() -> ClaudeClient? {
        guard let key = (try? secretStore.read(SecretKey.claude)) ?? nil, !key.isEmpty else {
            return nil
        }
        return ClaudeClient(apiKey: key, model: claudeModel)
    }

    public func currentExtractor() -> HighlightExtractor? {
        switch provider {
        case .gemini: return currentGeminiClient()
        case .claude: return currentClaudeClient()
        }
    }

    public func currentReadwiseClient() -> ReadwiseClient? {
        guard let key = (try? secretStore.read(SecretKey.readwise)) ?? nil, !key.isEmpty else {
            return nil
        }
        return ReadwiseClient(token: key)
    }

    private func persist(_ value: String, for key: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try secretStore.delete(key)
        } else {
            try secretStore.write(trimmed, for: key)
        }
        refreshKeyState()
    }

    static func mask(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        if value.count <= 4 { return String(repeating: "•", count: value.count) }
        let suffix = value.suffix(4)
        return String(repeating: "•", count: max(0, value.count - 4)) + suffix
    }
}
#endif
