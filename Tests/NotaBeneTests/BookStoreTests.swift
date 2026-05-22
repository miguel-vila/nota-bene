import XCTest
@testable import NotaBene

final class BookStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("books-\(UUID().uuidString).json")
    }

    func test_setLibrary_roundTrips() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = BookStore(url: url)
        let books = [
            Book(id: "rw:1", title: "A", author: "X", source: .readwise),
            Book(id: "rw:2", title: "B", author: nil, source: .readwise),
        ]
        try await store.setLibrary(books, at: Date(timeIntervalSince1970: 100))

        let reloaded = BookStore(url: url)
        let state = await reloaded.state
        XCTAssertEqual(state.library.map(\.id), ["rw:1", "rw:2"])
        XCTAssertEqual(state.libraryRefreshedAt, Date(timeIntervalSince1970: 100))
    }

    func test_recordUsage_movesToTopAndDedupes() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = BookStore(url: url)
        let a = Book(id: "1", title: "A", author: nil, source: .manual)
        let b = Book(id: "2", title: "B", author: nil, source: .manual)
        try await store.recordUsage(of: a)
        try await store.recordUsage(of: b)
        try await store.recordUsage(of: a)
        let recents = await store.state.recents
        XCTAssertEqual(recents.map(\.title), ["A", "B"])
    }

    func test_libraryNeedsRefresh_respectsTTL() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = BookStore(url: url)
        let now = Date()
        let needsBefore = await store.libraryNeedsRefresh(maxAgeHours: 1, now: now)
        XCTAssertTrue(needsBefore)

        try await store.setLibrary([], at: now)
        let after30 = await store.libraryNeedsRefresh(maxAgeHours: 1,
                                                       now: now.addingTimeInterval(60 * 30))
        XCTAssertFalse(after30)
        let after90 = await store.libraryNeedsRefresh(maxAgeHours: 1,
                                                       now: now.addingTimeInterval(60 * 90))
        XCTAssertTrue(after90)
    }
}
