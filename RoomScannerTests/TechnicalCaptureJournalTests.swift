import XCTest
@testable import RoomScanner

final class TechnicalCaptureJournalTests: XCTestCase {
    private func depth(_ timestamp: Double, pixels: Int = 1) -> TechnicalDepthSnapshot {
        .init(timestamp: timestamp, width: pixels, height: 1, imageWidth: pixels, imageHeight: 1,
              cameraTransform: [], intrinsics: [], depthMetres: Array(repeating: 1, count: pixels),
              confidence: nil, alignmentVerified: true)
    }
    private func mesh(_ timestamp: Double) -> TechnicalMeshSnapshot {
        .init(timestamp: timestamp, patches: [], alignmentVerified: false, truncated: false)
    }
    func testRetainsMultipleSnapshotsAndAlignmentEvidenceOnRoundTrip() throws {
        var journal = TechnicalCaptureJournal()
        journal.append(depth(1)); journal.append(depth(2)); journal.append(mesh(3)); journal.append(mesh(4))
        journal.append(.init(timestamp: 5, kind: .interrupted, message: "Backgrounded", alignmentVerified: false))
        XCTAssertEqual(journal.depths.map(\.timestamp), [1, 2])
        XCTAssertEqual(journal.meshes.map(\.timestamp), [3, 4])
        XCTAssertTrue(journal.depths.allSatisfy(\.alignmentVerified))
        XCTAssertFalse(journal.meshes[0].alignmentVerified)
        XCTAssertFalse(journal.retentionLimited)
        XCTAssertEqual(try JSONDecoder().decode(TechnicalCaptureJournal.self, from: JSONEncoder().encode(journal)), journal)
    }
    func testSnapshotBudgetEvictsOldestAcrossDepthAndMesh() {
        var journal = TechnicalCaptureJournal(snapshotBudget: 530)
        XCTAssertTrue(journal.append(mesh(1)))
        XCTAssertTrue(journal.append(depth(2)))
        XCTAssertTrue(journal.append(mesh(3)))
        XCTAssertTrue(journal.meshes.allSatisfy { $0.timestamp != 1 })
        XCTAssertEqual(journal.depths.map(\.timestamp), [2])
        XCTAssertEqual(journal.meshes.map(\.timestamp), [3])
        XCTAssertEqual(journal.droppedSnapshots, 1)
        XCTAssertLessThanOrEqual(journal.snapshotBytes, 530)
        XCTAssertTrue(journal.retentionLimited)
    }
    func testOversizedSnapshotDoesNotErasePreviouslyRetainedEvidence() {
        var journal = TechnicalCaptureJournal(snapshotBudget: 530)
        journal.append(mesh(1))
        XCTAssertFalse(journal.append(depth(2, pixels: 1000)))
        XCTAssertEqual(journal.meshes.count, 1)
        XCTAssertEqual(journal.droppedSnapshots, 1)
    }
    func testFrameAndEventLimitsAreExplicit() {
        var journal = TechnicalCaptureJournal(frameCapacity: 1, eventCapacity: 1)
        for timestamp in [1.0, 2.0] {
            journal.append(.init(timestamp: timestamp, cameraTransform: [], intrinsics: [], imageWidth: 1, imageHeight: 1,
                                 tracking: "normal", hasSceneDepth: true, hasSmoothedSceneDepth: false, alignmentVerified: false))
            journal.append(.init(timestamp: timestamp, kind: .trackingChanged, message: "normal", alignmentVerified: false))
        }
        XCTAssertEqual(journal.frames.map(\.timestamp), [2])
        XCTAssertEqual(journal.events.map(\.timestamp), [2])
        XCTAssertEqual(journal.droppedFrames, 1)
        XCTAssertEqual(journal.droppedEvents, 1)
    }
}
