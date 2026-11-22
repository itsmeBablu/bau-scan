import Foundation
import simd

/// Converts `ScanInput` (RoomPlan) to `FloorPlan`: ground projection,
/// opening attachment, floor polygon, ceiling heights.
struct FloorPlanBuilder {
    /// Wall snapping tolerance (m) to reconstruct boundary.
    var chainTolerance = 0.25
    var wallThickness = FloorPlan.defaultWallThickness
    /// Rotates plan so longest wall is horizontal (RoomPlan delivers arbitrary
    /// world coordinates: room arrives tilted). Disabled by `HouseBuilder` (shared coordinates).
    var alignToLongestWall = true

    func build(from scan: ScanInput, name: String) -> FloorPlan {
        let floorY = floorLevel(of: scan)
        var walls = scan.walls.map { makeWall($0) }
        var openings = scan.openings.map { makeOpening($0, walls: walls, floorY: floorY) }
        var objects = scan.objects.map { makeObject($0) }
        let outline = floorOutline(walls: walls,scan: scan)
        var polygon = outline.polygon
        if alignToLongestWall, let longest = walls.max(by: { $0.length < $1.length }) {
            // Smallest rotation (±90° max) that makes this wall horizontal.
            var theta = longest.segment.angle
            while theta > .pi / 2 { theta -= .pi }; while theta <= -.pi / 2 { theta += .pi }
            if abs(theta) > 1e-6 {
                let r = Transform2D(translation: .zero, rotation: -theta)
                walls = walls.map { var w = $0; w.segment = Segment2D(start: r.apply($0.start), end: r.apply($0.end)); return w }
                openings = openings.map { var o = $0; o.center = r.apply($0.center); o.angle -= theta; return o }
                objects = objects.map { var o = $0; o.center = r.apply($0.center); o.angle -= theta; return o }
                polygon = polygon.map(r.apply)
            }
        }
        let heights = walls.map(\.height)
        let ceiling: ClosedRange<Double> = heights.isEmpty ? 0...0 : heights.min()!...heights.max()!
        return FloorPlan(
            id: scan.id,
            name: name,
            label: scan.sectionLabels.first ?? .unidentified,
            story: scan.story,
            transform: .identity,
            walls: walls,
            openings: openings,
            objects: objects,
            floorPolygon: polygon,
            ceilingHeight: ceiling,floorOutlineSource: outline.source)
    }

    // MARK: - Elements

    private func makeWall(_ s: ScanSurface) -> Wall {
        let center = Point2D(projecting: s.transform.translation)
        let dir = planarDirection(of: s.transform)
        let half = Double(s.dimensions.x) / 2
        return Wall(id: s.id,
                    segment: Segment2D(start: center - dir * half, end: center + dir * half),
                    height: Double(s.dimensions.y),
                    thickness: wallThickness,
                    confidence: s.confidence)
    }

    private func makeOpening(_ s: ScanSurface, walls: [Wall], floorY: Double) -> Opening {
        let center = Point2D(projecting: s.transform.translation)
        let kind: Opening.Kind = switch s.category { case .door: .door; case .window: .window; default: .opening }
        // RoomPlan provides parent wall; otherwise use nearest wall.
        let wallID = s.parentID.flatMap { pid in walls.first { $0.id == pid }?.id }
            ?? walls.min { $0.segment.distance(to: center) < $1.segment.distance(to: center) }?.id
        let bottom = Double(s.transform.translation.y) - Double(s.dimensions.y) / 2
        let sill = kind == .door ? 0 : max(0, bottom - floorY)
        return Opening(id: s.id, kind: kind, wallID: wallID, center: center,
                       width: Double(s.dimensions.x), height: Double(s.dimensions.y),
                       sillHeight: sill, angle: planarDirection(of: s.transform).angle, confidence: s.confidence)
    }

    private func makeObject(_ o: ScanObject) -> PlacedObject {
        PlacedObject(id: o.id, category: o.category,
                     center: Point2D(projecting: o.transform.translation),
                     size: Size2D(width: Double(o.dimensions.x), depth: Double(o.dimensions.z)),
                     height: Double(o.dimensions.y),
                     angle: planarDirection(of: o.transform).angle,
                     confidence: o.confidence)
    }

    // MARK: - Floor

    /// Floor contour: RoomPlan floor surface polygon (`polygonCorners`, local
    /// surface coords → world → plan, simplified); fallback to chained walls, then bounds.
    private func floorOutline(walls: [Wall],scan: ScanInput) -> (polygon: [Point2D],source: FloorPlan.FloorOutlineSource) {
        var captured: [[Point2D]] = []
        for floor in scan.floors where floor.polygonCorners.count >= 3 {
            let world = floor.polygonCorners.map { c -> Point2D in
                let p = floor.transform * SIMD4<Float>(c.x,c.y,c.z,1)
                return Point2D(projecting: SIMD3(p.x,p.y,p.z))
            }
            guard world.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { continue }
            let poly = Polygon2D.simplified(world,tolerance: 0.01)
            if poly.count >= 3,Polygon2D.area(poly) > 0.01,Polygon2D.triangulation(poly).1 {
                captured.append(poly)
            }
        }
        if let poly = captured.max(by: { Polygon2D.area($0) < Polygon2D.area($1) }) {
            return (Polygon2D.signedArea(poly) < 0 ? poly.reversed() : poly,.capturedSurface)
        }
        if let chained = Polygon2D.chain(walls.map(\.segment),tolerance: chainTolerance),Polygon2D.triangulation(chained).1 {
            return (Polygon2D.signedArea(chained) < 0 ? chained.reversed() : chained,.wallBoundary)
        }
        let b = Rect2D.bounding(walls.flatMap { [$0.start,$0.end] })
        guard !b.isEmpty else { return ([],.boundsEstimate) }
        return ([.init(x: b.minX,y: b.minY),.init(x: b.maxX,y: b.minY),.init(x: b.maxX,y: b.maxY),.init(x: b.minX,y: b.maxY)],.boundsEstimate)
    }

    /// Floor elevation: `floor` surface if present, otherwise bottom of walls.
    private func floorLevel(of scan: ScanInput) -> Double {
        if let f = scan.floors.first { return Double(f.transform.translation.y) }
        let bottoms = scan.walls.map { Double($0.transform.translation.y) - Double($0.dimensions.y) / 2 }
        return bottoms.min() ?? 0
    }

    // MARK: - Helpers

    /// 'Width' direction of a surface projected to ground (local X axis → plan).
    private func planarDirection(of t: simd_float4x4) -> Point2D {
        let a = t.xAxis
        let d = Point2D(x: Double(a.x), y: -Double(a.z)).normalized
        return d.length > 0 ? d : Point2D(x: 1, y: 0)
    }
}

private extension Point2D {
    var angle: Double { atan2(y, x) }
}
