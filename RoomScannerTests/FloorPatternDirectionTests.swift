import XCTest
import SceneKit
@testable import RoomScanner

final class FloorPatternDirectionTests: XCTestCase {
    func testWoodDirectionFollowsTransformedLongestWallAndIgnoresRoomOrder() {
        var room = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Room")
        room.transform = .init(translation: .init(x: 10, y: -4), rotation: .pi / 6)
        let angle = FloorPatternDirection.angle(rooms: [room])
        XCTAssertEqual(angle, .pi / 6, accuracy: 1e-6)
        room.walls.reverse()
        XCTAssertEqual(FloorPatternDirection.angle(rooms: [room]), angle, accuracy: 1e-6)
        XCTAssertEqual(FloorPatternDirection.angle(rooms: []), 0)
    }

    @MainActor func testPatternAlignmentPreservesWorldFloorBounds() throws {
        var room = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Room")
        room.transform.rotation = .pi / 6
        let material = SCNMaterial()
        let a = try XCTUnwrap(StudioFloorSlab.node(rooms: [room], regions: [], material: material, textureScale: 0.72))
        let b = try XCTUnwrap(StudioFloorSlab.node(rooms: [room], regions: [], material: material, textureScale: 0.72,
                                                  patternAngle: FloorPatternDirection.angle(rooms: [room])))
        // Compare actual tessellated vertices in world space, rather than a
        // rotated local bounding box (which can overestimate a concave shape).
        func bounds(_ node: SCNNode) -> [Double] {
            var points: [SCNVector3] = []
            func append(_ child: SCNNode) {
                guard let source = child.geometry?.sources(for: .vertex).first else { return }
                source.data.withUnsafeBytes { bytes in
                    for index in 0..<source.vectorCount {
                        func component(_ axis: Int) -> Float {
                            let offset = source.dataOffset + index * source.dataStride + axis * source.bytesPerComponent
                            if source.bytesPerComponent == 4 { return bytes.loadUnaligned(fromByteOffset: offset, as: Float.self) }
                            return Float(bytes.loadUnaligned(fromByteOffset: offset, as: Double.self))
                        }
                        points.append(child.convertPosition(SCNVector3(component(0),component(1),component(2)), to: nil))
                    }
                }
            }
            append(node); node.enumerateChildNodes { child, _ in append(child) }
            return [points.map { Double($0.x) }.min() ?? .nan, points.map { Double($0.x) }.max() ?? .nan,
                    points.map { Double($0.y) }.min() ?? .nan, points.map { Double($0.y) }.max() ?? .nan,
                    points.map { Double($0.z) }.min() ?? .nan, points.map { Double($0.z) }.max() ?? .nan]
        }
        for (before,after) in zip(bounds(a),bounds(b)) { XCTAssertEqual(before,after,accuracy: 1e-4) }
        XCTAssertEqual(StudioFloorPresets.tiles.count, 6)
        XCTAssertEqual(Set(StudioFloorPresets.tiles.map(\.id)).count, 6)
    }
}
