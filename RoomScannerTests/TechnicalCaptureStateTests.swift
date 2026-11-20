import XCTest
@testable import RoomScanner

final class TechnicalCaptureStateTests: XCTestCase {
    func testTrackingRecoveryAloneDoesNotRestoreAnnotationPermission() {
        var state = TechnicalCaptureState()
        state.start()
        state.tracking(normal: true)
        state.verify(residualMm: 10, thresholdMm: 30)
        XCTAssertTrue(state.canAnnotate)
        state.interrupt()
        state.tracking(normal: true)
        XCTAssertFalse(state.canAnnotate)
        XCTAssertNil(state.checkpointResidualMm)
        state.verify(residualMm: 40, thresholdMm: 30)
        XCTAssertFalse(state.canAnnotate)
        state.verify(residualMm: 15, thresholdMm: 30)
        XCTAssertTrue(state.canAnnotate)
    }
    func testLateCallbacksCannotReviveStoppedCapture() {
        var state = TechnicalCaptureState()
        state.start()
        state.stop()
        state.tracking(normal: true)
        state.interrupt()
        state.verify(residualMm: 0, thresholdMm: 30)
        XCTAssertEqual(state.phase, .stopped)
        XCTAssertFalse(state.canAnnotate)
    }
    func testAlignmentRequiredAfterInterruption() {
        var state = TechnicalCaptureState()
        state.start()
        state.tracking(normal: true)
        XCTAssertFalse(state.canAnnotate)
        state.verify(residualMm: 20, thresholdMm: 30)
        XCTAssertTrue(state.canAnnotate)
        state.interrupt()
        state.tracking(normal: true)
        XCTAssertFalse(state.canAnnotate)
        state.verify(residualMm: 50, thresholdMm: 30)
        XCTAssertFalse(state.canAnnotate)
        state.stop()
        XCTAssertFalse(state.canAnnotate)
    }

    func testReferenceFrameMapsOriginAndAxis() throws {
        let origin = TechnicalPoint3(x: 3, y: 1, z: 4)
        let transform = try TechnicalReferenceFrame.transform(origin: origin, xCorner: .init(x: 3, y: 1, z: 6))
        let zero = TechnicalReferenceFrame.apply(transform, to: origin)
        XCTAssertEqual(zero.distance(to: .init(x: 0, y: 0, z: 0)), 0, accuracy: 1e-9)
        let corner = TechnicalReferenceFrame.apply(transform, to: .init(x: 3, y: 1, z: 6))
        XCTAssertEqual(corner.x, 2, accuracy: 1e-9)
        XCTAssertEqual(corner.z, 0, accuracy: 1e-9)
        XCTAssertThrowsError(try TechnicalReferenceFrame.transform(origin: origin, xCorner: origin))
    }
}
