import XCTest
@testable import RoomScanner

final class TechnicalAlignmentSurveyTests: XCTestCase {
    private func survey() throws -> TechnicalAlignmentSurvey {
        var survey = TechnicalAlignmentSurvey()
        try survey.define(origin: .init(x: 2, y: 1, z: 4), xCorner: .init(x: 4, y: 1, z: 4))
        return survey
    }
    func testReferenceCannotBeReplacedAfterAnnotations() throws {
        var survey = try survey()
        survey.lockReference()
        let original = survey.referenceFrame
        XCTAssertThrowsError(try survey.define(origin: .init(x: 0, y: 0, z: 0), xCorner: .init(x: 1, y: 0, z: 0)))
        XCTAssertEqual(survey.referenceFrame, original)
        XCTAssertTrue(survey.referenceLocked)
    }
    func testIndependentThirdPointRecordsAcceptedAndRejectedResiduals() throws {
        var survey = try survey()
        let good = try survey.check(observed: .init(x: 3, y: 1, z: 6.01), expected: .init(x: 1, y: 0, z: 2), thresholdMm: 30, timestamp: 1)
        XCTAssertEqual(good.residualMm, 10, accuracy: 1e-8)
        XCTAssertTrue(good.accepted)
        let bad = try survey.check(observed: .init(x: 3, y: 1, z: 6.1), expected: .init(x: 1, y: 0, z: 2), thresholdMm: 30, timestamp: 2)
        XCTAssertFalse(bad.accepted)
        XCTAssertEqual(survey.checkpoints.count, 2)
        XCTAssertEqual(try JSONDecoder().decode(TechnicalAlignmentSurvey.self, from: JSONEncoder().encode(survey)), survey)
    }
    func testBaselinePointAndInvalidCoordinatesCannotVerifyAlignment() throws {
        var survey = try survey()
        XCTAssertThrowsError(try survey.check(observed: .init(x: 3, y: 1, z: 4), expected: .init(x: 1, y: 0, z: 0), thresholdMm: 30, timestamp: 1))
        XCTAssertThrowsError(try survey.check(observed: .init(x: .nan, y: 1, z: 6), expected: .init(x: 1, y: 0, z: 2), thresholdMm: 30, timestamp: 1))
        XCTAssertThrowsError(try survey.check(observed: .init(x: 3, y: 1, z: 6), expected: .init(x: 1, y: 0, z: 2), thresholdMm: .infinity, timestamp: 1))
        XCTAssertTrue(survey.checkpoints.isEmpty)
        XCTAssertThrowsError(try TechnicalReferenceFrame.transform(origin: .init(x: 0, y: .nan, z: 0), xCorner: .init(x: 1, y: 0, z: 0)))
    }
    func testTrackingRecoveryRequiresNewCheckpointEvenWithStoredSurveyEvidence() throws {
        var survey = try survey()
        var state = TechnicalCaptureState()
        state.start(); state.tracking(normal: true)
        let checkpoint = try survey.check(observed: .init(x: 3, y: 1, z: 6), expected: .init(x: 1, y: 0, z: 2), thresholdMm: 30, timestamp: 1)
        state.verify(residualMm: checkpoint.residualMm, thresholdMm: checkpoint.thresholdMm)
        XCTAssertTrue(state.canAnnotate)
        state.interrupt(); state.tracking(normal: true)
        XCTAssertFalse(state.canAnnotate)
        XCTAssertEqual(survey.checkpoints.count, 1)
    }
    func testHealthWarningsCoverTrackingLightDepthPerformanceAndMemory() {
        let warnings = TechnicalCaptureHealth.warnings(for: .init(trackingNormal: false, fps: 10,
            residentMemoryBytes: 800 * 1_048_576, ambientIntensity: 50, depthCoverage: 0.2, elapsedSeconds: 5))
        XCTAssertEqual(warnings.count, 5)
        XCTAssertTrue(TechnicalCaptureHealth.warnings(for: .init(trackingNormal: true, fps: 60,
            residentMemoryBytes: 100 * 1_048_576, ambientIntensity: 1000, depthCoverage: 0.9, elapsedSeconds: 5)).isEmpty)
    }
}
