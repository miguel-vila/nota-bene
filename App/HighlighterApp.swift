import SwiftUI
import NotaBene

@main
struct HighlighterApp: App {
    @StateObject private var state: AppState

    init() {
        let secretStore: SecretStore = KeychainSecretStore()
        let bookStore = BookStore(url: BookStore.defaultURL())
        _state = StateObject(wrappedValue: AppState(
            secretStore: secretStore,
            bookStore: bookStore
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
        }
    }
}
