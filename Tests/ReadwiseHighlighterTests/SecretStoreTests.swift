import XCTest
@testable import ReadwiseHighlighter

final class SecretStoreTests: XCTestCase {
    func test_inMemory_roundTrips() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(try store.read(SecretKey.gemini))
        try store.write("abc", for: SecretKey.gemini)
        XCTAssertEqual(try store.read(SecretKey.gemini), "abc")
        try store.delete(SecretKey.gemini)
        XCTAssertNil(try store.read(SecretKey.gemini))
    }
}
