import XCTest
@testable import RoomScanner

final class TechnicalSavedMeshGeometryTests: XCTestCase {
    private func triangle(_ x: Double = 0) -> TechnicalMeshSnapshot.Patch {
        .init(anchorID: UUID(), vertices: [.init(x: x, y: 0, z: 0), .init(x: x + 1, y: 0, z: 0), .init(x: x, y: 1, z: 0)], triangleIndices: [0, 1, 2])
    }
    func testCombinesPatchIndicesAndAppliesSavedReferenceWithoutChangingRawEvidence() throws {
        let snapshot = TechnicalMeshSnapshot(timestamp: 1, patches: [triangle(), triangle(2)], alignmentVerified: false, truncated: false)
        let reference = try TechnicalReferenceFrame.transform(origin: .init(x: 1, y: 0, z: 0), xCorner: .init(x: 2, y: 0, z: 0))
        let geometry = try TechnicalSavedMeshGeometry(snapshot: snapshot, reference: reference)
        XCTAssertEqual(geometry.vertices.count, 6)
        XCTAssertEqual(geometry.triangleIndices, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(geometry.vertices[0], .init(x: -1, y: 0, z: 0))
        XCTAssertEqual(geometry.extent, .init(x: 3, y: 1, z: 0))
        XCTAssertEqual(geometry.center, .init(x: 0.5, y: 0.5, z: 0))
        XCTAssertEqual(snapshot.patches[0].vertices[0], .init(x: 0, y: 0, z: 0))
    }
    func testViewingDoesNotRequireARMapOrVerifiedAlignment() throws {
        let snapshot = TechnicalMeshSnapshot(timestamp: 1, patches: [triangle()], alignmentVerified: false, truncated: true)
        let geometry = try TechnicalSavedMeshGeometry(snapshot: snapshot, reference: nil)
        XCTAssertEqual(geometry.triangleIndices.count, 3)
        XCTAssertEqual(geometry.extent.x, 1)
    }
    func testChoosesLatestNonemptySnapshotByCaptureOrderNotTimestamp() throws {
        let old = TechnicalMeshSnapshot(timestamp: 1000, patches: [triangle()], alignmentVerified: true, truncated: false)
        let recent = TechnicalMeshSnapshot(timestamp: 10, patches: [triangle(3)], alignmentVerified: false, truncated: false)
        let empty = TechnicalMeshSnapshot(timestamp: 11, patches: [], alignmentVerified: false, truncated: false)
        XCTAssertEqual(TechnicalSavedMeshGeometry.latest(in: [old, recent, empty]), recent)
        XCTAssertNil(TechnicalSavedMeshGeometry.latest(in: [empty]))
    }
    func testInvalidIndicesAndEmptyGeometryFailWithoutArrayIndexTraps() {
        var patch = triangle(); patch = .init(anchorID: patch.anchorID, vertices: patch.vertices, triangleIndices: [0, 1, 3])
        XCTAssertThrowsError(try TechnicalSavedMeshGeometry(snapshot: .init(timestamp: 1, patches: [patch], alignmentVerified: false, truncated: false), reference: nil))
        XCTAssertThrowsError(try TechnicalSavedMeshGeometry(snapshot: .init(timestamp: 1, patches: [], alignmentVerified: false, truncated: false), reference: nil))
    }
    func testLegacyPatchWithoutColorsDecodesAndInvalidColorFails() throws {
        let patch = triangle()
        let encoded = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(TechnicalMeshSnapshot.Patch.self, from: encoded)
        XCTAssertNil(decoded.colors)
        let gray = try TechnicalSavedMeshGeometry(snapshot: .init(timestamp: 1, patches: [decoded], alignmentVerified: false, truncated: false), reference: nil)
        XCTAssertEqual(gray.colors.count, 3)
        XCTAssertTrue(gray.colors.allSatisfy { $0 == nil })
        let invalid = TechnicalMeshSnapshot.Patch(anchorID: UUID(), vertices: patch.vertices, triangleIndices: patch.triangleIndices,
                                                  colors: [.init(x: 2, y: 0, z: 0), nil, nil])
        var journal = TechnicalCaptureJournal()
        journal.append(.init(timestamp: 1, patches: [invalid], alignmentVerified: false, truncated: false))
        XCTAssertThrowsError(try journal.validate())
    }
    func testColorCacheRetainsOtherViewpointsWithoutChangingGeometryAndStaysBounded() {
        let red = TechnicalPoint3(x: 1, y: 0, z: 0)
        var patch = triangle()
        patch.colors = [red, nil, nil]
        let colored = TechnicalMeshSnapshot(timestamp: 1, patches: [patch], alignmentVerified: false, truncated: false)
        var cache = TechnicalSceneColorCache(capacity: 1)
        _ = cache.merge(colored)
        patch.colors = [nil, red, nil]
        let otherView = TechnicalMeshSnapshot(timestamp: 2, patches: [patch], alignmentVerified: false, truncated: false)
        let result = cache.merge(otherView)
        XCTAssertEqual(result.patches[0].colors!, [red, red, nil])
        XCTAssertEqual(result.patches[0].vertices, patch.vertices)
        XCTAssertEqual(result.patches[0].triangleIndices, patch.triangleIndices)
        XCTAssertEqual(cache.count, 1)
    }
    func testTextureAtlasUsesOneSamplePerFaceAndDoesNotColorUnseenFaces() throws {
        let red = TechnicalPoint3(x: 1, y: 0, z: 0)
        var patch = triangle()
        patch.colors = [red, red, red]
        let mesh = try TechnicalSavedMeshGeometry(snapshot: .init(timestamp: 1, patches: [patch], alignmentVerified: false, truncated: false), reference: nil)
        let atlas = try XCTUnwrap(TechnicalMeshAppearance.faceAtlas(mesh))
        XCTAssertEqual(atlas.uv.count, 3)
        XCTAssertEqual(atlas.uv[0], atlas.uv[1])
        XCTAssertEqual(atlas.uv[1], atlas.uv[2])
        patch.colors = [red, nil, nil]
        let partial = try TechnicalSavedMeshGeometry(snapshot: .init(timestamp: 1, patches: [patch], alignmentVerified: false, truncated: false), reference: nil)
        XCTAssertNil(TechnicalMeshAppearance.faceAtlas(partial))
    }
}
