# Readwise Auto Highlighter

iOS app that turns highlighted passages in physical books into Readwise highlights via Gemini.

See [`spec.md`](./spec.md) for the full product spec.

## Layout

```
Package.swift                          Swift Package (library + tests)
Sources/ReadwiseHighlighter/
  Models/                              Book, ExtractionResult, PendingHighlight
  Clients/                             GeminiClient, ReadwiseClient, OpenLibraryClient (URLSession)
  Storage/                             SecretStore + Keychain impl, BookStore JSON cache
  ViewModels/                          AppState, CaptureFlow, BookSearch
  UI/                                  SwiftUI views + AVFoundation camera (iOS only)
Tests/ReadwiseHighlighterTests/        XCTest suite (run with `swift test`)
App/                                   Files for the iOS App target (Xcode wrapper)
  HighlighterApp.swift                 @main entry, wires up AppState
  Info.plist                           Camera + Photo Library usage descriptions
```

## Running tests

The cross-platform core compiles for macOS so tests run from the command line:

```sh
swift test
```

The `UIKit` / `AVFoundation` views are guarded by `#if canImport(UIKit)` and only compile in an iOS context.

## Building the iOS app

The repo ships as a Swift Package plus loose `App/` files. Wire them into an Xcode iOS app target:

1. Open Xcode → **File → New → Project → iOS → App**, language Swift, interface SwiftUI, target iOS 17+.
2. Delete the auto-generated `ContentView.swift` and `App.swift`.
3. Drag `App/HighlighterApp.swift` into the new target. Replace the new target's `Info.plist` with `App/Info.plist` (or copy the two `NS*UsageDescription` keys into the existing one).
4. Add this directory as a local Swift Package: **File → Add Package Dependencies → Add Local…** and pick the repo root. Add the `ReadwiseHighlighter` library to the app target.
5. Build & run on a real device (the camera does not work in the simulator).

On first launch you'll be asked for a Gemini API key and a Readwise token; they're stored in the iOS Keychain.

## Notes on choices

- **No Gemini SDK.** The official Swift SDK is deprecated, the Firebase replacement requires a Firebase project, and the community alternative is single-maintainer. A direct REST call via `URLSession` is ~50 lines and has no dependency risk — see `GeminiClient`.
- **No Readwise SDK.** None exists for Swift; the API is small and stable. See `ReadwiseClient`.
- **Open Library** for the "new book" search source (no API key, broad long-tail coverage).
- **Keychain** for both API keys; `InMemorySecretStore` is provided for tests.
- **Book cache** is a JSON file in Application Support — pull-to-refresh and a 12h TTL trigger a reload from `GET /api/v2/books/`.
