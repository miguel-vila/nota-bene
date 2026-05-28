#if canImport(SwiftUI)
import XCTest
@testable import NotaBene

@MainActor
final class AppStateTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func tempBookStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("appstate-books-\(UUID().uuidString).json")
    }

    func test_provider_defaultsToGemini() {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        XCTAssertEqual(state.provider, .gemini)
    }

    func test_provider_persistsAcrossInstances() {
        let defaults = makeDefaults()
        let url = tempBookStoreURL()
        let first = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        first.provider = .claude

        let second = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        XCTAssertEqual(second.provider, .claude)
    }

    func test_geminiModel_defaultsToClientDefaultWhenUnset() {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        XCTAssertEqual(state.geminiModel, GeminiClient.defaultModel)
    }

    func test_claudeModel_defaultsToClientDefaultWhenUnset() {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        XCTAssertEqual(state.claudeModel, ClaudeClient.defaultModel)
    }

    func test_geminiModel_persistsAcrossInstances() {
        let defaults = makeDefaults()
        let url = tempBookStoreURL()
        let first = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        first.geminiModel = "gemini-2.5-pro"

        let second = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        XCTAssertEqual(second.geminiModel, "gemini-2.5-pro")
    }

    func test_claudeModel_persistsAcrossInstances() {
        let defaults = makeDefaults()
        let url = tempBookStoreURL()
        let first = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        first.claudeModel = "claude-opus-4-7"

        let second = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        XCTAssertEqual(second.claudeModel, "claude-opus-4-7")
    }

    func test_resetGeminiModelToDefault() {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        state.geminiModel = "gemini-2.5-pro"
        state.resetGeminiModelToDefault()
        XCTAssertEqual(state.geminiModel, GeminiClient.defaultModel)
    }

    func test_currentModel_followsProvider() {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        state.provider = .gemini
        XCTAssertEqual(state.currentModel, state.geminiModel)
        state.provider = .claude
        XCTAssertEqual(state.currentModel, state.claudeModel)
    }

    func test_setCurrentModel_writesToActiveProvider() {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        state.provider = .claude
        state.setCurrentModel("claude-haiku-4-5")
        XCTAssertEqual(state.claudeModel, "claude-haiku-4-5")
        XCTAssertEqual(state.geminiModel, GeminiClient.defaultModel)
    }

    func test_resetCurrentModel_resetsActiveProviderOnly() {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        state.geminiModel = "gemini-2.5-pro"
        state.claudeModel = "claude-opus-4-7"
        state.provider = .claude
        state.resetCurrentModelToDefault()
        XCTAssertEqual(state.claudeModel, ClaudeClient.defaultModel)
        XCTAssertEqual(state.geminiModel, "gemini-2.5-pro")
    }

    func test_phase_readyRequiresActiveProviderKey() throws {
        let secrets = InMemorySecretStore()
        let state = AppState(
            secretStore: secrets,
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        try state.saveClaudeKey("c-key")
        try state.saveReadwiseKey("rw-key")
        state.enableTarget(.readwise)
        // Active provider still Gemini → no provider key set yet → setup.
        XCTAssertEqual(state.phase, .setup)

        state.provider = .claude
        XCTAssertEqual(state.phase, .ready)

        state.provider = .gemini
        XCTAssertEqual(state.phase, .setup)

        try state.saveGeminiKey("g-key")
        XCTAssertEqual(state.phase, .ready)
    }

    func test_phase_requiresAtLeastOneEnabledConfiguredTarget() throws {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        try state.saveGeminiKey("g-key")
        // Provider key but no target → setup.
        XCTAssertEqual(state.phase, .setup)
        try state.saveReadwiseKey("rw-key")
        // Token saved but not enabled → still setup.
        XCTAssertEqual(state.phase, .setup)
        state.enableTarget(.readwise)
        XCTAssertEqual(state.phase, .ready)
    }

    func test_enableTarget_doesNotMakeUnconfiguredTargetActive() throws {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        try state.saveGeminiKey("g-key")
        // Enabling .notion without any connection should not flip to ready.
        state.enableTarget(.notion)
        XCTAssertEqual(state.phase, .setup)
    }

    func test_disableTarget_lastConfiguredThrows() throws {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        try state.saveGeminiKey("g-key")
        try state.saveReadwiseKey("rw-key")
        state.enableTarget(.readwise)
        XCTAssertThrowsError(try state.disableTarget(.readwise)) { error in
            XCTAssertEqual(error as? AppState.TargetMutationError, .lastConfiguredTargetCannotBeDisabled)
        }
        XCTAssertTrue(state.enabledTargets.contains(.readwise))
    }

    func test_disableTarget_secondaryTargetSucceeds() throws {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        try state.saveGeminiKey("g-key")
        try state.saveReadwiseKey("rw-key")
        state.enableTarget(.readwise)

        // Add a fully-configured Notion connection.
        let conn = NotionConnection(
            workspaceID: "ws",
            botID: "bot",
            parentPageID: "p1",
            parentPageTitle: "Library"
        )
        try state.saveNotionConnection(conn, accessToken: "secret_n")
        state.enableTarget(.notion)
        XCTAssertEqual(state.configuredTargets(), [.readwise, .notion])

        XCTAssertNoThrow(try state.disableTarget(.notion))
        XCTAssertFalse(state.enabledTargets.contains(.notion))
        XCTAssertEqual(state.phase, .ready) // readwise still active
    }

    func test_configuredTargets_excludesNotionWithoutParentPage() throws {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        let conn = NotionConnection(workspaceID: "ws", botID: "bot") // no parent page
        try state.saveNotionConnection(conn, accessToken: "secret_n")
        XCTAssertFalse(state.configuredTargets().contains(.notion))
    }

    func test_init_migratesPreExistingReadwiseKeyToEnabledTargets() throws {
        let defaults = makeDefaults()
        let secrets = InMemorySecretStore()
        try secrets.write("rw-key", for: SecretKey.readwise)
        let state = AppState(
            secretStore: secrets,
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: defaults
        )
        XCTAssertEqual(state.enabledTargets, [.readwise])
    }

    func test_init_withoutReadwiseKey_doesNotAutoMigrate() throws {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        XCTAssertTrue(state.enabledTargets.isEmpty)
    }

    func test_clearNotionConnection_removesNotionFromEnabledTargets() throws {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        try state.saveGeminiKey("g-key")
        try state.saveReadwiseKey("rw-key")
        state.enableTarget(.readwise)
        let conn = NotionConnection(
            workspaceID: "ws",
            botID: "bot",
            parentPageID: "p1",
            parentPageTitle: "L"
        )
        try state.saveNotionConnection(conn, accessToken: "n-tok")
        state.enableTarget(.notion)
        try state.clearNotionConnection()
        XCTAssertNil(state.notionConnection)
        XCTAssertFalse(state.enabledTargets.contains(.notion))
        XCTAssertEqual(state.phase, .ready) // readwise still active
    }

    func test_notionConnection_persistsAcrossInstances() throws {
        let defaults = makeDefaults()
        let url = tempBookStoreURL()
        let first = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        let conn = NotionConnection(
            workspaceID: "ws-1",
            workspaceName: "My WS",
            botID: "bot-1",
            parentPageID: "page-1",
            parentPageTitle: "Library"
        )
        try first.saveNotionConnection(conn, accessToken: "secret")

        let second = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        XCTAssertEqual(second.notionConnection?.workspaceID, "ws-1")
        XCTAssertEqual(second.notionConnection?.parentPageID, "page-1")
    }

    func test_recordNotionBookPage_storesCacheEntry() throws {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        let conn = NotionConnection(
            workspaceID: "ws",
            botID: "bot",
            parentPageID: "p1",
            parentPageTitle: "L"
        )
        try state.saveNotionConnection(conn, accessToken: "n-tok")
        state.recordNotionBookPage(bookID: "book-1", pageID: "notion-page-1")
        XCTAssertEqual(state.notionConnection?.bookPageCache["book-1"], "notion-page-1")
        // Idempotent — same call doesn't duplicate.
        state.recordNotionBookPage(bookID: "book-1", pageID: "notion-page-1")
        XCTAssertEqual(state.notionConnection?.bookPageCache.count, 1)
    }

    func test_enabledTargets_persistsAcrossInstances() throws {
        let defaults = makeDefaults()
        let url = tempBookStoreURL()
        let first = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        try first.saveReadwiseKey("rw")
        first.enableTarget(.readwise)
        first.enableTarget(.notion) // even though not configured, persistence holds the choice

        let secondSecrets = InMemorySecretStore()
        try secondSecrets.write("rw", for: SecretKey.readwise)
        let second = AppState(
            secretStore: secondSecrets,
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        XCTAssertEqual(second.enabledTargets, [.readwise, .notion])
    }

    func test_experimentalMergeHighlights_defaultsFalse() {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        XCTAssertFalse(state.experimentalMergeHighlights)
    }

    func test_experimentalMergeHighlights_persistsAcrossInstances() {
        let defaults = makeDefaults()
        let url = tempBookStoreURL()
        let first = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        first.experimentalMergeHighlights = true

        let second = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: url),
            defaults: defaults
        )
        XCTAssertTrue(second.experimentalMergeHighlights)
    }

    func test_currentExtractor_picksProviderClient() throws {
        let secrets = InMemorySecretStore()
        let state = AppState(
            secretStore: secrets,
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        try state.saveGeminiKey("g-key")
        try state.saveClaudeKey("c-key")

        state.provider = .gemini
        XCTAssertTrue(state.currentExtractor() is GeminiClient)

        state.provider = .claude
        XCTAssertTrue(state.currentExtractor() is ClaudeClient)
    }
}
#endif
