# Readwise Auto Highlighter

iOS app that turns highlighted passages in physical books into Readwise highlights via Gemini.

See [`spec.md`](./spec.md) for the full product spec.

## Layout

```
Package.swift                          Swift Package (library + tests)
project.yml                            XcodeGen spec for the iOS App target
Sources/ReadwiseHighlighter/
  Models/                              Book, ExtractionResult, PendingHighlight
  Clients/                             GeminiClient, ReadwiseClient, OpenLibraryClient (URLSession)
  Storage/                             SecretStore + Keychain impl, BookStore JSON cache
  ViewModels/                          AppState, CaptureFlow, BookSearch
  UI/                                  SwiftUI views + AVFoundation camera (iOS only)
Tests/ReadwiseHighlighterTests/        XCTest suite (run with `swift test`)
App/                                   Files for the iOS App target
  HighlighterApp.swift                 @main entry, wires up AppState
  Info.plist                           Bundle metadata (regenerated from project.yml)
```

## Running tests

The cross-platform core compiles for macOS so tests run from the command line:

```sh
swift test
```

The `UIKit` / `AVFoundation` views are guarded by `#if canImport(UIKit)` and only compile in an iOS context.

## Building the iOS app

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen        # one-time
xcodegen generate             # regenerates ReadwiseHighlighter.xcodeproj
open ReadwiseHighlighter.xcodeproj
```

Then in Xcode:

1. Select the **ReadwiseHighlighter** target → **Signing & Capabilities** → pick your team.
2. Plug in your iPhone, select it as the run destination, and hit ⌘R.

The camera does not work in the simulator — you need a real device.

On first launch you'll be asked for a Gemini API key and a Readwise token; they're stored in the iOS Keychain.

## Notes on choices

- **No Gemini SDK.** The official Swift SDK is deprecated, the Firebase replacement requires a Firebase project, and the community alternative is single-maintainer. A direct REST call via `URLSession` is ~50 lines and has no dependency risk — see `GeminiClient`.
- **No Readwise SDK.** None exists for Swift; the API is small and stable. See `ReadwiseClient`.
- **Open Library** for the "new book" search source (no API key, broad long-tail coverage).
- **Keychain** for both API keys; `InMemorySecretStore` is provided for tests.
- **Book cache** is a JSON file in Application Support — pull-to-refresh and a 12h TTL trigger a reload from `GET /api/v2/books/`.
