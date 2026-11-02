#if canImport(SwiftUI)
import XCTest
@testable import NotaBene

@MainActor
final class BookSelectionTests: XCTestCase {
    private func tempBookStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bookselection-\(UUID().uuidString).json")
    }

    private func makeSelection(
        library: [Book] = [],
        openLibraryTitles: [String] = [],
        readwiseClient: @escaping @MainActor () -> ReadwiseClient? = { nil }
    ) async -> BookSelection {
        let store = BookStore(url: tempBookStoreURL())
        if !library.isEmpty {
            try? await store.setLibrary(library)
        }
        let docs = openLibraryTitles
            .map { #"{"title":"\#($0)","author_name":["Someone"],"key":"/works/\#($0)"}"# }
            .joined(separator: ",")
        let payload = Data(#"{"docs":[\#(docs)]}"#.utf8)
        let http = MockHTTPClient { _ in MockHTTPClient.ok(payload) }
        return BookSelection(
            bookStore: store,
            openLibrary: OpenLibraryClient(http: http),
            readwiseClient: readwiseClient,
            searchDebounce: .zero
        )
    }

    /// A Readwise client whose library call is always rejected.
    private func rejectingReadwiseClient() -> ReadwiseClient {
        ReadwiseClient(
            token: "bad",
            http: MockHTTPClient { _ in MockHTTPClient.status(401) }
        )
    }

    private func settle(_ selection: BookSelection) async {
        await selection.pendingSearch?.value
        await selection.pendingRecentsWrite?.value
    }

    func test_search_showsLibraryAndOpenLibraryMatches() async {
        let selection = await makeSelection(
            library: [Book(id: "rw:1", title: "A Philosophy of Software Design",
                           author: "John K. Ousterhout", source: .readwise)],
            openLibraryTitles: ["A Philoso Scientific Warrior"]
        )
        selection.query = "philoso"
        await settle(selection)

        XCTAssertEqual(selection.libraryMatches.map(\.id), ["rw:1"])
        XCTAssertEqual(selection.openLibraryMatches.map(\.title), ["A Philoso Scientific Warrior"])
    }

    /// The reported bug: a search run before opening a book was still on screen
    /// after coming back from it.
    func test_returningFromABook_clearsTheSearch() async {
        let selection = await makeSelection(
            library: [Book(id: "rw:1", title: "A Philosophy of Software Design",
                           author: "John K. Ousterhout", source: .readwise)],
            openLibraryTitles: ["A Philoso Scientific Warrior"]
        )
        selection.query = "philoso"
        await settle(selection)
        XCTAssertFalse(selection.libraryMatches.isEmpty)
        XCTAssertFalse(selection.openLibraryMatches.isEmpty)

        selection.selectedBook = selection.libraryMatches[0]
        selection.selectedBook = nil  // SwiftUI pops the capture flow

        XCTAssertEqual(selection.query, "")
        XCTAssertEqual(selection.libraryMatches, [])
        XCTAssertEqual(selection.openLibraryMatches, [])
        XCTAssertFalse(selection.isSearchingOpenLibrary)
        await settle(selection)
        XCTAssertEqual(selection.query, "")
        XCTAssertEqual(selection.openLibraryMatches, [])
    }

    /// Clearing the search must not take the rest of the screen with it: the
    /// recents list and a standing library-refresh error are not search state,
    /// and the error would otherwise stay hidden until the next refresh.
    func test_returningFromABook_keepsTheRecentsAndTheLibraryError() async {
        let client = rejectingReadwiseClient()
        let selection = await makeSelection(
            library: [Book(id: "rw:1", title: "Dune", author: "Herbert", source: .readwise)],
            readwiseClient: { client }
        )
        await selection.refreshLibrary(force: true)
        let error = selection.libraryError
        XCTAssertNotNil(error)

        selection.query = "dune"
        await settle(selection)

        selection.selectedBook = selection.libraryMatches[0]
        selection.selectedBook = nil

        await settle(selection)
        XCTAssertEqual(selection.recents.map(\.id), ["rw:1"])
        XCTAssertEqual(selection.libraryError, error)
        XCTAssertEqual(selection.query, "")
    }

    func test_selectingABook_recordsItAsRecent() async {
        let selection = await makeSelection()
        let book = Book(id: "ol:1", title: "Personal Knowledge", author: "Polanyi", source: .openLibrary)
        selection.selectedBook = book

        await settle(selection)
        XCTAssertEqual(selection.recents.map(\.id), ["ol:1"])
    }

    func test_clearingTheQueryByHand_dropsBothResultLists() async {
        let selection = await makeSelection(
            library: [Book(id: "rw:1", title: "Dune", author: "Herbert", source: .readwise)],
            openLibraryTitles: ["Dune Messiah"]
        )
        selection.query = "dune"
        await settle(selection)
        XCTAssertFalse(selection.openLibraryMatches.isEmpty)

        selection.query = ""
        await settle(selection)
        XCTAssertEqual(selection.libraryMatches, [])
        XCTAssertEqual(selection.openLibraryMatches, [])
    }
}
#endif
