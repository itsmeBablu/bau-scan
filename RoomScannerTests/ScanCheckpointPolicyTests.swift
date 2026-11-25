import XCTest
@testable import RoomScanner
final class ScanCheckpointPolicyTests: XCTestCase {
    func testTimeSizeGeometryAndForcedTriggers() {
        var policy = ScanCheckpointPolicy()
        XCTAssertTrue(policy.shouldSave(.init(time:0,geometry:0,bytes:0),trigger:.update))
        policy.committed(.init(time:0,geometry:4,bytes:100))
        XCTAssertFalse(policy.shouldSave(.init(time:1,geometry:100,bytes:1_000_000),trigger:.update))
        XCTAssertFalse(policy.shouldSave(.init(time:4,geometry:4,bytes:100),trigger:.update))
        XCTAssertTrue(policy.shouldSave(.init(time:15,geometry:4,bytes:100),trigger:.update))
        XCTAssertTrue(policy.shouldSave(.init(time:4,geometry:16,bytes:100),trigger:.update))
        XCTAssertTrue(policy.shouldSave(.init(time:4,geometry:4,bytes:600_000),trigger:.update))
        for trigger in [ScanCheckpointPolicy.Trigger.memoryWarning,.background,.pause,.interruption] {
            XCTAssertTrue(policy.shouldSave(.init(time:1,geometry:4,bytes:100),trigger:trigger))
        }
        XCTAssertFalse(policy.shouldSave(.init(time:.nan,geometry:1,bytes:1),trigger:.background))
    }
}
