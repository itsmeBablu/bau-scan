import XCTest
@testable import RoomScanner

final class TechnicalSavedMeshGeometryTests: XCTestCase {
    func testCeilingTogglePreservesPipesWallsColoursAndOriginalEvidence() {
        let vertices: [TechnicalPoint3] = [.init(x: 0,y: 0,z: 0),.init(x: 1,y: 0,z: 0),.init(x: 0,y: 1,z: 0)]
        let colors: [TechnicalPoint3?] = Array(repeating: .init(x: 0.2,y: 0.5,z: 0.7),count: 3)
        let patch = TechnicalMeshSnapshot.Patch(anchorID: UUID(),vertices: vertices,triangleIndices: [0,1,2,0,2,1,1,0,2],colors: colors,faceClasses: [3,0,1])
        let source = TechnicalMeshSnapshot(timestamp: 1,patches: [patch],alignmentVerified: false,truncated: false)
        let filtered = source.hidingCeilings()
        XCTAssertEqual(filtered.patches[0].triangleIndices,[0,2,1,1,0,2])
        XCTAssertEqual(filtered.patches[0].faceClasses,[0,1])
        XCTAssertEqual(filtered.patches[0].colors,colors)
        XCTAssertEqual(source.capturedFaceCount,3)
        XCTAssertEqual(filtered.capturedFaceCount,2)
        XCTAssertEqual(source.patches[0],patch)
        let legacy = TechnicalMeshSnapshot(timestamp: 1,patches: [triangle()],alignmentVerified: false,truncated: false)
        XCTAssertEqual(legacy.hidingCeilings(),legacy)
    }
    private func triangle(_ x: Double = 0) -> TechnicalMeshSnapshot.Patch {
        .init(anchorID: UUID(), vertices: [.init(x: x, y: 0, z: 0), .init(x: x + 1, y: 0, z: 0), .init(x: x, y: 1, z: 0)], triangleIndices: [0, 1, 2])
    }
    func testRoomSurfaceFilterKeepsUnclassifiedEquipmentAndLegacyEvidence() {
        let wall = triangle(), pipe = triangle(2)
        let classified = TechnicalMeshSnapshot.Patch(anchorID: wall.anchorID, vertices: wall.vertices, triangleIndices: wall.triangleIndices, faceClasses: [1])
        let snapshot = TechnicalMeshSnapshot(timestamp: 1, patches: [classified, pipe], alignmentVerified: false, truncated: false)
        let filtered = snapshot.hidingRoomSurfaces()
        XCTAssertTrue(filtered.patches[0].triangleIndices.isEmpty)
        XCTAssertEqual(filtered.patches[1], pipe)
        XCTAssertEqual(snapshot.patches[0].triangleIndices.count, 3)
    }
    func testMeshCacheKeepsEarlierSurfacesWhenFinalFrameHasNoAnchors() {
        var cache = TechnicalSceneMeshCache(maximumVertices: 6)
        let first = triangle()
        _ = cache.merge(.init(timestamp: 1, patches: [first], alignmentVerified: false, truncated: false))
        let final = cache.merge(.init(timestamp: 2, patches: [], alignmentVerified: false, truncated: false))
        XCTAssertEqual(final.patches, [first])
        let updated = TechnicalMeshSnapshot.Patch(anchorID: first.anchorID, vertices: triangle(3).vertices, triangleIndices: [0,1,2])
        let result = cache.merge(.init(timestamp: 3, patches: [updated], alignmentVerified: false, truncated: false))
        XCTAssertEqual(result.patches, [updated])
        let bounded = cache.merge(.init(timestamp: 4, patches: [triangle(6), triangle(9)], alignmentVerified: false, truncated: false))
        XCTAssertTrue(bounded.truncated)
        XCTAssertEqual(bounded.patches.reduce(0) { $0 + $1.vertices.count }, 6)
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
