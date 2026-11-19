import Foundation
import simd
@testable import RoomScanner

/// Synthetic rooms built in RoomPlan coordinate system (Y up, XZ floor),
/// à partir de contours donnés en coordonnées *plan* (x droite, y haut de feuille).
enum SyntheticRooms {
    static let wallHeight: Float = 2.5

    /// RoomPlan wall connecting two plan points: center in middle, local X axis
    /// along wall (`xAxis = (cos yaw, 0, -sin yaw)` => `yaw = atan2(dy, dx)`).
    static func wall(from a: Point2D, to b: Point2D, height: Float = wallHeight, id: UUID = UUID(), confidence: Confidence = .high) -> ScanSurface {
        let mid = (a + b) * 0.5
        let dx = b.x - a.x, dy = b.y - a.y
        let length = Float((dx * dx + dy * dy).squareRoot())
        let t = simd_float4x4.roomPlacement(x: Float(mid.x), y: height / 2, z: Float(-mid.y), yaw: Float(atan2(dy, dx)))
        return ScanSurface(id: id, category: .wall, dimensions: SIMD3(length, height, 0), transform: t, confidence: confidence)
    }

    /// Opening on a wall: `along` in [0,1] position along the wall.
    static func opening(_ category: ScanSurface.Category, on wall: ScanSurface, from a: Point2D, to b: Point2D,
                        along: Double, width: Float, height: Float, bottom: Float, parent: Bool = true) -> ScanSurface {
        let p = a + (b - a) * along
        let yaw = Float(atan2(b.y - a.y, b.x - a.x))
        let t = simd_float4x4.roomPlacement(x: Float(p.x), y: bottom + height / 2, z: Float(-p.y), yaw: yaw)
        return ScanSurface(category: category, dimensions: SIMD3(width, height, 0.1), transform: t, parentID: parent ? wall.id : nil)
    }

    static func object(_ category: String, at center: Point2D, width: Float, depth: Float, height: Float, yaw: Float = 0) -> ScanObject {
        ScanObject(category: category, dimensions: SIMD3(width, height, depth),
                   transform: .roomPlacement(x: Float(center.x), y: height / 2, z: Float(-center.y), yaw: yaw))
    }

    /// Walls closing a contour (in point order), optional floor.
    static func walls(closing polygon: [Point2D]) -> [ScanSurface] {
        polygon.indices.map { wall(from: polygon[$0], to: polygon[($0 + 1) % polygon.count]) }
    }

    // MARK: - Pièces

    /// Rectangle 4 m x 3 m centered at origin, door to south, window to north, a table.
    static let rectangleCorners = [Point2D(x: -2, y: -1.5), Point2D(x: 2, y: -1.5), Point2D(x: 2, y: 1.5), Point2D(x: -2, y: 1.5)]

    static func rectangularRoom(withParentIDs: Bool = true) -> (scan: ScanInput, south: ScanSurface, north: ScanSurface) {
        let c = rectangleCorners
        let south = wall(from: c[0], to: c[1])   // y = −1.5
        let east  = wall(from: c[1], to: c[2])   // x = 2
        let north = wall(from: c[2], to: c[3])   // y = 1.5
        let west  = wall(from: c[3], to: c[0])   // x = −2
        let door = opening(.door, on: south, from: c[0], to: c[1], along: 0.75, width: 0.9, height: 2.0, bottom: 0, parent: withParentIDs)
        let window = opening(.window, on: north, from: c[2], to: c[3], along: 0.5, width: 1.2, height: 1.0, bottom: 1.0, parent: withParentIDs)
        let floor = ScanSurface(category: .floor, dimensions: SIMD3(4, 3, 0), transform: .roomPlacement(x: 0, y: 0, z: 0))
        let table = object("table", at: Point2D(x: 0.5, y: -0.2), width: 1.2, depth: 0.8, height: 0.75)
        let scan = ScanInput(story: 0, sectionLabels: [.livingRoom],
                             surfaces: [south, east, north, west, door, window, floor], objects: [table])
        return (scan, south, north)
    }

    /// L-shaped room: 6 m x 5 m minus 3 x 2 square -> 24 m2, perimeter 22 m.
    static let lShapeCorners = [Point2D(x: 0, y: 0), Point2D(x: 6, y: 0), Point2D(x: 6, y: 3),
                                Point2D(x: 3, y: 3), Point2D(x: 3, y: 5), Point2D(x: 0, y: 5)]

    static func lShapedRoom() -> ScanInput {
        ScanInput(story: 1, sectionLabels: [.bedroom], surfaces: walls(closing: lShapeCorners))
    }

    // MARK: - Maisons (v2)

    /// Rectangle `w` x `d` with lower-left corner at `origin`, floor at `floorY`, with south door.
    static func rectangularRoom(origin: Point2D, width w: Double, depth d: Double, floorY: Float = 0, label: RoomLabel = .unidentified) -> ScanInput {
        let c = [origin, origin + Point2D(x: w, y: 0), origin + Point2D(x: w, y: d), origin + Point2D(x: 0, y: d)]
        var surfaces = c.indices.map { i -> ScanSurface in
            let a = c[i], b = c[(i + 1) % 4], mid = (a + b) * 0.5
            let t = simd_float4x4.roomPlacement(x: Float(mid.x), y: floorY + wallHeight / 2, z: Float(-mid.y), yaw: Float(atan2(b.y - a.y, b.x - a.x)))
            return ScanSurface(category: .wall, dimensions: SIMD3(Float((b - a).length), wallHeight, 0), transform: t, confidence: .high)
        }
        surfaces.append(opening(.door, on: surfaces[0], from: c[0], to: c[1], along: 0.5, width: 0.9, height: 2.0, bottom: floorY))
        let center = (c[0] + c[2]) * 0.5
        surfaces.append(ScanSurface(category: .floor, dimensions: SIMD3(Float(w), Float(d), 0), transform: .roomPlacement(x: Float(center.x), y: floorY, z: Float(-center.y))))
        return ScanInput(sectionLabels: [label], surfaces: surfaces)
    }

    /// Two adjacent rooms (4 x 3 m and 3 x 3 m) on same level, shared wall at x = 4.
    static func twoRoomApartment() -> StructureInput {
        StructureInput(rooms: [
            rectangularRoom(origin: Point2D(x: 0, y: 0), width: 4, depth: 3, label: .livingRoom),
            rectangularRoom(origin: Point2D(x: 4, y: 0), width: 3, depth: 3, label: .kitchen),
        ])
    }

    /// Multi-story house: two ground floor rooms (y = 0 and 0.02: tolerance) and bedroom at 2.7 m.
    static func twoStoryHouse() -> StructureInput {
        StructureInput(rooms: [
            rectangularRoom(origin: Point2D(x: 0, y: 0), width: 4, depth: 3, label: .livingRoom),
            rectangularRoom(origin: Point2D(x: 4, y: 0), width: 3, depth: 3, floorY: 0.02, label: .kitchen),
            rectangularRoom(origin: Point2D(x: 0, y: 0), width: 4, depth: 3, floorY: 2.7, label: .bedroom),
        ])
    }
}
