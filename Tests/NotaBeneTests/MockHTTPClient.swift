import Foundation
@testable import NotaBene

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    private let lock = NSLock()
    private var handler: Handler
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func setHandler(_ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        requests.append(request)
        let h = handler
        lock.unlock()
        let (data, response) = try h(request)
        return (data, response)
    }

    static func ok(_ data: Data, url: URL = URL(string: "https://example.com")!) -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    static func status(_ code: Int, url: URL = URL(string: "https://example.com")!,
                       data: Data = Data()) -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}
