# iPhone App Spec — Readwise Physical Highlight Capture

## Overview

A native iPhone app that turns highlighted passages in physical books into Readwise highlights. The user selects a book, photographs a highlighted passage, lets a vision LLM extract the text and (optionally) the page number, reviews/edits the result, and submits it to Readwise.

## Model providers

The app supports multiple vision-LLM providers. v1 ships with two:

- **Gemini** (Google) — default. Uses the `generativelanguage.googleapis.com` REST endpoint with the user's API key.
- **Claude** (Anthropic) — uses the `api.anthropic.com/v1/messages` endpoint with the user's API key. Structured output is forced via tool use (a `report_highlights` tool whose `input_schema` matches the highlights JSON shape).

Adding a new provider is a matter of conforming a new client to `HighlightExtractor` and listing the provider in the `LLMProvider` enum (with its preset model list). The capture/extraction flow is provider-agnostic.

## First-launch setup

- Setup is a two-step wizard:
  - **Step 1 — Provider.** The user picks a model provider (Gemini or Claude) from two cards. The "Continue" button advances to step 2.
  - **Step 2 — Keys.** The user pastes the active provider's API key and the Readwise token in two `KeyField` rows. Each field shows a green `✓ Valid` chip as soon as its value passes a **format check** (Gemini: `AIza…` prefix, Claude: `sk-ant-…` prefix, Readwise: alphanumeric token of at least 20 characters). The format check is purely structural — it does not call the API. Real validation happens when the keys are used (extraction / submit) or via "Test connection" in Settings. The "Finish setup" button is disabled until both fields pass the format check.
- The active provider's API key plus the Readwise key are required before the app becomes usable. The user can switch providers later in Settings; switching to a provider whose key is not yet set returns the app to the setup state until that key is provided.
- Keys are stored in the iOS Keychain (not UserDefaults). Each provider's key is stored under its own keychain item, so switching back and forth does not require re-pasting.
- A Settings screen allows the user to view (masked), replace, or clear any key.
- Settings includes a "Test connection" action for each key:
  - Active provider: a minimal vision request.
  - Readwise: `GET /api/v2/auth/`.
- Settings is structured so that the **provider selector comes first**. The chosen provider drives which API-key section and which model picker are shown below. Each provider has its own model preset list and persisted model selection:
  - Gemini presets: Flash (default), Pro, Flash Lite.
  - Claude presets: Sonnet (default), Opus, Haiku.
  - A "Custom…" option allows entering an arbitrary model name for advanced users.
  - "Reset to default" restores the recommended default for the active provider.
- The active provider and per-provider model selections are persisted across launches and applied to all subsequent extractions.

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

### 5. Submit to Readwise

- `POST /api/v2/highlights/` with payload (one entry per highlight from the Review screen):

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

- On success: navigate to a dedicated **Saved** screen (see "6. Saved" below) instead of silently returning to capture.
- On failure: keep the user on the Review screen, show the error, allow retry. Do not lose the edited text.

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

## Data model

- `Book`: `{ id, title, author?, source: "readwise" | "open_library" | "manual", lastUsedAt, coverURL? }`
- `PendingHighlight` (in-memory only during a session): `{ book, images: [Data], highlights: [{ text, pageNumber? }] }`
- Recently used books and the cached Readwise book list are persisted locally (Core Data, SwiftData, or a JSON file — implementer's choice).

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
- Invalid Readwise key → block submission, prompt the user to update the key in Settings.
- Provider returns an empty highlights array → still proceed to Review with empty text and a small notice ("No highlight detected — type the passage manually").
- Network failure on Readwise submit → stay on Review with retry; no automatic background queue in v1.
- Camera permission denied → show explanation with a "Open Settings" deep link.

## API integrations

- **Gemini**: `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent` with the user's API key (`x-goog-api-key` header). Multimodal request with the captured image plus instruction prompt and JSON schema (`generationConfig.responseSchema`).
- **Claude**: `https://api.anthropic.com/v1/messages` with the user's API key (`x-api-key` header) and the `anthropic-version: 2023-06-01` header. Multimodal request with `image` content blocks plus the instruction prompt as the `system` field. Structured output is enforced via a single tool (`report_highlights`) with `tool_choice: {type: "tool", name: "report_highlights"}`; the response's `tool_use` block carries the highlights JSON.
- **Readwise**:
  - `GET /api/v2/books/?category=books` — list user's books.
  - `POST /api/v2/highlights/` — create highlight(s).
  - `GET /api/v2/auth/` — validate token.
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
- iPad layout, macOS Catalyst.
- Sync of cached book list across devices.
- Bulk import (multi-photo capture session).
