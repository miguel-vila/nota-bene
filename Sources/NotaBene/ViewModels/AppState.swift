#if canImport(SwiftUI)
import Foundation
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    public enum Phase: Equatable {
        case setup
        case ready
    }

    public enum TargetMutationError: Error, Equatable {
        case lastConfiguredTargetCannotBeDisabled
    }

    @Published public var phase: Phase = .setup
    @Published public var geminiKeyMasked: String = ""
    @Published public var claudeKeyMasked: String = ""
    @Published public var readwiseKeyMasked: String = ""
    @Published public var notionAccessTokenMasked: String = ""
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
    @Published public var experimentalMergeHighlights: Bool {
        didSet { defaults.set(experimentalMergeHighlights, forKey: PreferenceKey.experimentalMergeHighlights) }
    }
    @Published public private(set) var enabledTargets: Set<ExportTarget> {
        didSet {
            let raws = enabledTargets.map(\.rawValue).sorted()
            defaults.set(raws, forKey: PreferenceKey.enabledExportTargets)
            refreshKeyState()
        }
    }
    @Published public var notionConnection: NotionConnection? {
        didSet {
            if let connection = notionConnection,
               let data = try? JSONEncoder().encode(connection) {
                defaults.set(data, forKey: PreferenceKey.notionConnection)
            } else {
                defaults.removeObject(forKey: PreferenceKey.notionConnection)
            }
            refreshKeyState()
        }
    }

    public let secretStore: SecretStore
    public private(set) var bookStore: BookStore
    public let openLibrary: OpenLibraryClient
    public let notionOAuthConfig: NotionOAuthConfig?
    private let defaults: UserDefaults

    public var libraryRefreshIntervalHours: Double = 12

    public init(
        secretStore: SecretStore,
        bookStore: BookStore,
        openLibrary: OpenLibraryClient = OpenLibraryClient(),
        notionOAuthConfig: NotionOAuthConfig? = NotionOAuthConfig.fromMainBundle(),
        defaults: UserDefaults = .standard
    ) {
        self.secretStore = secretStore
        self.bookStore = bookStore
        self.openLibrary = openLibrary
        self.notionOAuthConfig = notionOAuthConfig
        self.defaults = defaults

        let storedProvider = defaults.string(forKey: PreferenceKey.provider)
            .flatMap(LLMProvider.init(rawValue:)) ?? .default
        self.provider = storedProvider

        let storedGemini = defaults.string(forKey: PreferenceKey.geminiModel)
        self.geminiModel = (storedGemini?.isEmpty == false ? storedGemini! : GeminiClient.defaultModel)

        let storedClaude = defaults.string(forKey: PreferenceKey.claudeModel)
        self.claudeModel = (storedClaude?.isEmpty == false ? storedClaude! : ClaudeClient.defaultModel)

        self.debugMode = defaults.bool(forKey: PreferenceKey.debugMode)
        self.experimentalMergeHighlights = defaults.bool(forKey: PreferenceKey.experimentalMergeHighlights)

        let storedTargetRawsOptional = defaults.stringArray(forKey: PreferenceKey.enabledExportTargets)
        if let storedTargetRaws = storedTargetRawsOptional {
            self.enabledTargets = Set(storedTargetRaws.compactMap(ExportTarget.init(rawValue:)))
        } else if let existingReadwise = (try? secretStore.read(SecretKey.readwise)) ?? nil,
                  !existingReadwise.isEmpty {
            self.enabledTargets = [.readwise]
            defaults.set([ExportTarget.readwise.rawValue], forKey: PreferenceKey.enabledExportTargets)
        } else {
            self.enabledTargets = []
        }

        if let data = defaults.data(forKey: PreferenceKey.notionConnection),
           let conn = try? JSONDecoder().decode(NotionConnection.self, from: data) {
            self.notionConnection = conn
        } else {
            self.notionConnection = nil
        }

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
        let notionToken = (try? secretStore.read(SecretKey.notionAccessToken)) ?? nil
        geminiKeyMasked = Self.mask(gemini)
        claudeKeyMasked = Self.mask(claude)
        readwiseKeyMasked = Self.mask(readwise)
        notionAccessTokenMasked = Self.mask(notionToken)

        let providerKey: String? = {
            switch provider {
            case .gemini: return gemini
            case .claude: return claude
            }
        }()
        let providerReady = (providerKey?.isEmpty == false)

        let configured = configuredTargets(readwise: readwise, notionToken: notionToken)
        let hasActiveTarget = !enabledTargets.intersection(configured).isEmpty

        phase = (providerReady && hasActiveTarget) ? .ready : .setup
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

    // MARK: Export targets

    public func enableTarget(_ target: ExportTarget) {
        var updated = enabledTargets
        updated.insert(target)
        enabledTargets = updated
    }

    public func disableTarget(_ target: ExportTarget) throws {
        let currentActive = enabledTargets.intersection(configuredTargets())
        if currentActive == [target] {
            throw TargetMutationError.lastConfiguredTargetCannotBeDisabled
        }
        var updated = enabledTargets
        updated.remove(target)
        enabledTargets = updated
    }

    public func configuredTargets() -> Set<ExportTarget> {
        let readwise = (try? secretStore.read(SecretKey.readwise)) ?? nil
        let notionToken = (try? secretStore.read(SecretKey.notionAccessToken)) ?? nil
        return configuredTargets(readwise: readwise, notionToken: notionToken)
    }

    public func isTargetConfigured(_ target: ExportTarget) -> Bool {
        configuredTargets().contains(target)
    }

    private func configuredTargets(readwise: String?, notionToken: String?) -> Set<ExportTarget> {
        var set: Set<ExportTarget> = []
        if (readwise?.isEmpty == false) { set.insert(.readwise) }
        if (notionToken?.isEmpty == false) && (notionConnection?.isFullyConfigured == true) {
            set.insert(.notion)
        }
        return set
    }

    // MARK: Notion connection

    public func saveNotionConnection(_ connection: NotionConnection, accessToken: String) throws {
        try secretStore.write(accessToken, for: SecretKey.notionAccessToken)
        notionConnection = connection
    }

    public func updateNotionParentPage(pageID: String, title: String) {
        guard var conn = notionConnection else { return }
        conn.parentPageID = pageID
        conn.parentPageTitle = title
        notionConnection = conn
    }

    public func recordNotionBookPage(bookID: String, pageID: String) {
        guard var conn = notionConnection else { return }
        guard conn.bookPageCache[bookID] != pageID else { return }
        conn.setCachedPageID(pageID, forBookID: bookID)
        notionConnection = conn
    }

    public func clearNotionConnection() throws {
        try secretStore.delete(SecretKey.notionAccessToken)
        var updated = enabledTargets
        updated.remove(.notion)
        enabledTargets = updated
        notionConnection = nil
    }

    // MARK: Clients

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

    public func currentNotionClient() -> NotionClient? {
        guard let token = (try? secretStore.read(SecretKey.notionAccessToken)) ?? nil,
              !token.isEmpty else {
            return nil
        }
        return NotionClient(token: token)
    }

    public func currentNotionOAuth() -> NotionOAuth? {
        guard let config = notionOAuthConfig else { return nil }
        return NotionOAuth(config: config)
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
