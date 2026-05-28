import XCTest
@testable import NotaBene

final class HighlightSubmitterTests: XCTestCase {
    private func makeBook(id: String = "b1") -> Book {
        Book(id: id, title: "On Writing", author: "Stephen King", source: .manual)
    }

    private func makeHighlights() -> [HighlightDraft] {
        [
            HighlightDraft(text: "Adverbs are not your friend.", pageNumber: 124, note: nil),
            HighlightDraft(text: "Write with the door closed.", pageNumber: nil, note: "Drafting")
        ]
    }

    // MARK: HighlightSubmitter.submit

    func test_submit_emptyDestinations_returnsEmptyResult() async {
        let result = await HighlightSubmitter.submit(
            book: makeBook(),
            highlights: makeHighlights(),
            destinations: []
        )
        XCTAssertTrue(result.isAllSuccess)
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func test_submit_allSucceed_returnsAllTargets() async {
        let readwise = StubDestination(target: .readwise)
        let notion = StubDestination(target: .notion)
        let result = await HighlightSubmitter.submit(
            book: makeBook(),
            highlights: makeHighlights(),
            destinations: [readwise, notion]
        )
        XCTAssertTrue(result.isAllSuccess)
        XCTAssertEqual(result.succeeded, [.readwise, .notion])
        XCTAssertTrue(result.failures.isEmpty)
        let rwCalls = await readwise.calls
        let nCalls = await notion.calls
        XCTAssertEqual(rwCalls.count, 1)
        XCTAssertEqual(nCalls.count, 1)
        XCTAssertEqual(rwCalls.first?.book.id, "b1")
        XCTAssertEqual(rwCalls.first?.highlights.count, 2)
    }

    func test_submit_allFail_returnsOnlyFailures() async {
        let readwise = StubDestination(target: .readwise, error: ReadwiseError.invalidToken)
        let notion = StubDestination(target: .notion, error: NotionError.invalidToken)
        let result = await HighlightSubmitter.submit(
            book: makeBook(),
            highlights: makeHighlights(),
            destinations: [readwise, notion]
        )
        XCTAssertFalse(result.isAllSuccess)
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.failures.count, 2)
        let byTarget = Dictionary(uniqueKeysWithValues: result.failures.map { ($0.target, $0.message) })
        XCTAssertEqual(byTarget[.readwise], "Readwise token rejected — update it in Settings.")
        XCTAssertEqual(byTarget[.notion], "Notion access expired — reconnect in Settings.")
    }

    func test_submit_partialFailure_reportsBoth() async {
        let readwise = StubDestination(target: .readwise)
        let notion = StubDestination(
            target: .notion,
            error: NotionError.requestFailed(status: 502, body: "")
        )
        let result = await HighlightSubmitter.submit(
            book: makeBook(),
            highlights: makeHighlights(),
            destinations: [readwise, notion]
        )
        XCTAssertFalse(result.isAllSuccess)
        XCTAssertEqual(result.succeeded, [.readwise])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.target, .notion)
        XCTAssertEqual(result.failures.first?.message, "Notion returned HTTP 502.")
    }

    func test_submit_runsDestinationsInParallel() async {
        let readwise = StubDestination(target: .readwise, delayNanoseconds: 200_000_000)
        let notion = StubDestination(target: .notion, delayNanoseconds: 200_000_000)
        let start = Date()
        let result = await HighlightSubmitter.submit(
            book: makeBook(),
            highlights: makeHighlights(),
            destinations: [readwise, notion]
        )
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(result.isAllSuccess)
        // 2 destinations × 200ms sequentially would be ~400ms.
        // Parallel should be ~200ms; allow generous headroom for CI.
        XCTAssertLessThan(elapsed, 0.35, "destinations should run in parallel; elapsed=\(elapsed)")
    }

    // MARK: HighlightSubmitter.message formatting

    func test_message_readwiseInvalidToken() {
        let m = HighlightSubmitter.message(
            for: ReadwiseError.invalidToken,
            target: .readwise,
            includeBody: true
        )
        XCTAssertEqual(m, "Readwise token rejected — update it in Settings.")
    }

    func test_message_readwiseRequestFailed_omitsBodyWhenDebugOff() {
        let m = HighlightSubmitter.message(
            for: ReadwiseError.requestFailed(status: 500, body: "ouch"),
            target: .readwise,
            includeBody: false
        )
        XCTAssertEqual(m, "Readwise returned HTTP 500.")
    }

    func test_message_readwiseRequestFailed_appendsBodyWhenDebugOn() {
        let m = HighlightSubmitter.message(
            for: ReadwiseError.requestFailed(status: 500, body: "ouch"),
            target: .readwise,
            includeBody: true
        )
        XCTAssertEqual(m, "Readwise returned HTTP 500.\n\nouch")
    }

    func test_message_readwiseRequestFailed_skipsEmptyBodyEvenWhenDebugOn() {
        let m = HighlightSubmitter.message(
            for: ReadwiseError.requestFailed(status: 500, body: ""),
            target: .readwise,
            includeBody: true
        )
        XCTAssertEqual(m, "Readwise returned HTTP 500.")
    }

    func test_message_notionInvalidToken() {
        let m = HighlightSubmitter.message(
            for: NotionError.invalidToken,
            target: .notion,
            includeBody: false
        )
        XCTAssertEqual(m, "Notion access expired — reconnect in Settings.")
    }

    func test_message_notionRequestFailed_appendsBodyWhenDebugOn() {
        let m = HighlightSubmitter.message(
            for: NotionError.requestFailed(status: 429, body: "rate limited"),
            target: .notion,
            includeBody: true
        )
        XCTAssertEqual(m, "Notion returned HTTP 429.\n\nrate limited")
    }

    func test_message_notionRequestFailed_omitsBodyWhenDebugOff() {
        let m = HighlightSubmitter.message(
            for: NotionError.requestFailed(status: 429, body: "rate limited"),
            target: .notion,
            includeBody: false
        )
        XCTAssertEqual(m, "Notion returned HTTP 429.")
    }

    func test_message_notionDecoding() {
        let m = HighlightSubmitter.message(
            for: NotionError.decoding(reason: "missing id", payload: "{}"),
            target: .notion,
            includeBody: false
        )
        XCTAssertEqual(m, "Couldn't parse Notion response: missing id")
    }

    func test_message_defaultUsesTargetLabelAndLocalizedDescription() {
        struct DummyError: LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let m = HighlightSubmitter.message(
            for: DummyError(),
            target: .readwise,
            includeBody: false
        )
        XCTAssertEqual(m, "Readwise error: boom")
    }

    // MARK: NotionBookPageCache

    func test_notionBookPageCache_lookupReturnsNilWhenAbsent() async {
        let cache = NotionBookPageCache()
        let result = await cache.lookup(bookID: "missing")
        XCTAssertNil(result)
    }

    func test_notionBookPageCache_storeAndLookupRoundtrip() async {
        let cache = NotionBookPageCache()
        await cache.store(pageID: "page-1", bookID: "book-1")
        let result = await cache.lookup(bookID: "book-1")
        XCTAssertEqual(result, "page-1")
    }

    func test_notionBookPageCache_storeOverwrites() async {
        let cache = NotionBookPageCache(initial: ["book-1": "page-old"])
        await cache.store(pageID: "page-new", bookID: "book-1")
        let snap = await cache.snapshot()
        XCTAssertEqual(snap["book-1"], "page-new")
    }

    func test_notionBookPageCache_seedsFromInitial() async {
        let cache = NotionBookPageCache(initial: ["b1": "p1", "b2": "p2"])
        let snap = await cache.snapshot()
        XCTAssertEqual(snap, ["b1": "p1", "b2": "p2"])
    }

    // MARK: NotionDestination cache integration

    func test_notionDestination_usesCachedPageID_andSkipsFindOrCreate() async throws {
        let book = makeBook(id: "cached-book")
        let cache = NotionBookPageCache(initial: ["cached-book": "page-cached"])
        let mock = MockHTTPClient { req in
            // Should only see a PATCH to /v1/blocks/{pageID}/children — no find-or-create round-trip.
            XCTAssertEqual(req.httpMethod, "PATCH")
            XCTAssertEqual(req.url?.path, "/v1/blocks/page-cached/children")
            return MockHTTPClient.ok(Data("{}".utf8))
        }
        let client = NotionClient(token: "tok", http: mock, baseURL: URL(string: "https://api.notion.com")!)
        let dest = NotionDestination(client: client, parentPageID: "parent", cache: cache)
        try await dest.submit(book: book, highlights: makeHighlights())
        XCTAssertEqual(mock.requests.count, 1, "cached pageID should skip find-or-create")
    }

    func test_notionDestination_findOrCreate_storesPageIDIntoCache() async throws {
        let book = makeBook(id: "fresh-book")
        let cache = NotionBookPageCache()

        let listJSON = """
        {"results": [], "has_more": false, "next_cursor": null}
        """.data(using: .utf8)!
        let createJSON = """
        {"id": "page-new"}
        """.data(using: .utf8)!

        var step = 0
        let mock = MockHTTPClient { req in
            defer { step += 1 }
            switch step {
            case 0:
                // GET children of parent
                XCTAssertEqual(req.url?.path, "/v1/blocks/parent/children")
                return MockHTTPClient.ok(listJSON)
            case 1:
                // POST /v1/pages (create)
                XCTAssertEqual(req.httpMethod, "POST")
                XCTAssertEqual(req.url?.path, "/v1/pages")
                return MockHTTPClient.ok(createJSON)
            case 2:
                // PATCH highlights to the newly-created page
                XCTAssertEqual(req.httpMethod, "PATCH")
                XCTAssertEqual(req.url?.path, "/v1/blocks/page-new/children")
                return MockHTTPClient.ok(Data("{}".utf8))
            default:
                XCTFail("unexpected extra request at step \(step)")
                return MockHTTPClient.ok(Data())
            }
        }
        let client = NotionClient(token: "tok", http: mock, baseURL: URL(string: "https://api.notion.com")!)
        let dest = NotionDestination(client: client, parentPageID: "parent", cache: cache)
        try await dest.submit(book: book, highlights: makeHighlights())

        XCTAssertEqual(mock.requests.count, 3)
        let cached = await cache.lookup(bookID: "fresh-book")
        XCTAssertEqual(cached, "page-new", "destination should cache the page id after creation")
    }

    func test_notionDestination_findOrCreate_secondSubmitUsesCache() async throws {
        let book = makeBook(id: "warm-book")
        let cache = NotionBookPageCache()

        let listJSON = """
        {"results": [], "has_more": false, "next_cursor": null}
        """.data(using: .utf8)!
        let createJSON = """
        {"id": "page-warm"}
        """.data(using: .utf8)!

        var step = 0
        let mock = MockHTTPClient { req in
            defer { step += 1 }
            switch step {
            case 0: return MockHTTPClient.ok(listJSON)        // initial find (empty)
            case 1: return MockHTTPClient.ok(createJSON)      // create page
            case 2: return MockHTTPClient.ok(Data("{}".utf8)) // append #1
            case 3:
                // Second submit: should go straight to PATCH on the cached page id.
                XCTAssertEqual(req.httpMethod, "PATCH")
                XCTAssertEqual(req.url?.path, "/v1/blocks/page-warm/children")
                return MockHTTPClient.ok(Data("{}".utf8))
            default:
                XCTFail("unexpected request at step \(step)")
                return MockHTTPClient.ok(Data())
            }
        }
        let client = NotionClient(token: "tok", http: mock, baseURL: URL(string: "https://api.notion.com")!)
        let dest = NotionDestination(client: client, parentPageID: "parent", cache: cache)
        try await dest.submit(book: book, highlights: makeHighlights())
        try await dest.submit(book: book, highlights: makeHighlights())
        XCTAssertEqual(mock.requests.count, 4, "second submit should reuse cached page id")
    }

    // MARK: ReadwiseDestination integration

    func test_readwiseDestination_postsHighlightsThroughClient() async throws {
        let mock = MockHTTPClient { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.absoluteString, "https://readwise.io/api/v2/highlights/")
            return MockHTTPClient.ok(Data("{}".utf8))
        }
        let client = ReadwiseClient(token: "rw", http: mock, baseURL: URL(string: "https://readwise.io")!)
        let dest = ReadwiseDestination(client: client)
        try await dest.submit(book: makeBook(), highlights: makeHighlights())
        XCTAssertEqual(mock.requests.count, 1)
    }
}

// MARK: - Test stubs

private actor StubDestination: HighlightDestination {
    nonisolated let target: ExportTarget
    private let error: Error?
    private let delayNanoseconds: UInt64
    private(set) var calls: [(book: Book, highlights: [HighlightDraft])] = []

    init(target: ExportTarget, error: Error? = nil, delayNanoseconds: UInt64 = 0) {
        self.target = target
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func submit(book: Book, highlights: [HighlightDraft]) async throws {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        calls.append((book, highlights))
        if let error { throw error }
    }
}
