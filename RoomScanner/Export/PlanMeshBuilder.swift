import Foundation
import simd

/// Indexed triangle mesh, face normals (flat faceted shading), named groups.
/// Coordinates: meters, **Y up**, z = -y_plan (same convention as RealityKit
/// and RoomPlan USDZ output).
struct TriangleMesh: Equatable {
    struct Group: Equatable { var name: String; var triangles: Range<Int> }
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var triangles: [SIMD3<UInt32>] = []
    var groups: [Group] = []

    var isEmpty: Bool { triangles.isEmpty }

    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard let f = positions.first else { return nil }
        return positions.dropFirst().reduce((f, f)) { (simd_min($0.0, $1), simd_max($0.1, $1)) }
    }

    /// Adds a planar quad (4 vertices in order, outward normal = counterclockwise viewed from outside).
    mutating func addQuad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
        let cross = simd_cross(b - a, c - a)
        guard simd_length(cross) > 1e-9 else { return }   // face plate : pas de normale possible
        let n = simd_normalize(cross)
        let base = UInt32(positions.count)
        positions += [a, b, c, d]; normals += [n, n, n, n]
        triangles += [SIMD3(base, base + 1, base + 2), SIMD3(base, base + 2, base + 3)]
    }

    /// Adds a triangle with its normal.
    mutating func addTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let cross = simd_cross(b - a, c - a)
        guard simd_length(cross) > 1e-9 else { return }
        let n = simd_normalize(cross)
        let base = UInt32(positions.count)
        positions += [a, b, c]; normals += [n, n, n]
        triangles.append(SIMD3(base, base + 1, base + 2))
    }

    mutating func group(_ name: String, _ body: (inout TriangleMesh) -> Void) {
        let start = triangles.count
        body(&self)
        if triangles.count > start { groups.append(Group(name: name, triangles: start..<triangles.count)) }
    }
}

/// Builds parametric mesh of a house: walls with cutouts (lintels,
/// parapets), door and glazing panels, polygonal floor slab, placed
/// boxes. Deterministic output, identical on iOS / macOS, independent of RoomPlan.
struct PlanMeshBuilder {
    var floorThickness: Double = FloorPlan.defaultFloorSlabThickness
    var includeObjects = true
    var includePanels = true

    func build(_ house: House) -> TriangleMesh {
        var mesh = TriangleMesh()
        let geometry = WallGeometry()
        for room in house.allRooms {
            let t = room.transform
            let prefix = house.allRooms.count > 1 ? "\(room.name)/" : ""
            mesh.group(prefix + "walls") { m in
                for wall in room.walls {
                    let ops = room.openings.filter { $0.wallID == wall.id }
                    for box in geometry.wallBoxes(wall, openings: ops) { Self.addBox(box, transform: t, to: &m) }
                }
                let joins = StudioWallJoins.mesh(room: room, visible: Set(room.walls.map(\.id)))
                if !joins.isEmpty {
                    let offset = UInt32(m.positions.count)
                    m.positions += joins.positions
                    m.normals += joins.normals
                    m.triangles += joins.triangles.map { $0 &+ SIMD3<UInt32>(repeating: offset) }
                }
            }
            if includePanels {
                for kind in [Opening.Kind.door, .window] {
                    mesh.group(prefix + (kind == .door ? "doors" : "windows")) { m in
                        for o in room.openings where o.kind == kind {
                            if let box = geometry.panelBox(o, wall: room.wall(withID: o.wallID)) { Self.addBox(box, transform: t, to: &m) }
                        }
                    }
                }
            }
            mesh.group(prefix + "floor") { m in Self.addFloor(room, transform: t, thickness: room.floorSlabThickness == nil ? floorThickness : room.displayFloorSlabThickness, to: &m) }
            if includeObjects {
                mesh.group(prefix + "objects") { m in
                    for o in room.objects { Self.addBox(WallGeometry.objectBox(o), transform: t, to: &m) }
                }
            }
        }
        return mesh
    }

    // MARK: primitives

    static func point(_ p: Point2D, y: Double) -> SIMD3<Float> { SIMD3(Float(p.x), Float(y), Float(-p.y)) }

    /// Box sitting on a segment: 6 faces with outward normals.
    static func addBox(_ box: WallGeometry.Box, transform t: Transform2D, to mesh: inout TriangleMesh) {
        guard box.segment.length > 0, box.height > 0, box.thickness > 0 else { return }
        let seg = Segment2D(start: t.apply(box.segment.start), end: t.apply(box.segment.end))
        let n = seg.leftNormal * (box.thickness / 2)
        // Footprint corners in plan: a→b along segment, sides +n then -n.
        let p0 = seg.start + n, p1 = seg.end + n, p2 = seg.end - n, p3 = seg.start - n
        let (lo, hi) = (box.bottom, box.top)
        let a0 = point(p0, y: lo), a1 = point(p1, y: lo), a2 = point(p2, y: lo), a3 = point(p3, y: lo)
        let b0 = point(p0, y: hi), b1 = point(p1, y: hi), b2 = point(p2, y: hi), b3 = point(p3, y: hi)
        // Conversion from plan (x, y) to 3D (x, -z) reverses chirality: quads are
        // ordered to yield outward-facing normals.
        mesh.addQuad(b3, b2, b1, b0)       // dessus (+y)
        mesh.addQuad(a0, a1, a2, a3)       // dessous (−y)
        mesh.addQuad(a0, b0, b1, a1)       // face +n (negative z)
        mesh.addQuad(a2, b2, b3, a3)       // face −n
        mesh.addQuad(a1, b1, b2, a2)       // bout `end`
        mesh.addQuad(a3, b3, b0, a0)       // bout `start`
    }

    /// Floor slab: floor polygon (or bounding box) triangulated top/bottom + edges.
    static func addFloor(_ room: FloorPlan, transform t: Transform2D, thickness: Double, to mesh: inout TriangleMesh) {
        let b = room.floorBounds
        guard !b.isEmpty else { return }
        let rectangle = [Point2D(x: b.minX, y: b.minY), Point2D(x: b.maxX, y: b.minY), Point2D(x: b.maxX, y: b.maxY), Point2D(x: b.minX, y: b.maxY)]
        var poly = room.floorPolygon.count >= 3 ? room.floorPolygon : rectangle
        // Counterclockwise winding so normals point outward.
        if Polygon2D.signedArea(poly) < 0 { poly.reverse() }
        var pts = poly.map(t.apply)
        var (tris, complete) = Polygon2D.triangulation(pts)
        if !complete {
            // Degenerate contour: a partial slab with all sides would be unclosed (rejected
            // 3D printing). Fallback to bounding rectangle, always triangulable.
            pts = rectangle.map(t.apply)
            (tris, _) = Polygon2D.triangulation(pts)
        }
        for tri in tris {
            let (a, b, c) = (pts[tri.0], pts[tri.1], pts[tri.2])
            mesh.addTriangle(point(a, y: 0), point(b, y: 0), point(c, y: 0))                                    // dessus : normale +y
            mesh.addTriangle(point(a, y: -thickness), point(c, y: -thickness), point(b, y: -thickness))          // dessous : −y
        }
        for i in pts.indices {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            mesh.addQuad(point(q, y: -thickness), point(q, y: 0), point(p, y: 0), point(p, y: -thickness))   // side face, outward normal
        }
    }
}
