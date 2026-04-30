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

    func test_geminiModel_defaultsToClientDefaultWhenUnset() {
        let state = AppState(
            secretStore: InMemorySecretStore(),
            bookStore: BookStore(url: tempBookStoreURL()),
            defaults: makeDefaults()
        )
        XCTAssertEqual(state.geminiModel, GeminiClient.defaultModel)
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
}
#endif
