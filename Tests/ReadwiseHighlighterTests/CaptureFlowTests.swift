#if canImport(SwiftUI)
import XCTest
@testable import ReadwiseHighlighter

@MainActor
final class CaptureFlowTests: XCTestCase {
    private func makeFlow(withImage: Bool = true) -> CaptureFlow {
        let book = Book(id: "b", title: "Test Book", author: nil, source: .manual)
        let flow = CaptureFlow(book: book)
        if withImage {
            flow.acceptPhoto(Data([0x01]))
        }
        return flow
    }

    func test_failExtraction_setsErrorAndStage() {
        let flow = makeFlow()
        flow.stage = .extracting
        flow.failExtraction("network down")
        XCTAssertEqual(flow.stage, .extractionFailed)
        XCTAssertEqual(flow.lastError, "network down")
    }

    func test_retryExtraction_clearsErrorAndReturnsToExtracting() {
        let flow = makeFlow()
        flow.failExtraction("oops")
        flow.retryExtraction()
        XCTAssertEqual(flow.stage, .extracting)
        XCTAssertNil(flow.lastError)
    }

    func test_retryExtraction_noopWhenNoImages() {
        let flow = makeFlow(withImage: false)
        flow.failExtraction("oops")
        // No images → can't actually re-run extraction.
        flow.retryExtraction()
        XCTAssertEqual(flow.stage, .extractionFailed)
        XCTAssertEqual(flow.lastError, "oops")
    }

    func test_backToPreview_clearsErrorAndReturnsToPreview() {
        let flow = makeFlow()
        flow.failExtraction("oops")
        flow.backToPreview()
        XCTAssertEqual(flow.stage, .preview)
        XCTAssertNil(flow.lastError)
    }

    func test_skipExtraction_fromFailureGoesToReviewWithBlankHighlight() {
        let flow = makeFlow()
        flow.failExtraction("oops")
        flow.skipExtraction()
        XCTAssertEqual(flow.stage, .review)
        XCTAssertTrue(flow.didDetectEmptyHighlight)
        XCTAssertEqual(flow.highlights.count, 1)
        XCTAssertTrue(flow.highlights[0].text.isEmpty)
    }

    func test_acceptPhoto_advancesFromCaptureToPreview() {
        let flow = makeFlow(withImage: false)
        XCTAssertEqual(flow.stage, .capture)
        flow.acceptPhoto(Data([0x42]))
        XCTAssertEqual(flow.stage, .preview)
        XCTAssertEqual(flow.images.count, 1)
    }
}
#endif
