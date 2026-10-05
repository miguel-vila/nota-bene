import Foundation
import os
@testable import NotaBene

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    private let lock = NSLock()
    private var handler: Handler
    private var recorded: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func setHandler(_ handler: @escaping Handler) {
        lock.withLock { self.handler = handler }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let h: Handler = lock.withLock {
            recorded.append(request)
            return handler
        }
        return try h(request)
    }

    static func ok(_ data: Data, url: URL = URL(string: "https://example.com")!) -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    static func status(_ code: Int, url: URL = URL(string: "https://example.com")!,
                       data: Data = Data()) -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}

/// Call counter for `MockHTTPClient.Handler` closures. The handler is `@Sendable`,
/// so it cannot capture and mutate a local `var`; capture one of these instead.
final class CallCounter: Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)

    /// Returns how many calls came before this one, then records this call.
    func next() -> Int {
        count.withLock { current in
            defer { current += 1 }
            return current
        }
    }
}
