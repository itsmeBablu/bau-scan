import XCTest
@testable import RoomScanner

final class OperationLifetimeTests: XCTestCase {
    func testSlowWriteKeepsExclusiveOwnershipUntilItActuallyFinishes() throws {
        var lifetime = OperationLifetime()
        let first = try XCTUnwrap(lifetime.begin())
        XCTAssertNil(lifetime.begin())
        XCTAssertTrue(lifetime.warnIfRunning(first))
        XCTAssertTrue(lifetime.isRunning)
        XCTAssertNil(lifetime.begin(), "A timeout must not enable a second writer")
        XCTAssertFalse(lifetime.warnIfRunning(first), "Warn only once for this operation")
        XCTAssertTrue(lifetime.finish(first))
        XCTAssertFalse(lifetime.isRunning)
        XCTAssertFalse(lifetime.exceededExpectedDuration)
        XCTAssertNotNil(lifetime.begin(), "Retry is available after real completion")
    }

    func testLateCompletionOrDeadlineCannotEndOrWarnANewerOperation() throws {
        var lifetime = OperationLifetime()
        let first = try XCTUnwrap(lifetime.begin())
        XCTAssertTrue(lifetime.finish(first))
        let second = try XCTUnwrap(lifetime.begin())
        XCTAssertFalse(lifetime.finish(first))
        XCTAssertFalse(lifetime.warnIfRunning(first))
        XCTAssertEqual(lifetime.id, second)
        XCTAssertFalse(lifetime.exceededExpectedDuration)
        XCTAssertTrue(lifetime.finish(second))
    }
}
