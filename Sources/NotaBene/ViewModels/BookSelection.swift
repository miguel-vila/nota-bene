#if canImport(SwiftUI)
import Foundation
import SwiftUI

/// Everything the main (book selection) screen shows: the query, the two
/// result lists it produces, the recents list and the library-refresh error.
///
/// A trip into a book is a fresh start. `selectedBook` returning to `nil` —
/// how SwiftUI reports a pop out of the capture flow — drops the query and the
/// results it produced, so the user comes back to the recents list instead of
/// to the search they ran before. Holding that rule next to the state it
/// clears is what keeps a later addition from being left behind.
/// The cached library and any refresh error survive: they are not the user's
/// search. See spec.md "Book selection".
@MainActor
public final class BookSelection: ObservableObject {
    @Published public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    /// Bound to the screen's navigation destination: non-`nil` while the
    /// capture flow is pushed, set back to `nil` by SwiftUI on pop.
    @Published public var selectedBook: Book? {
        didSet {
            if let book = selectedBook {
                recordUsage(of: book)
            } else if oldValue != nil {
                clearSearch()
            }
        }
    }

    @Published public private(set) var recents: [Book] = []
    @Published public private(set) var libraryMatches: [Book] = []
    @Published public private(set) var openLibraryMatches: [Book] = []
    @Published public private(set) var isSearchingOpenLibrary = false
    @Published public private(set) var libraryError: String?

    private let bookStore: BookStore
    private let openLibrary: OpenLibraryClient
    private let readwiseClient: @MainActor () -> ReadwiseClient?
    private let libraryRefreshIntervalHours: Double
    private let searchDebounce: Duration
    private var isRefreshingLibrary = false

    /// Work started off a property change rather than awaited by a caller:
    /// the debounced search, and the recents write that a selection kicks off.
    /// Held so a later change can cancel the search, and so tests can await
    /// either one.
    private(set) var pendingSearch: Task<Void, Never>?
    private(set) var pendingRecentsWrite: Task<Void, Never>?

    public init(
        bookStore: BookStore,
        openLibrary: OpenLibraryClient,
        readwiseClient: @escaping @MainActor () -> ReadwiseClient?,
        libraryRefreshIntervalHours: Double = 12,
        searchDebounce: Duration = .milliseconds(300)
    ) {
        self.bookStore = bookStore
        self.openLibrary = openLibrary
        self.readwiseClient = readwiseClient
        self.libraryRefreshIntervalHours = libraryRefreshIntervalHours
        self.searchDebounce = searchDebounce
    }

    /// Show the cached recents, and pull the Readwise library when the cache is
    /// empty or past `libraryRefreshIntervalHours`.
    public func load() async {
        let cache = await bookStore.state
        recents = cache.recents
        if cache.library.isEmpty {
            await refreshLibrary(force: true)
        } else if await bookStore.libraryNeedsRefresh(maxAgeHours: libraryRefreshIntervalHours) {
            await refreshLibrary(force: false)
        }
    }

    /// `force` is the pull-to-refresh path: it overrides the guard that keeps a
    /// background refresh from stacking on one already running.
    public func refreshLibrary(force: Bool) async {
        guard let client = readwiseClient() else { return }
        if isRefreshingLibrary && !force { return }
        isRefreshingLibrary = true
        defer { isRefreshingLibrary = false }
        do {
            let books = try await client.listBooks()
            try await bookStore.setLibrary(books)
            libraryError = nil
            libraryMatches = BookSearch.filterLibrary(books, query: query)
        } catch ReadwiseError.invalidToken {
            libraryError = "Readwise token rejected — update it in Settings."
        } catch {
            libraryError = "Couldn't refresh library: \(error.localizedDescription)"
        }
    }

    private func scheduleSearch() {
        pendingSearch?.cancel()
        let query = self.query
        let debounce = searchDebounce
        pendingSearch = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.runSearch(query: query)
        }
    }

    private func runSearch(query: String) async {
        let library = await bookStore.state.library
        guard !Task.isCancelled else { return }
        libraryMatches = BookSearch.filterLibrary(library, query: query)

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            openLibraryMatches = []
            return
        }
        isSearchingOpenLibrary = true
        defer { isSearchingOpenLibrary = false }
        let results = (try? await openLibrary.search(query: trimmed)) ?? []
        guard !Task.isCancelled else { return }
        openLibraryMatches = BookSearch.merge(readwise: libraryMatches, openLibrary: results)
            .filter { $0.source != .readwise }
    }

    /// Back to how the screen looks on a fresh visit. Clearing `query` first
    /// lets its `didSet` run, then the cancel below discards the search it
    /// scheduled along with any search still waiting on the network.
    private func clearSearch() {
        query = ""
        pendingSearch?.cancel()
        pendingSearch = nil
        libraryMatches = []
        openLibraryMatches = []
        isSearchingOpenLibrary = false
    }

    private func recordUsage(of book: Book) {
        pendingRecentsWrite = Task {
            try? await bookStore.recordUsage(of: book)
            recents = await bookStore.state.recents
        }
    }
}
#endif
