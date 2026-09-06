## Sub-spec — Eval Capture (experimental)

> Status: draft. Debug/experimental feature for building an offline eval dataset from real captures. Not user-facing — intended for the developer (Miguel) to dogfood and collect labeled samples for prompt/model regression testing.

### Purpose

Every successful Extraction round-trip pairs a real-world photo with a real model response. Today that pair is thrown away the moment Review opens. This feature lets the developer **curate** those pairs — after seeing the extraction result on the Review screen, decide per capture whether to keep it — persists the kept ones to disk, then ships them off-device as a single archive so they can be labeled and turned into an eval set in a separate tool.

### Non-goals

- No in-app labeling UI. Labels are produced off-device after export.
- No automatic upload — the export is a manual share-sheet action only. The dataset never leaves the device unless the developer explicitly shares it.
- No scoring, diffing, or replay against past samples in-app. That belongs in the off-device eval harness.
- Not shippable to end users. The flag is intentionally only reachable in development builds (see "Enablement").

### Enablement

The eval-capture code path is gated by the standard **`#if DEBUG`** compilation condition. Xcode and SwiftPM define `DEBUG` automatically in their Debug configuration; Release/Archive builds drop it. The entire feature (toggle UI, badge view, `EvalSampleWriter`, integration call) is wrapped in `#if DEBUG` and there is no fallback in Release.

This is the iOS convention and removes the need for any custom flag, manual Xcode setting, project.yml plumbing, or CI guard. Build & Run from Xcode (Debug by default) lights the feature up; Archive / TestFlight / App Store builds drop it on the floor.

In DEBUG builds, Settings grows a new **"Developer"** section with a **master enable**:

- **Capture eval samples** — off by default. Persisted in `UserDefaults` under `evalCaptureEnabled`. Survives relaunches but reverts to off if you reinstall.

This master flag does **not** itself write anything. It is a *feature-available* switch: when on, it surfaces a per-capture **"Save eval sample"** toggle on the Review screen (and the `REC · EVAL` badge once that per-capture toggle is on). The actual per-capture decision — and the disk write — happens there, on Save. See "What a sample is" below.

The per-capture choice is a separate piece of state, `AppState.evalRecordThisCapture`: **session-only** (deliberately *not* `UserDefaults`-backed), so it resets to off on every cold launch and can never silently resurrect a weeks-old "on" that quietly accumulates samples. Within a session it is remembered ("remember last") so a multi-capture collection run doesn't re-toggle every time.

Toggling the master flag off mid-session stops new writes immediately — the write is gated on the master key, not just the per-capture toggle's visibility, so a stale per-capture "on" cannot keep writing after the feature is disabled. Previously written samples are kept until the developer clears them.

The Developer section surfaces two adjacent actions. Both are **always visible** (even when zero samples exist) so the developer can tell at a glance whether nothing has been written yet vs. whether writes are silently failing:

- **Export samples** — see "Export" below. Disabled with subtitle "No samples yet" when count is 0.
- **Clear samples** — destructive, confirmation alert, wipes the `EvalSamples/` directory. Disabled when count is 0.

A subtitle under the toggle shows `N samples · ~X.X MB on disk` and the **timestamp of the last write attempt** (success or failure). A failed last write surfaces the error message in red so the developer doesn't silently lose collection runs.

Rationale for compile-time gating over a hidden release flag: the dataset is a dev tool, not a user feature. There is no use case for flipping it on for a user we shipped to. Compile-time gating also keeps the photo-storage code path out of the release binary entirely, so there is nothing to misconfigure into existence at runtime.

### Visual cue while capturing

An `EvalRecordingBadge` is shown on **every screen in the capture flow** — Camera, Preview, Extracting, Review, and Saved — while an eval-recording streak is active, i.e. `evalCaptureEnabled && AppState.evalRecordThisCapture`. Because the per-capture choice is remembered within a session, once the developer opts a capture in, the badge surfaces from the *next* capture's Camera screen onward (including the Photos-picker path, which skips Camera), making the recording state impossible to miss before any sample is written. On the very first capture of a session — before any opt-in — the badge stays hidden until the developer flips the Review toggle. Specifications:

- Position: **top-right** of the screen, away from both the `PAGE N / 2` chip in the top-left and the instructional text pinned near the bottom of the camera viewport. (Bottom-left, as originally drafted, collided with both on small devices.)
- Label: `REC · EVAL` in the same mono caption style as `PAGE N / 2`.
- Color: red dot + white text on a translucent dark capsule, matching the existing chip aesthetic.
- Behavior: static (no pulse/animation). Hidden whenever the master flag is off *or* the per-capture toggle is off. The badge view itself is wrapped in `#if DEBUG`, so it cannot render in Release builds.

The Review screen carries the actual control: a **"Save eval sample"** toggle pinned in the save bar, just above the Save button (always visible, no scrolling). It is shown only when `evalCaptureEnabled && pendingEvalTrace != nil` — so it's hidden on the "Type manually" / skip path, which has no extraction to record — and binds to `AppState.evalRecordThisCapture`.

(The earlier draft's persistent red banner in Settings — "Eval capture is ON — every successful extraction will be saved" — is **retired**: it is no longer true that enabling the master flag saves anything. The toggle subtitle now explains the per-capture flow instead.)

### What a sample is

A single sample corresponds to one **Extraction round-trip**: the set of images sent in one model request plus the model's parsed/raw response. Extraction runs once between Preview ("Use photo(s)") and Review, so each capture flow that reaches Review *can* produce at most one sample — but only if the developer opts in.

The extraction trace is held on the flow (`CaptureFlow.pendingEvalTrace`, DEBUG-only) when extraction succeeds; nothing is written yet. The sample is written **on the Review screen, when the developer taps Save**, from the top of `CaptureFlowContainer.submit()` — *before* the export-target checks, so the sample is captured on Save intent even if the export target is misconfigured, and **independently of whether the Readwise/Notion submit then succeeds**. `flow.images` are still present at that point (only `markSaved` clears them). This means:

- If extraction throws (network, invalid key, parse failure), no trace is held and nothing is written — failures are intentionally out of scope (see "Failures" below).
- If extraction returns an **empty** `highlights` array (the model saw no marked passages), a trace is still held and the sample **is** written if the developer opts in. An empty result is a real model output worth evaluating — it tells the eval whether the model missed real highlights.
- What is recorded is the **raw model output + images only** — the `sample.json` schema is unchanged (`schema_version: 1`). The developer's edits to the highlights in Review are **not** captured. The eval is about model quality, not user corrections; capturing edited highlights as ground-truth labels is explicitly out of scope.

The write gate, evaluated on Save, is exactly:

```
evalCaptureEnabled && AppState.evalRecordThisCapture && flow.pendingEvalTrace != nil && !flow.didWriteEvalSample
```

(implemented as the pure `CaptureFlow.shouldWriteEvalSample(...)` so it is unit-testable).

- The **master key** (`evalCaptureEnabled`) is part of the gate, not just the toggle's visibility — a stale per-capture "on" must stop writing the instant the feature is disabled in Settings.
- **At most once per capture:** `flow.didWriteEvalSample` (set only on a *successful* write) guards against duplicates. A failed Readwise/Notion submit returns to Review and Save can be re-tapped; the second tap will not write a second sample. A failed *write* (rare — disk/template error) leaves the flag off so the next Save tap retries.
- Both `pendingEvalTrace` and `didWriteEvalSample` are cleared by `CaptureFlow.reset()` and `markSaved()`, so a new capture starts clean. `evalRecordThisCapture` is **not** reset per capture — that is the "remember last" behavior; it only resets on cold launch.

### On-disk layout

Samples live in the app's Documents directory so they're visible to Finder/Files:

```
<Documents>/EvalSamples/
  request_templates/
    claude-single-v3.json
    claude-multi-v3.json
    claude-multi-v4.json       # appears when the multi prompt or tool schema is bumped to v4
    gemini-single-v3.json
    gemini-multi-v3.json
  20260531T142233Z_a3f9c102e8f1/
    image_1.jpg
    sample.json
  20260531T143010Z_b7e2d44f9c33/
    image_1.heic               # Photos-picker import; raw bytes are HEIC, not JPEG
    image_2.heic
    sample.json
```

- **Folder name** is `YYYYMMDDTHHMMSSZ_<12-hex-suffix>` (e.g. `20260531T142233Z_a3f9c102e8f1/`). Sortable. The 12-hex suffix is the first 48 bits of a fresh UUID; collision-free in practice for any single-developer dataset. (The earlier 8-char draft was not actually collision-proof at large N — bumped to 12.)
- **Images** are written as the **exact bytes the app sent to the model**, with no re-encoding or orientation correction. The file extension matches the sniffed image format (`.jpg` for JPEG-magic bytes, `.heic` for HEIC, `.png` for PNG). The Photos picker can hand back HEIC/PNG that the current app forwards verbatim to the provider while claiming `image/jpeg` in the request — saving the raw bytes (and recording both the actual format and the claimed MIME in `sample.json`, see schema below) lets the eval surface that mismatch instead of hiding it.
- **`request_templates/`** is a top-level directory containing one file per `(provider, variant, version)` tuple that has been written by any sample currently on disk. Each file is JSON and carries the **provider-specific, non-image, non-key parts of the model request** — system prompt, user-text instruction, tool/response schema, etc. — *not* just the prompt string. Saving only the prompt would mis-label what the eval is evaluating, since the tool definition (Claude) and response schema (Gemini) are part of what the model "sees."
  - **`claude-<variant>-<version>.json`** contains: `{ "system": <ExtractionPrompts.{single,multi}PagePrompt>, "user_text_instruction": <the "Extract the highlighted passages…" trailer from ClaudeClient.makeBody>, "tool_name": "report_highlights", "tool_description": <verbatim from makeBody>, "tool_input_schema": <ClaudeHighlightSchema.inputSchema>, "tool_choice": {"type":"tool","name":"report_highlights"}, "max_tokens": 4096, "anthropic_version": "2023-06-01" }`.
  - **`gemini-<variant>-<version>.json`** contains: `{ "instruction": <ExtractionPrompts.{single,multi}PagePrompt>, "response_mime_type": "application/json", "response_schema": <the responseSchema literal from GeminiClient.makeBody> }`.
- Each `sample.json` references its template by relative path (`"request_template": "request_templates/claude-multi-v4.json"`). Multiple samples sharing the same `(provider, variant, version)` share one file. When the template content changes, the version is bumped and a new file is added; **old files are never overwritten**.
- **Versions are per-variant, not global.** `ExtractionPrompts` exposes two constants — `singleExtractionVersion` and `multiExtractionVersion` — bumped independently whenever the corresponding prompt text, any interpolated guidance constant it uses, the tool/response schema, or any other field stored in the template changes. A multi-prompt edit does not churn the single version. (The earlier single-global-version draft was inconsistent with this layout.)
- **Writer hash-check prevents stale templates.** Before writing a sample, `EvalSampleWriter` builds the in-memory template object for the current `(provider, variant, version)`. If `request_templates/<provider>-<variant>-<version>.json` already exists, the writer loads it, canonical-JSON-serializes both objects, and compares SHA-256. **On mismatch, the writer `preconditionFailure`s with a message naming the file** ("eval-capture: in-memory request template for claude-multi-v3 differs from on-disk file; bump `multiExtractionVersion` in ExtractionPrompts.swift"). This makes "forgot to bump the version" a loud crash in Debug builds, not silent corruption. On hit, the writer leaves the file alone. On miss, it writes the new template.
- All writes (samples, templates, images) use **atomic temp-then-rename**: write to `EvalSamples/.in_progress/<sample_id>/...`, fsync, then `rename` the directory into place. Partial writes from crash/kill/low-disk leave the staging directory alone, which is cleaned up on writer init.

`sample.json` schema:

```json
{
  "schema_version": 1,
  "sample_id": "20260531T142233Z_a3f9c102e8f1",
  "captured_at": "2026-05-31T14:22:33Z",
  "request_template": "request_templates/claude-multi-v4.json",
  "photos": ["image_1.jpg", "image_2.jpg"],
  "provider": "claude",
  "model": "claude-sonnet-4-6",
  "app": {
    "version": "1.4.0",
    "build": "142",
    "platform": "iOS 17.5",
    "device_model": "iPhone15,2"
  },
  "book": {
    "title": "The Idea of the Brain",
    "author": "Matthew Cobb",
    "source": "readwise"
  },
  "response": {
    "parsed": {
      "highlights": [
        { "text": "...", "page_number": 42, "note": null }
      ]
    },
    "raw": "<provider's raw response body, verbatim>",
    "latency_ms": 1842
  },
  "photo_meta": [
    {
      "file": "image_1.jpg",
      "bytes": 184221,
      "width": 3024,
      "height": 4032,
      "detected_format": "jpeg",
      "request_mime": "image/jpeg"
    },
    {
      "file": "image_2.jpg",
      "bytes": 192334,
      "width": 3024,
      "height": 4032,
      "detected_format": "jpeg",
      "request_mime": "image/jpeg"
    }
  ]
}
```

Notes on the schema:

- `schema_version` starts at `1`. Bump on any breaking shape change; the off-device harness branches on it.
- `request_template` is the relative path to the per-`(provider, variant, version)` file under `request_templates/`. The filename encodes provider + variant + version so the eval harness can group samples without re-reading the file.
- `photos` lists image filenames in the order sent to the model. Each entry in `photo_meta` reports the **on-disk format** (`detected_format`, from magic-byte sniffing) and the **MIME string the request actually sent** (`request_mime`, currently always `"image/jpeg"` from a hardcode in `CaptureView.swift`). When these disagree, the eval can see "the model received HEIC bytes labeled as JPEG" — a real bug in the current app the eval will help surface, not paper over.
- `response.raw` is the provider's untouched response body string (UTF-8). For Claude this is the JSON body containing the `tool_use` block; for Gemini it's the `candidates`-shaped body. This is what lets the eval harness re-parse later if the parser changes, or diagnose model-side regressions.
- `response.parsed` is the `ExtractionResult` after the app's parser ran, encoded with the same `CodingKeys` already used by `ExtractionResult`. **Caveat:** the current parsers (`ClaudeClient.parseResponse`, `GeminiClient.parseResponse`) silently drop malformed highlight items via `compactMap`. The eval should treat `response.parsed` as "what the app surfaced to the user," not "what the model returned" — the latter requires re-parsing `response.raw`. The off-device harness is free to do that.
- `book.title` is always present; `book.author` is the JSON string `null` when absent (matching `Book.author: String?`). The key is always written, never omitted, so the harness has a stable shape.
- `book.source` reuses `Book.source` (`"readwise"` / `"open_library"` / `"manual"`). Useful for slicing the dataset later.
- No API keys, OAuth tokens, `NotionConnection`, or any Readwise-specific user IDs appear anywhere in the sample.

Reproducibility unit: a single sample folder is **not** self-contained on its own — it references a sibling `request_templates/<...>.json`. The reproducible units are (a) the whole `EvalSamples/` directory and (b) the exported zip; both always carry the templates dir. **Files-app caveat:** see "Resolved design calls" below — deleting individual files from inside `request_templates/` will unmoor any sample that referenced them. Delete sample folders, not template files.

### Failures

Failed extractions are skipped on purpose. The eval is about **model quality on content** — given pages with marked passages, does the model recover them. Failure modes fall into two buckets:

- **Network / auth / server errors** (invalid key, 5xx, timeouts). These are infrastructure, not model output. They don't belong in a model-eval dataset; observing them would only measure cell reception. Skip.
- **Content-driven model failures** (refusal, malformed JSON, content the parser can't read). In practice these are vanishingly rare for this workload — the model returns an empty `highlights` array when it sees no marks, which is captured as a successful sample (see "What a sample is"). The expected mode for "model couldn't find anything" is empty-array success, not a thrown error.

If a future eval wants to investigate genuine content-driven failures (model returns garbage on a specific page type, parser rejects valid output), a separate `EvalFailures/` directory with `error.json` + the request payload is a clean extension. Out of scope for v1.

### Export

Settings → Developer → **Export samples**:

1. Snapshot the writer state (hold a lightweight read lock so no new sample folder is renamed-into-place mid-zip — the writer's atomic rename gives us a clean boundary), then zip the entire `EvalSamples/` directory into a temporary file `eval-samples-<ISO8601-UTC>.zip` in `NSTemporaryDirectory()`.
2. Present a `UIActivityViewController` over Settings with the zip as its only item. AirDrop, Files, Google Drive, Mail are all free for the developer to pick.
3. After dismissal, delete the temporary zip. The on-disk `EvalSamples/` is kept; the developer has to explicitly tap **Clear samples** to wipe the source.

The zip implementation is `ZIPFoundation` (see Integration points for the dependency decision and how it's kept out of release builds). USB-pull-via-Finder is also available, scoped to the dev Debug configuration only via the `INFOPLIST_KEY_*` overrides in `project.yml`.

### Storage hygiene

- No size cap or retention policy in v1. The flag is opt-in and the developer is expected to clear after each export. Sample folders are ~0.5–2 MB each (two JPEGs + JSON); a long reading weekend producing 200 samples runs ~200–400 MB. Worth eyeballing but not worth a v1 cap.
- Sample count + total size + last-write status are always visible in the Settings → Developer section (see Enablement). The count refreshes when Settings appears and also when the writer completes a write while Settings is on screen, so the footer doesn't go stale during a multi-capture session.
- `EvalSamples/` itself lives inside the app sandbox and cannot be committed to git directly. The realistic accidental-commit paths are (a) exported zips dragged into the repo and (b) directories copied out via Finder. Add `eval-samples-*.zip` and `EvalSamples/` to the repo `.gitignore` as a safety net for both.

### Privacy & safety

The protections, in order of how much they actually buy:

1. **Compile-time gating via `#if DEBUG`.** Xcode and SwiftPM set `DEBUG` automatically in the Debug configuration; Release/Archive builds drop it. The entire feature — toggle, badge, writer, dependency import — is absent from release binaries.
2. **No background upload, no analytics, no telemetry.** The dataset only leaves the device when the developer physically taps **Export samples** and chooses a destination in the share sheet, or pulls the directory over USB via Finder. The writer never touches the network.
3. **`EvalSamples/` excluded from iCloud backup.** The writer sets `isExcludedFromBackupKey` on the root directory at init, so an inadvertently-enabled iCloud Drive doesn't sync book photos off-device.

What the samples actually contain — stated honestly so the dataset is treated with appropriate care:

- **Photos of physical book pages.** These can include handwritten marginalia, the reader's notes, names, library stamps, ownership inscriptions, bookmarks, and incidental items in the camera frame. They are personal data even though they look like "just book pages."
- **Book metadata** (title, author, source). Combined with the timestamps these reveal reading habits.
- **Device model and iOS version**, included for cohorting eval results across devices. These are not strong identifiers on their own but become one when joined with the photos.
- **Capture timestamps** (ISO 8601 UTC, per-sample).
- **Model latency and provider/model id** — useful for eval, harmless on their own.

What samples explicitly do **not** contain: API keys for any provider, the Readwise token, the Notion OAuth access token, the Notion `botID` / `workspaceID`, the `NotionConnection.bookPageCache`, the user's Readwise book IDs, or any push/device tokens. These are never serialized by the writer.

Treat an exported zip as personal data on par with a folder of photos pulled off the device. If it ends up in a shared Drive, it's shared. If it ends up in a screenshot of the eval harness, it's leaked. The safety story is "small audience, explicit export," not "this is anonymized."

### Integration points (light implementation sketch)

So the spec is concrete enough to estimate against, the touch points are:

- **`HighlightExtractor` protocol — always-on richer return type.** The protocol's `extractHighlights(fromImages:mimeType:)` returns `ExtractionTrace { result: ExtractionResult, rawResponseBody: String, latencyMillis: Int, requestMime: String }` in all builds, not just Debug. Production code (`HighlightSubmitter` / `CaptureFlow`) ignores the trace fields and uses `.result`; the eval-capture call site reads them. This keeps a single API surface — a "DEBUG-only protocol fork" would have split production/test/eval behavior across the two clients, which is exactly the kind of compile-time multiverse that rots.
- **`ExtractionPrompts`** — adds per-variant version constants `singleExtractionVersion` / `multiExtractionVersion`, each a string (`"v3"`, `"v4"`, …) bumped manually whenever **any** field stored in the corresponding `request_templates/...json` file changes (prompt text, any guidance constant it interpolates, tool/response schema, user-text trailer, tool description, `max_tokens`). The writer's hash-check (see "On-disk layout") enforces this at runtime — a forgotten bump crashes with a clear message.
- **Extraction call site (`CaptureFlowContainer.runExtraction`)** — where extraction is invoked and the `ExtractionTrace` lands. On a successful trace it (wrapped in `#if DEBUG`) stores `flow.pendingEvalTrace = trace` and transitions to Review; it does **not** write. (`CaptureFlow` itself doesn't need provider / model / raw body in scope — the write call site reads those from `AppState`.)
- **Write call site (`CaptureFlowContainer.submit`)** — at the top of `submit()`, before the export-target checks, a `#if DEBUG` `maybeWriteEvalSample()` evaluates the gate (`CaptureFlow.shouldWriteEvalSample(...)`) and, if it passes, calls `EvalSampleWriter.writeSample(trace:, images:, provider:, model:, book:, …)` reading provider/model/book from `AppState` + `flow`. It marks `flow.didWriteEvalSample` on success. The write fires on Save intent, independently of the export submit's outcome.
- **`SettingsView.swift` / `SettingsDeveloperSection`** — `#if DEBUG` "Developer" section with the **master enable** toggle (subtitle explains the per-capture flow; the old red on/off banner is retired), always-visible sample count + size + last-write-status, **Export samples** (disabled at 0), **Clear samples** (disabled at 0).
- **`ReviewView`** — `#if DEBUG` "Save eval sample" toggle in the pinned save bar (above Save), shown only when `evalCaptureEnabled && pendingEvalTrace != nil`, bound to `AppState.evalRecordThisCapture`.
- **Capture-flow screens** — `EvalRecordingBadge` view rendered top-right on `CameraView`, `CapturePreview`, `Extracting`, `Review`, and `Saved` whenever `evalCaptureEnabled && AppState.evalRecordThisCapture`. View itself is wrapped in `#if DEBUG` so it can't exist in Release builds.
- **New file `Sources/NotaBene/Storage/EvalSampleWriter.swift`** — actor (entire file wrapped in `#if DEBUG`) that owns `EvalSamples/` and its `request_templates/` subdirectory: writes a sample atomically (temp dir + rename), creates the template file on first miss for a `(provider, variant, version)` triple, hash-checks on hit and `preconditionFailure`s on mismatch, lists samples, computes total size, clears, cleans up `.in_progress/` on init, and produces an export zip. Tags `EvalSamples/` as excluded from iCloud backup via `URLResourceKey.isExcludedFromBackupKey = true` so accidentally-on iCloud Drive doesn't sync book photos off-device.
- **`ZIPFoundation` dependency** — added to `Package.swift` as a Swift Package dependency, but the import + zip code lives inside `#if DEBUG`-wrapped files so the dep is dead-stripped from release builds. (The earlier "use Foundation directly" suggestion was hand-waving — Foundation has no first-party zip API outside `NSFileCoordinator`'s archive APIs, which are awkward and macOS-leaning. Pick `ZIPFoundation` outright.)

### Resolved design calls

- **Badge is static.** A still red dot + `REC · EVAL` label — no pulse or animation. Rationale: a real capture demands the developer's full attention on aligning the page; an animated badge in the corner would compete for that attention.
- **No Notion page id in samples.** Only model-input/output and book-identity fields appear in `sample.json`. The eval cares about model quality, not Notion routing — anything else is unnecessary leakage from one feature into another.
- **Files-app deletes are allowed, with one footgun.** Eval-capture builds keep `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` on (scoped to the dev Debug configuration only — see Integration points), which means `EvalSamples/` is browseable from Finder and the iOS Files app. The convenience of a Finder copy for bulk collection runs outweighs the fat-finger-delete risk on sample folders. **The one rule to remember:** delete sample folders (`20260531T142233Z_*/`), not files inside `request_templates/`. Deleting a template file unmoors any sample that referenced it — the eval harness can still load the sample's `response.raw` and `response.parsed` but no longer has the exact request shape the model saw. The in-app **Clear samples** button is all-or-nothing and stays consistent (clears both samples and templates together).
