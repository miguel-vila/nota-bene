# iPhone App Spec — Readwise Physical Highlight Capture

## Overview

A native iPhone app that turns highlighted passages in physical books into Readwise highlights. The user selects a book, photographs a highlighted passage, lets a vision LLM extract the text and (optionally) the page number, reviews/edits the result, and submits it to Readwise.

## First-launch setup

- On first launch, the user is prompted to paste:
  - Gemini API key
  - Readwise API key
- Both keys are required before the app becomes usable.
- Keys are stored in the iOS Keychain (not UserDefaults).
- A Settings screen allows the user to view (masked), replace, or clear either key.
- Settings includes a "Test connection" action for each key:
  - Gemini: a minimal text-only request.
  - Readwise: `GET /api/v2/auth/`.

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
- Capture button takes a still photo.
- Alternative: a "Pick from library" button to choose an existing photo (e.g. one taken earlier offline).
- After capture, a preview screen with three actions:
  - Retake → discard captured pages and return to camera.
  - Turn page → keep the captured page(s) and return to camera to capture the next page (for highlights that span a page break). Capped at 2 pages per submission.
  - Use photo(s) → go to Extraction with all captured pages.

### 3. Extraction

- The captured image(s) are sent to the Gemini API (multimodal model, e.g. `gemini-2.5-flash` for speed; configurable) in a single request — multiple page images are passed as separate `inline_data` parts in reading order, so the model can natively merge a highlight that wraps across the page break instead of forcing the client to stitch.
- The request uses structured output (JSON schema) and returns an array of highlights, each with:
  - `text` (string): the text marked with highlighter, pen, pencil, bracket, or underline. Verbatim, preserving punctuation.
  - `page_number` (integer | null): the page number visible in the photo, if any.
- A single photo may contain multiple distinct highlighted passages — the model returns each as a separate entry in reading order. An empty array means no highlight was detected.
- The prompt instructs the model to:
  - Return only the marked passages, not the surrounding unmarked text.
  - Preserve original line wrapping as spaces (no hyphenation artifacts).
  - Return `null` for `page_number` if no page number is visible or unambiguous.
  - When multiple page images are provided, treat them as consecutive pages and merge any passage that continues across the page break into a single entry.
- A loading indicator is shown while the request is in flight.
- Failures (network, invalid key, model error) show an error with a Retry action and a "Skip extraction, type manually" action that takes the user to Review with empty fields.

### 4. Review

- One editable group per detected highlight, each with:
  - **Text** (multiline): pre-filled, editable.
  - **Page number** (numeric): pre-filled if detected, editable.
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
        "location_type": "page"
      }
    ]
  }
  ```

- On success: brief confirmation, then return to the Capture screen with the same book still selected (so consecutive highlights from the same book require no re-selection).
- On failure: keep the user on the Review screen, show the error, allow retry. Do not lose the edited text.

## Navigation

- Tab-less, single stack.
- Top-level: Book selection.
- Push: Capture → Preview → Review → (success) → Capture (same book).
- A "Change book" affordance is available from Capture and Review.
- Settings is accessible from the Book selection screen via a gear icon.

## Data model

- `Book`: `{ id, title, author?, source: "readwise" | "open_library" | "manual", lastUsedAt, coverURL? }`
- `PendingHighlight` (in-memory only during a session): `{ book, images: [Data], highlights: [{ text, pageNumber? }] }`
- Recently used books and the cached Readwise book list are persisted locally (Core Data, SwiftData, or a JSON file — implementer's choice).

## Error handling

- Invalid Gemini key → block extraction, prompt the user to update the key in Settings.
- Invalid Readwise key → block submission, prompt the user to update the key in Settings.
- Gemini returns empty `highlighted_text` → still proceed to Review with empty text and a small notice ("No highlight detected — type the passage manually").
- Network failure on Readwise submit → stay on Review with retry; no automatic background queue in v1.
- Camera permission denied → show explanation with a "Open Settings" deep link.

## API integrations

- **Gemini**: `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent` with the user's API key. Multimodal request with the captured image plus instruction prompt and JSON schema.
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
- **Recommendation: skip the SDKs and call the Gemini REST endpoint directly via URLSession.** The app makes exactly one kind of call (multimodal + structured JSON output). A direct REST client is ~50 lines of Swift, has zero dependency risk, and will not be invalidated by future Google SDK reorganizations. Wrap it in a `GeminiClient` actor with one method: `extractHighlights(fromImages: [Data]) async throws -> ExtractionResult`.

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
