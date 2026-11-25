import XCTest
@testable import RoomScanner

final class ProjectDistanceCheckTests: XCTestCase {
    func testKnownDistanceReportsOnlyTheActualComparison() throws {
        var check = ProjectDistanceCheck(projectID:UUID(),reference:.init(kind:.room,itemID:UUID(),library:"local"),elementID:UUID(),label:"Wall",referenceMeters:2,observedMeters:2.03,method:"Tape measure")
        try check.validate()
        XCTAssertEqual(check.absoluteErrorMeters,0.03,accuracy:0.0000001)
        XCTAssertEqual(check.relativeErrorPercent,1.5,accuracy:0.0000001)
        XCTAssertTrue(check.deviceValidationPending)
        check.referenceMeters = 0
        XCTAssertThrowsError(try check.validate())
    }
}
