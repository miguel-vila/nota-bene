# Nota Bene

iOS app that turns highlighted passages in physical books into structured highlights, via a vision LLM (Gemini or Claude), and ships them to one or more **export targets** (Readwise and/or Notion).

See [`spec.md`](./spec.md) for the full product spec.

## Layout

```
Package.swift                          Swift Package (library + tests)
project.yml                            XcodeGen spec for the iOS App target
Sources/NotaBene/
  Models/                              Book, ExtractionResult, PendingHighlight,
                                       ExportTarget, NotionConnection
  Clients/                             GeminiClient, ClaudeClient, ReadwiseClient,
                                       NotionClient, NotionOAuth, OpenLibraryClient
  Storage/                             SecretStore + Keychain impl, BookStore JSON cache
  ViewModels/                          AppState, CaptureFlow, BookSearch,
                                       HighlightSubmitter (fan-out across targets)
  UI/                                  SwiftUI views + AVFoundation camera (iOS only)
Tests/NotaBeneTests/                   XCTest suite (run with `swift test`)
App/                                   Files for the iOS App target
  HighlighterApp.swift                 @main entry, wires up AppState
  Info.plist                           Bundle metadata (regenerated from project.yml)
cloudflare-workers/
  notion-oauth/                        Cloudflare Worker that holds the Notion OAuth
                                       client secret and proxies the code-for-token
                                       exchange. Required for the Notion export target.
                                       See its own README for deploy + secret setup.
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
xcodegen generate             # regenerates NotaBene.xcodeproj
open NotaBene.xcodeproj
```

Then in Xcode:

1. Select the **NotaBeneApp** target → **Signing & Capabilities** → pick your team.
2. Plug in your iPhone, select it as the run destination, and hit ⌘R.

The camera does not work in the simulator — you need a real device.

On first launch you'll walk through a four-step setup: pick a model provider, paste its API key, pick one or both export targets (Readwise, Notion), and then configure each chosen target (Readwise token, and/or Notion OAuth + parent-page picker). All keys are stored in the iOS Keychain; the Notion connection metadata (workspace, parent page, per-book page-id cache) is persisted to `UserDefaults`.

## Enabling Notion as an export target

The Notion target requires deploying the Cloudflare Worker in [`cloudflare-workers/notion-oauth/`](./cloudflare-workers/notion-oauth/) — it holds the Notion OAuth client secret so it never ships in the app binary. See that directory's README for `wrangler deploy` and `wrangler secret put NOTION_CLIENT_ID / NOTION_CLIENT_SECRET` instructions. Once the Worker is live, set the `NOTION_CLIENT_ID` and `NOTION_WORKER_BASE_URL` values in `project.yml` (they're bundled into `Info.plist` at build time) and run `xcodegen generate` again. If those values are missing, the Notion option in setup/Settings is shown disabled with a hint.

## Notes on choices

- **No Gemini SDK.** The official Swift SDK is deprecated, the Firebase replacement requires a Firebase project, and the community alternative is single-maintainer. A direct REST call via `URLSession` is ~50 lines and has no dependency risk — see `GeminiClient`.
- **No Claude SDK.** Anthropic doesn't ship a Swift SDK; the REST API is small. See `ClaudeClient`.
- **No Readwise SDK.** None exists for Swift; the API is small and stable. See `ReadwiseClient`.
- **No Notion SDK.** Notion's JS SDK is the only first-party one; we hand-roll a small `NotionClient` actor covering the four endpoints the app actually uses (`/v1/users/me`, `/v1/search`, `/v1/blocks/<id>/children`, `/v1/pages`).
- **OAuth via Cloudflare Worker.** Notion's 3-legged OAuth requires keeping the client secret server-side. A tiny TypeScript Worker holds it and exposes one endpoint (`POST /oauth/notion/exchange`) that the app calls after `ASWebAuthenticationSession` returns the auth code.
- **Open Library** for the "new book" search source (no API key, broad long-tail coverage).
- **Keychain** for all secrets (provider keys, Readwise token, Notion access token); `InMemorySecretStore` is provided for tests.
- **Book cache** is a JSON file in Application Support — pull-to-refresh and a 12h TTL trigger a reload from `GET /api/v2/books/`.
- **Parallel fan-out.** When more than one export target is enabled, `HighlightSubmitter.submit` runs them concurrently in a `TaskGroup` and reports per-target success/failure rather than failing the whole Save on the first error.
