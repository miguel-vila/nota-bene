# iPhone App Spec — Physical Highlight Capture (Nota Bene)

## Overview

A native iPhone app that turns highlighted passages in physical books into structured highlights. The user selects a book, photographs a highlighted passage, lets a vision LLM extract the text and (optionally) the page number, reviews/edits the result, and submits it to one or more **export targets**.

Export targets supported in v1:

- **Readwise** — the original target. Highlights are POSTed to `/api/v2/highlights/` and the book is created implicitly from the payload's `title`/`author`.
- **Notion** — appends each captured highlight as a quote block (plus a gray paragraph for the page number / note) under a per-book child page inside a user-chosen parent page.

A user may have **both** targets enabled at the same time. When they do, a Save fans out to every enabled target in parallel and the Saved screen reports per-target success/failure (see "5. Submit" below).

## Model providers

The app supports multiple vision-LLM providers. v1 ships with two:

- **Gemini** (Google) — default. Uses the `generativelanguage.googleapis.com` REST endpoint with the user's API key.
- **Claude** (Anthropic) — uses the `api.anthropic.com/v1/messages` endpoint with the user's API key. Structured output is forced via tool use (a `report_highlights` tool whose `input_schema` matches the highlights JSON shape).

Adding a new provider is a matter of conforming a new client to `HighlightExtractor` and listing the provider in the `LLMProvider` enum (with its preset model list). The capture/extraction flow is provider-agnostic.

## First-launch setup

- Setup is a four-step wizard. Steps 1–3 are flat, single-purpose screens; step 4 is repeated once per export target the user picked in step 3.
  - **Step 1 — Provider.** The user picks a model provider (Gemini or Claude) from two cards. The "Continue" button advances to step 2.
  - **Step 2 — Provider key.** The user pastes the active provider's API key in a single `KeyField`. The field shows a green `✓ Valid` chip as soon as its value passes a **format check** (Gemini: `AIza…` prefix, Claude: `sk-ant-…` prefix). The "Continue" button is disabled until the field passes the format check.
  - **Step 3 — Pick targets.** The user checks one or both export targets (Readwise, Notion). At least one must be selected to advance. If the app was built without a Notion OAuth configuration (no `NOTION_CLIENT_ID` / `NOTION_WORKER_BASE_URL` in `project.yml`), the Notion option is shown disabled with a hint to configure the worker.
  - **Step 4 — Configure each selected target** (looped per target, in the order they appear in `ExportTarget.allCases`):
    - **Readwise**: paste the Readwise token in a single `KeyField`, with the same format-check chip (Readwise: alphanumeric token of at least 20 characters). The "Continue" button is disabled until the field passes the format check.
    - **Notion**: tap "Connect Notion" to launch the OAuth flow (see "Export targets — Notion" below). After the workspace card appears, the user picks a parent page from `searchTopLevelPages()` and taps "Continue". The Notion access token is stored to the Keychain and the `NotionConnection` to `UserDefaults` **as soon as OAuth completes**, so an interrupted setup leaves the partial connection intact (parent page can be picked later from Settings).
  - Finishing the last per-target step persists the provider key (and, if Readwise was picked, the Readwise token) to the Keychain in one operation and flips the app to `.ready`.
- The format check on every key step is purely structural — it does not call the API. Real validation happens when the keys are used (extraction / submit) or via "Test connection" in Settings.
- **Token-page links.** On every key step, the right-side hint inside each `KeyField` is a **tappable link** that opens the relevant token page in the default browser, so the user doesn't have to hunt for it:
  - Gemini → `https://aistudio.google.com/apikey`
  - Claude → `https://console.anthropic.com/settings/keys`
  - Readwise → `https://readwise.io/access_token`
- **Privacy notice.** A privacy notice appears beneath the key field on every key-entry step. It states that the app does not store or transmit the user's API keys anywhere — they live only in the iOS Keychain on the device and are sent only to the service they're for. The notice includes a link to the app's source code at `https://github.com/miguel-vila/nota-bene` so the user can verify the claim. (Notion's OAuth flow is exempt — it goes through the Cloudflare Worker; see "Notion API integration".)
- The active provider's API key plus **at least one configured export target** are required before the app becomes usable. The user can switch providers and add or remove export targets later in Settings.
- **Adding a provider key from Settings** does **not** reuse the first-launch wizard. Tapping a provider whose key is not yet set opens a focused single-step sheet that only asks for that provider's API key (reusing the same `KeyField` and `PrivacyNotice` components, with the same format-check chip and token-page link). Saving the key persists it and switches the active provider in one step; cancelling leaves the active provider unchanged. The export-targets steps are skipped because those were already configured during first-launch setup (or can be managed from Settings).
- Keys are stored in the iOS Keychain (not UserDefaults). Each provider's key, the Readwise token, and the Notion access token each live under their own keychain item, so switching back and forth does not require re-pasting.
- A Settings screen allows the user to view (masked), replace, or clear any key, and to enable/disable individual export targets.
- Settings includes a "Test connection" action for each configured target:
  - Active provider: a minimal vision request.
  - Readwise: `GET /api/v2/auth/`.
  - Notion: `GET /v1/users/me` with the stored access token.
- Settings is split into two top-level sections:
  - **Model** — provider selector (segmented), the active provider's API-key card, and the active provider's model picker. Each provider has its own model preset list and persisted model selection:
    - Gemini presets: Flash (default), Pro, Flash Lite.
    - Claude presets: Sonnet (default), Opus, Haiku.
    - A "Custom…" option allows entering an arbitrary model name for advanced users.
    - "Reset to default" restores the recommended default for the active provider.
  - **Export targets** — one card per target with a toggle in the header and management actions in the body (token replacement, "Test connection", and, for Notion, parent-page change and "Disconnect"). The toggle for an unconfigured target opens the configuration UI; flipping the toggle off on the last enabled+configured target is rejected with a toast ("At least one destination must stay on.") so the app cannot end up with zero active targets while in `.ready`.
- The active provider and per-provider model selections are persisted across launches and applied to all subsequent extractions. The set of enabled export targets and the Notion connection (workspace, parent page, per-book page-id cache) are also persisted.

## Main flow

### 1. Book selection

- Single search field at the top of the screen.
- Typeahead/smart search merges results from two sources:
  - **Readwise library** (`GET /api/v2/books/?category=books`): the user's existing books. Fetched once and cached locally; refreshed on pull-to-refresh and on app foreground after N hours. Results from this source are labelled "In your library".
  - **Open Library search API** (`https://openlibrary.org/search.json?q=...&limit=10&fields=title,author_name,key,cover_i`): for books the user has not highlighted before. This is the common case — most first-time highlights for a new book will not match anything in Readwise yet. Results from this source are labelled "New book".
- The search field debounces input (~300ms) and queries both sources in parallel. Readwise matches appear above Open Library matches. Duplicates (same title + author) are de-duplicated, preferring the Readwise entry.
- Open Library is preferred over Google Books because it has no API key requirement and broader long-tail coverage. The implementer can swap to Google Books if needed without changing the rest of the app.
- Each result displays a small cover thumbnail alongside the title and author (from the Readwise book record's cover URL or Open Library's cover ID).
- Recently used books appear at the top of the list when the search field is empty.
- "Add book manually" option at the bottom of the list (for the rare case where a book is missing from both sources):
  - Form: title (required), author (optional).
- Books from Open Library and manual entry are not pre-registered in Readwise — they are created implicitly when the first highlight is submitted (Readwise creates the book from the highlight payload's `title`/`author`).
- Selecting a book transitions to the Capture screen.

### 2. Capture

- Full-screen camera view (AVFoundation) opens automatically once a book is selected.
- Header shows the currently selected book title (tap to change).
- A `PAGE N / 2` chip in the top-left of the viewport shows which page is about to be captured (1 before any photo is taken, 2 after the first). The chip is hidden when no pages have been captured yet for the current submission, and reappears once at least one page is in the buffer.
- Capture button takes a still photo.
- Alternative: a "Pick from library" button to choose an existing photo (e.g. one taken earlier offline).
- After capture, a preview screen with three actions:
  - Retake → discard captured pages and return to camera.
  - Turn page → keep the captured page(s) and return to camera to capture the next page (for highlights that span a page break). Capped at 2 pages per submission.
  - Use photo(s) → go to Extraction with all captured pages.

### 3. Extraction

- The captured image(s) are sent to the **active provider's vision model** (Gemini or Claude — configurable; see "Model providers" above) in a single request. Multiple page images are passed as separate parts in reading order (Gemini: `inline_data` parts; Claude: `image` content blocks), so the model can natively merge a highlight that wraps across the page break instead of forcing the client to stitch.
- Both providers share the same extraction prompt and produce the same JSON shape. Provider choice is invisible to the rest of the flow.
- The request uses structured output (JSON schema) and returns an array of highlights, each with:
  - `text` (string): the text marked with highlighter, pen, pencil, bracket, or underline. Verbatim, preserving punctuation.
  - `page_number` (integer | null): the page number visible in the photo, if any.
  - `note` (string | null): a handwritten margin/inline note physically closest to this highlight, if any. Notes that aren't clearly attached to a single highlight are skipped; illegible notes are returned as `null` rather than guessed.
- A single photo may contain multiple distinct highlighted passages — the model returns each as a separate entry in reading order. An empty array means no highlight was detected.
- The prompt instructs the model to:
  - Return only the marked passages, not the surrounding unmarked text.
  - Preserve original line wrapping as spaces (no hyphenation artifacts).
  - Return `null` for `page_number` if no page number is visible or unambiguous.
- The prompt adapts to the number of pages in the capture: single-page captures get a leaner prompt with no cross-page wording, while multi-page captures get an extended version that tells the model to treat the images as consecutive pages and merge any passage that continues across the page break into a single entry.
- A loading indicator is shown while the request is in flight.
- Failures (network, invalid key, model error) land on a dedicated extraction-failed screen — **not** on Review. The screen shows the error message and four actions, in priority order:
  - **Try again** (primary): re-runs extraction against the same captured images, no re-shoot needed.
  - **Type manually**: skips extraction and goes to Review with a single empty highlight (the historical "skip" behavior).
  - **Back to photo**: returns to the Preview screen so the user can retake or turn the page.
  - **Back to books**: dismisses the capture flow entirely and returns to the Book selection screen (the main menu).

### 4. Review

- One editable group per detected highlight, each with:
  - **Text** (multiline): pre-filled, editable.
  - **Page number** (numeric): pre-filled if detected, editable.
  - **Note** (multiline): pre-filled with the closest detected handwritten note, editable. Empty if the model didn't attach a note to this highlight; the user can still type one in manually.
- Users can remove individual highlights or add a blank one to type manually.
- The selected book is shown above the highlights. Tapping it returns to book selection (preserving the captured photo and extracted highlights in memory).
- Primary action: **Save**. Disabled if no highlight has any text. All non-empty highlights are submitted together.
- Secondary action: **Cancel**. Discards the highlights and returns to the camera.

### 5. Submit

On Save, the highlights are fanned out **in parallel** to every export target that is currently enabled and configured (see `HighlightSubmitter.submit`). A `SubmissionResult` records the set of `succeeded` targets and a list of `SubmissionFailure { target, message }` for the rest.

- **Readwise destination**: `POST /api/v2/highlights/` with one entry per highlight from the Review screen:

  ```json
  {
    "highlights": [
      {
        "text": "<edited text>",
        "title": "<book title>",
        "author": "<book author, if known>",
        "source_type": "physical_book_capture",
        "category": "books",
        "location": <page number, if provided>,
        "location_type": "page",
        "note": "<edited note, if provided>"
      }
    ]
  }
  ```

- **Notion destination**: idempotent per (workspace, book).
  - The destination looks up the book's Notion page id in the per-`NotionConnection` `bookPageCache`. On hit, it appends straight to the cached page; on miss it calls `findOrCreateBookPage`, which paginates the parent page's children searching for an existing child page whose title matches `"<book title> — <author>"` (or just the title when no author). If none is found, a new child page is created via `POST /v1/pages` under the configured parent.
  - The resolved page id is then written back into both the in-memory `NotionBookPageCache` (the per-submission cache shared across highlights in this submission) and the persisted `NotionConnection.bookPageCache` (so future submissions for the same book go straight to PATCH).
  - Highlights are appended via `PATCH /v1/blocks/<page>/children` with a `quote` block per highlight, optionally followed by a gray `paragraph` block of the form `P. <n> — Note: <note>` (parts omitted if missing).
  - **Idempotency caveat.** "Find or create" only deduplicates the *book page*, not the *highlights themselves*. Re-submitting the same highlight for the same book will append a duplicate quote block. This is a deliberate v1 limitation — Notion's block API has no natural id for "this highlight already exists" and the per-highlight equality check (text + page + note) is brittle. Users are expected to treat a successful Save as final.

- On all-success: navigate to the dedicated **Saved** screen (see "6. Saved" below).
- On any failure: keep the user on the Review screen, show one error message per failed target, allow retry. Do not lose the edited text. Successful targets are not re-sent on retry (a future improvement; v1 retries the whole submission, which is acceptable because Readwise dedup is server-side on (title, text, page) and Notion's only side-effect is the duplicate-quote-block caveat above).
- Error messages are produced by `HighlightSubmitter.message(for:target:includeBody:)` and surface as user-readable strings (e.g. "Notion access expired — reconnect in Settings.", "Readwise returned HTTP 500."). When **Debug mode** is on (Settings), the message also includes the raw response body for triage.

### 6. Saved

- Shown after a successful submit. Light background, centered content.
- A snapshot of the just-saved highlights is rendered as **fanned chips** (up to 2 visible), each showing a green check, a `SAVED · P.<n>` mono label, and a single-line excerpt of the highlight text.
- Headline: "**N highlights** saved." with a yellow swipe behind the count.
- Two actions:
  - **Capture another** (primary): returns to the Capture screen with the same book preselected, so consecutive highlights from the same book require no re-selection.
  - **Done** (ghost): pops back to the Book selection screen.
- The captured images and draft highlights are cleared from memory once Saved is shown; only the snapshot of the saved highlights is kept for the chip preview. The snapshot is discarded once the user leaves Saved.

## Navigation

- Tab-less, single stack.
- Top-level: Book selection.
- Push: Capture → Preview → Extracting → Review → Saved → (Capture, same book) **or** (back to Book selection).
- A "Change book" affordance is available from Capture and Review.
- Settings is accessible from the Book selection screen via a gear icon.

## Export targets

`ExportTarget` is the user-facing enum (`readwise`, `notion`) that drives Settings cards, the onboarding "Pick targets" step, and the per-submission fan-out. Every target conforms to `HighlightDestination`:

```swift
protocol HighlightDestination {
    var target: ExportTarget { get }
    func submit(book: Book, highlights: [HighlightDraft]) async throws
}
```

Submissions go through `HighlightSubmitter.submit(book:highlights:destinations:debugIncludesBody:)`, which runs each destination's `submit` concurrently inside a `TaskGroup` and aggregates the result into a `SubmissionResult`.

### Notion

- **Auth (OAuth).** Notion uses 3-legged OAuth, which means the client secret must never leave the server. The app talks to a tiny Cloudflare Worker (`cloudflare-workers/notion-oauth`) that holds `NOTION_CLIENT_ID` / `NOTION_CLIENT_SECRET` as wrangler secrets. The Worker exposes a single `POST /oauth/notion/exchange` endpoint that the iOS app calls after `ASWebAuthenticationSession` redirects back. The Worker proxies the exchange to `https://api.notion.com/v1/oauth/token` and returns Notion's response untouched.
- The app launches the authorize URL with `client_id` (from `project.yml` → bundled into `Info.plist`), `response_type=code`, `owner=user`, the Worker's `redirect_uri`, and a per-attempt `state`. The custom URL scheme `notabene://oauth/notion/callback` is registered via `CFBundleURLTypes`.
- A redirect with `error=access_denied` is mapped to `NotionOAuthError.userCancelled` (silently dismissed); any other `error=…` lands as `NotionOAuthError.providerError(code, description?)` with a toast.
- **Persisted state.** A successful exchange yields a `NotionConnection { workspaceID, workspaceName?, workspaceIcon?, botID, parentPageID?, parentPageTitle?, bookPageCache, connectedAt }`. The connection is saved to `UserDefaults` (encoded JSON) and the access token to the Keychain under its own item. `NotionConnection.isFullyConfigured` is true only when `parentPageID != nil`, so a user who connects but never picks a parent page stays in `.setup`.
- **Parent page picker.** `NotionClient.searchTopLevelPages()` calls `POST /v1/search` with `filter: page` and sorts results by last edited; the user picks one. The picked id + title are written into `NotionConnection.parentPageID` / `parentPageTitle`.
- **Per-book page cache.** `NotionConnection.bookPageCache` is a `[bookID: pageID]` dictionary persisted alongside the rest of the connection, so subsequent submissions of the same book skip the "find or create" round-trip. A per-submission `NotionBookPageCache` actor mirrors this for the lifetime of a single Save (avoiding races inside a fan-out).
- **Removing the connection.** `clearNotionConnection()` deletes the token from the Keychain, removes Notion from `enabledTargets`, and wipes the persisted `NotionConnection` (including the bookPageCache). Reconnecting starts from a clean slate.

## Data model

- `Book`: `{ id, title, author?, source: "readwise" | "open_library" | "manual", lastUsedAt, coverURL?, readwiseID? }`
- `PendingHighlight` (in-memory only during a session): `{ book, images: [Data], highlights: [{ text, pageNumber?, note? }] }`
- `ExportTarget`: `readwise` | `notion` — the set of targets the user has enabled is persisted in `UserDefaults` under `enabledExportTargets`. On first launch, if the user already had a Readwise key from an older build, Readwise is auto-migrated into `enabledExportTargets`.
- `NotionConnection` (persisted as JSON in `UserDefaults`): `{ workspaceID, workspaceName?, workspaceIcon?, botID, parentPageID?, parentPageTitle?, bookPageCache: [bookID: pageID], connectedAt }`.
- Recently used books and the cached Readwise book list are persisted locally (a JSON file in Application Support; see `BookStore`).

## Experimental features

The Settings screen exposes an "Experimental" section listing opt-in feature flags. Each flag is off by default and is persisted in `UserDefaults` so the choice survives relaunches. Toggling a flag immediately changes the affected UI without requiring a restart.

Active flags:

- **Merge highlights** — adds a "Merge with above" affordance at the top of every highlight after the first in the Review screen. Tapping it folds the current highlight into the one above:
  - **Text** is concatenated as `<upper> <lower>` (each side trimmed; if either side is empty the other is kept verbatim).
  - **Page number** keeps the upper highlight's value when present, otherwise falls back to the lower one's.
  - **Note** is concatenated as `<upper>\n\n<lower>` (each side trimmed; if either side is empty the other is kept verbatim).
  - The lower highlight is removed and the upper highlight's identity is preserved so the user's editing focus stays put.

## Error handling

- Invalid provider (Gemini/Claude) key → block extraction, prompt the user to update the key in Settings (or switch to a provider whose key is set).
- Invalid Readwise key → submission to Readwise fails with `ReadwiseError.invalidToken`; the Saved/Review screen shows "Readwise token rejected — update it in Settings." If Notion is also enabled and succeeds, the user lands on Saved with one failure listed and the Readwise highlights not delivered.
- Invalid Notion token (expired or revoked workspace install) → submission to Notion fails with `NotionError.invalidToken`; the message is "Notion access expired — reconnect in Settings."
- Provider returns an empty highlights array → still proceed to Review with empty text and a small notice ("No highlight detected — type the passage manually").
- Network failure on any export target → that target lands in `SubmissionResult.failures`; the others may still succeed. Retry from Review re-runs the whole submission (see "5. Submit" idempotency caveat).
- Disabling the last enabled+configured target from Settings is rejected with a toast — the app guarantees at least one active destination while in `.ready`.
- Camera permission denied → show explanation with a "Open Settings" deep link.

## API integrations

- **Gemini**: `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent` with the user's API key (`x-goog-api-key` header). Multimodal request with the captured image plus instruction prompt and JSON schema (`generationConfig.responseSchema`).
- **Claude**: `https://api.anthropic.com/v1/messages` with the user's API key (`x-api-key` header) and the `anthropic-version: 2023-06-01` header. Multimodal request with `image` content blocks plus the instruction prompt as the `system` field. Structured output is enforced via a single tool (`report_highlights`) with `tool_choice: {type: "tool", name: "report_highlights"}`; the response's `tool_use` block carries the highlights JSON.
- **Readwise**:
  - `GET /api/v2/books/?category=books` — list user's books.
  - `POST /api/v2/highlights/` — create highlight(s).
  - `GET /api/v2/auth/` — validate token.
- **Notion**: all calls use `Authorization: Bearer <access_token>` and the `Notion-Version: 2022-06-28` header.
  - `GET /v1/users/me` — validate token (used by "Test connection" in Settings).
  - `POST /v1/search` with `filter.value=page` — list candidate parent pages for the picker.
  - `GET /v1/blocks/<parent>/children?page_size=100` (paginated) — search for an existing per-book child page by exact title.
  - `POST /v1/pages` — create a per-book child page under the chosen parent.
  - `PATCH /v1/blocks/<page>/children` — append `quote` + (optional) gray `paragraph` blocks.
  - **OAuth via Cloudflare Worker.** Authorize URL is built client-side; the code-for-token exchange is `POST <WORKER>/oauth/notion/exchange` (the Worker injects `NOTION_CLIENT_ID` / `NOTION_CLIENT_SECRET` and forwards to `https://api.notion.com/v1/oauth/token`).
- **Open Library**: `GET https://openlibrary.org/search.json` — book search for titles not in the user's Readwise library. No auth required.

## Libraries and dependencies

### Gemini (Swift SDK landscape, current as of 2026)

- Google's original `GoogleGenerativeAI` package (`github.com/google-gemini/generative-ai-swift`) is **deprecated** and frozen — Google explicitly states no further changes will be made to it.
- Google's currently-supported path is the **Firebase AI Logic SDK** (`FirebaseAILogic` library, part of `firebase-ios-sdk`). It does **not** fit this app's design: it requires a Firebase project and routes calls through Firebase rather than accepting a user-supplied raw Gemini API key. Since the whole point of this app is "user pastes their own Gemini API key," this SDK is not usable.
- Community alternative: `paradigms-of-intelligence/swift-gemini-api` accepts a raw API key but is small, single-maintainer, and not battle-tested.
- **Recommendation: skip the SDKs and call the Gemini REST endpoint directly via URLSession.** The app makes exactly one kind of call (multimodal + structured JSON output). A direct REST client is ~50 lines of Swift, has zero dependency risk, and will not be invalidated by future Google SDK reorganizations. Wrap it in a `GeminiClient` actor that conforms to a small `HighlightExtractor` protocol with one method: `extractHighlights(fromImages: [Data], mimeType: String) async throws -> ExtractionResult`.

### Claude (Swift SDK landscape)

- Anthropic does not publish a first-party Swift SDK. As with Gemini, we call the REST endpoint directly via `URLSession` and wrap it in a `ClaudeClient` actor that conforms to the same `HighlightExtractor` protocol — so the capture flow doesn't care which provider it talks to.

### Readwise

- **No official or widely-used Swift SDK exists.** The "awesome-readwise" community list shows clients in JS/TS, Python, Ruby, and Go — nothing for Swift.
- Readwise's API is a small, stable REST surface (token in `Authorization` header, JSON in/out). Hand-roll a `ReadwiseClient` using URLSession with three methods: `validateToken()`, `listBooks()`, `createHighlight(...)`.

### Other dependencies

- **Networking**: URLSession (no Alamofire needed for this scope).
- **Keychain**: either Apple's Security framework directly, or a thin wrapper like `KeychainAccess` (`github.com/kishikawakatsumi/KeychainAccess`) — the wrapper is small and reduces boilerplate, but is not required.
- **Camera**: AVFoundation directly. SwiftUI has no first-party camera view, so wrap `AVCaptureSession` in a `UIViewControllerRepresentable`.
- **Image picker** (for the "pick from library" alternative): `PhotosPicker` (SwiftUI, iOS 16+).

## Tech stack

- iOS 17+
- Swift, SwiftUI
- AVFoundation (camera)
- Keychain Services (API key storage)
- URLSession (networking)
- No required third-party dependencies. `KeychainAccess` is the only one worth considering, and only as a convenience.

## Out of scope for v1

- Tags or notes attached to highlights.
- Offline queue with background retry.
- Editing existing Readwise highlights.
- Per-highlight deduplication on Notion (see "5. Submit" — find-or-create only dedupes the *book page*, not the individual quote blocks).
- Selective per-target retry after a partial-failure Save (retry re-runs the whole submission).
- Notion databases as a target (current implementation appends children blocks to a regular page; database/property mapping is a future improvement).
- iPad layout, macOS Catalyst.
- Sync of cached book list across devices.
- Bulk import (multi-photo capture session).
