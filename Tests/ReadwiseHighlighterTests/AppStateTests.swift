#if canImport(SwiftUI)
import XCTest
@testable import ReadwiseHighlighter

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
        // Both keys for the inactive provider don't satisfy readiness.
        try state.saveClaudeKey("c-key")
        try state.saveReadwiseKey("rw-key")
        XCTAssertEqual(state.phase, .setup)

        state.provider = .claude
        XCTAssertEqual(state.phase, .ready)

        state.provider = .gemini
        XCTAssertEqual(state.phase, .setup)

        try state.saveGeminiKey("g-key")
        XCTAssertEqual(state.phase, .ready)
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
