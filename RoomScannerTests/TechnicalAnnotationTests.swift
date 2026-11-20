import XCTest
@testable import RoomScanner

final class TechnicalAnnotationTests: XCTestCase {
    private var capture: TechnicalCaptureState {
        var value = TechnicalCaptureState(); value.start(); value.tracking(normal: true); value.verify(residualMm: 0, thresholdMm: 30); return value
    }
    private func history() throws -> TechnicalAnnotationHistory {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "small-boiler-room", withExtension: "json"))
        return TechnicalAnnotationHistory(room: try JSONDecoder().decode(TechnicalRoom.self, from: Data(contentsOf: url)))
    }
    private func value<T: Codable & Equatable>(_ item: T, _ unit: String = "m") -> TechnicalValue<T> {
        .init(value: item, unit: unit, source: .entered, method: "manualTest", accuracyMm: nil)
    }
    func testRejectedEditsAreAtomicAndAlignmentGated() throws {
        var history = try history()
        let original = history.document
        XCTAssertThrowsError(try history.edit(capture: TechnicalCaptureState()) { $0.room.notes = [] })
        XCTAssertThrowsError(try history.edit(capture: capture) { $0.room.pipeRuns[0].outerDiameterMm.value = .nan })
        XCTAssertThrowsError(try history.addPipe(history.room.pipeRuns[0], capture: capture))
        XCTAssertEqual(history.document, original)
        XCTAssertFalse(history.canUndo)
    }
    func testDiameterRecomputesGeometryWithoutRewritingRawHitsAndPointMovesUndo() throws {
        var history = try history()
        let raw = history.room.pipeRuns[0].surfaceHits
        let old = history.document.effectiveRoom.pipeRuns[0].centerline.value
        try history.edit(capture: capture) { $0.room.pipeRuns[0].outerDiameterMm.value += 20 }
        XCTAssertEqual(history.room.pipeRuns[0].surfaceHits, raw)
        XCTAssertNotEqual(history.document.effectiveRoom.pipeRuns[0].centerline.value, old)
        let target = TechnicalAnnotationTarget.pipe(history.room.pipeRuns[0].id)
        let moved = TechnicalPoint3(x: raw[0].position.value.x + 0.1, y: raw[0].position.value.y, z: raw[0].position.value.z)
        try history.move(target: target, index: 0, to: moved, observation: nil, capture: capture)
        XCTAssertEqual(history.room.pipeRuns[0].surfaceHits, raw)
        XCTAssertEqual(history.document.points(for: target)[0], moved)
        history.undo(); XCTAssertEqual(history.document.points(for: target)[0], raw[0].position.value)
        history.redo(); XCTAssertEqual(history.document.points(for: target)[0], moved)
        XCTAssertNil(history.document.pointOverrides[0].position.accuracyMm)
    }
    func testDeletingEquipmentCascadesConnectionsAndUndoRestoresGraph() throws {
        var history = try history()
        try history.edit(capture: capture) { $0.room.pipeRuns[0].connectedPorts = [] }
        let pipe = history.room.pipeRuns[0].id, item = history.room.equipment[0].id, port = history.room.equipment[0].ports[0].id
        try history.connect(pipeID: pipe, endpoint: .start, portID: port, capture: capture)
        XCTAssertEqual(history.document.connections.count, 1)
        try history.deleteEquipment(item, capture: capture)
        XCTAssertTrue(history.document.connections.isEmpty)
        XCTAssertTrue(history.room.pipeRuns[0].connectedPorts.isEmpty)
        history.undo()
        XCTAssertEqual(history.document.connections[0].portID, port)
        XCTAssertEqual(history.room.equipment[0].id, item)
    }
    func testDeletingPipeCascadesFittingsAndOverrides() throws {
        var history = try history()
        let id = history.room.pipeRuns[0].id
        let point = history.room.pipeRuns[0].surfaceHits[0].position.value
        try history.move(target: .pipe(id), index: 0, to: point, observation: nil, capture: capture)
        try history.deletePipe(id, capture: capture)
        XCTAssertTrue(history.room.fittings.allSatisfy { $0.hostPipeRunId != id })
        XCTAssertTrue(history.document.pointOverrides.isEmpty)
        history.undo(); XCTAssertEqual(history.document.pointOverrides.count, 1)
    }
    func testDuctsMeasurementsCalibrationAndProvenanceRoundTrip() throws {
        var history = try history()
        let a = value(TechnicalPoint3(x: 0, y: 0, z: 0)), b = value(TechnicalPoint3(x: 2, y: 0, z: 0))
        let measurement = TechnicalPointMeasurement(id: UUID(), name: "Baseline", start: a, end: b)
        try history.edit(capture: capture) {
            $0.ducts.append(.init(id: UUID(), width: value(0.3), height: value(0.2), points: [a, b]))
            $0.measurements.append(measurement)
            $0.calibration = .init(measurementID: measurement.id, referenceLength: value(2.1), observedLength: value(2.0))
        }
        XCTAssertEqual(history.document.correctedLength(2), 2.1, accuracy: 1e-9)
        XCTAssertEqual(history.document.measurements[0].end, b)
        XCTAssertEqual(try JSONDecoder().decode(TechnicalAnnotationDocument.self, from: JSONEncoder().encode(history.document)), history.document)
        XCTAssertNil(history.document.ducts[0].width.accuracyMm)
    }
    func testGridSnappingAndAxisLockPreserveTheOtherAxes() throws {
        let origin = TechnicalPoint3(x: 1, y: 2, z: 3)
        let adjusted = try TechnicalPointEditing.adjust(.init(x: 1.023, y: 2.19, z: 3.02), origin: origin,
            axis: .orthogonal, gridMetres: 0.01, snapPoints: [])
        XCTAssertEqual(adjusted, .init(x: 1, y: 2.19, z: 3))
        let snapped = try TechnicalPointEditing.adjust(.init(x: 1.02, y: 2, z: 3), origin: nil, axis: .free,
            gridMetres: 0, snapPoints: [origin])
        XCTAssertEqual(snapped, origin)
        XCTAssertThrowsError(try TechnicalPointEditing.adjust(.init(x: .infinity, y: 0, z: 0), origin: nil, axis: .free, gridMetres: 0, snapPoints: []))
    }
    func testSidecarDimensionsCannotSilentlyUseMillimetresAsMetres() throws {
        var history = try history()
        let points = history.room.pipeRuns[0].surfaceHits.map(\.position)
        let original = history.document
        XCTAssertThrowsError(try history.edit(capture: capture) {
            $0.ducts.append(.init(id: UUID(), width: value(200, "mm"), height: value(0.2), points: points))
        })
        XCTAssertEqual(history.document, original)
    }
}
