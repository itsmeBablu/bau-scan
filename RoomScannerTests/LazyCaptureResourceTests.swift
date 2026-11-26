import XCTest
@testable import RoomScanner

final class LazyCaptureResourceTests:XCTestCase {
    @MainActor func testDiscardedViewInitializersDoNotConstructCameraResources() {
        var constructions = 0
        func holder() -> LazyCaptureResource<NSObject> {
            LazyCaptureResource { constructions += 1; return NSObject() }
        }
        let retained = holder()
        for _ in 0..<100 { _ = holder() }
        XCTAssertEqual(constructions,0)
        let first = retained.value
        for _ in 0..<100 { XCTAssertTrue(first === retained.value) }
        XCTAssertEqual(constructions,1)
    }
    @MainActor func testOptionalResourceHasNoInvalidEmptyState() {
        var constructions = 0
        let holder = LazyCaptureResource<Int?> { constructions += 1; return nil }
        XCTAssertNil(holder.value); XCTAssertNil(holder.value)
        XCTAssertEqual(constructions,1)
    }
}
