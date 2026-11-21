import XCTest
@testable import RoomScanner

final class TechnicalCaptureStateTests: XCTestCase {
    func testCameraCanResumeAfterBackgroundWithoutRestoringSurveyPermission() {
        var state = TechnicalCaptureState()
        state.start(); state.tracking(normal: true)
        state.verify(residualMm: 5,thresholdMm: 30)
        XCTAssertTrue(state.canAnnotate)
        state.suspendCamera()
        XCTAssertTrue(state.cameraSuspended)
        XCTAssertFalse(state.trackingNormal)
        XCTAssertTrue(state.resumeCamera())
        XCTAssertFalse(state.cameraSuspended)
        state.tracking(normal: true)
        XCTAssertFalse(state.canAnnotate,"Camera recovery must not certify survey alignment.")
        XCTAssertNil(state.checkpointResidualMm)
        state.verify(residualMm: 5,thresholdMm: 30)
        XCTAssertTrue(state.canAnnotate)
        XCTAssertFalse(state.resumeCamera(),"Do not repeatedly restart an already running camera.")
    }
    func testStoppedOrIdleCameraCannotBeResumedByLateForegroundEvents() {
        var state = TechnicalCaptureState()
        state.suspendCamera()
        XCTAssertFalse(state.resumeCamera())
        XCTAssertEqual(state.phase,.idle)
        state.start(); state.suspendCamera(); state.stop()
        XCTAssertFalse(state.cameraSuspended)
        XCTAssertFalse(state.resumeCamera())
        XCTAssertEqual(state.phase,.stopped)
    }
    func testRoomToSessionRoundTrip() throws {
        let frame = try TechnicalReferenceFrame.transform(origin: .init(x: 3, y: 1, z: 4), xCorner: .init(x: 4, y: 1, z: 6))
        let original = TechnicalPoint3(x: -2, y: 2.7, z: 8)
        let room = TechnicalReferenceFrame.apply(frame, to: original)
        XCTAssertEqual(TechnicalReferenceFrame.inverseApply(frame, to: room).distance(to: original), 0, accuracy: 1e-9)
    }
    func testDepthProjectionUsesARCameraAxesAndRejectsInvalidDepth() throws {
        let center = try XCTUnwrap(TechnicalDepthProjection.cameraPoint(pixelX: 100, pixelY: 80,
            depthMetres: 2, fx: 200, fy: 200, cx: 100, cy: 80))
        XCTAssertEqual(center, .init(x: 0, y: 0, z: -2))
        let offset = try XCTUnwrap(TechnicalDepthProjection.cameraPoint(pixelX: 150, pixelY: 100,
            depthMetres: 2, fx: 200, fy: 200, cx: 100, cy: 80))
        XCTAssertEqual(offset.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(offset.y, -0.2, accuracy: 1e-9)
        XCTAssertNil(TechnicalDepthProjection.cameraPoint(pixelX: 0, pixelY: 0, depthMetres: .nan,
            fx: 200, fy: 200, cx: 100, cy: 80))
    }
    func testFrameHistoryIsBoundedAndCodable() throws {
        var history = TechnicalFrameHistory(capacity: 2)
        for timestamp in 0..<3 {
            history.append(.init(timestamp: Double(timestamp), cameraTransform: Array(repeating: 0, count: 16),
                intrinsics: Array(repeating: 0, count: 9), imageWidth: 1920, imageHeight: 1440,
                tracking: "normal", hasSceneDepth: true, hasSmoothedSceneDepth: true, alignmentVerified: false))
        }
        XCTAssertEqual(history.records.map(\.timestamp), [1, 2])
        XCTAssertEqual(history.droppedCount, 1)
        let data = try JSONEncoder().encode(history.records)
        XCTAssertEqual(try JSONDecoder().decode([TechnicalFrameRecord].self, from: data), history.records)
    }
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
