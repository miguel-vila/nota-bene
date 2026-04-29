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
    @Published public var readwiseKeyMasked: String = ""

    public let secretStore: SecretStore
    public private(set) var bookStore: BookStore
    public let openLibrary: OpenLibraryClient

    public var libraryRefreshIntervalHours: Double = 12

    public init(
        secretStore: SecretStore,
        bookStore: BookStore,
        openLibrary: OpenLibraryClient = OpenLibraryClient()
    ) {
        self.secretStore = secretStore
        self.bookStore = bookStore
        self.openLibrary = openLibrary
        refreshKeyState()
    }

    public func refreshKeyState() {
        let gemini = (try? secretStore.read(SecretKey.gemini)) ?? nil
        let readwise = (try? secretStore.read(SecretKey.readwise)) ?? nil
        geminiKeyMasked = Self.mask(gemini)
        readwiseKeyMasked = Self.mask(readwise)
        phase = (gemini?.isEmpty == false && readwise?.isEmpty == false) ? .ready : .setup
    }

    public func saveGeminiKey(_ value: String) throws {
        try persist(value, for: SecretKey.gemini)
    }

    public func saveReadwiseKey(_ value: String) throws {
        try persist(value, for: SecretKey.readwise)
    }

    public func clearGeminiKey() throws {
        try secretStore.delete(SecretKey.gemini)
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
        return GeminiClient(apiKey: key)
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
