import Foundation

/// Small display mitres only at coincident solid wall endpoints. Scan dimensions remain untouched.
enum StudioWallJoins {
    static func mesh(room: FloorPlan,visible: Set<UUID>) -> TriangleMesh {
        let walls = room.walls.filter { visible.contains($0.id) }
        var result = TriangleMesh()
        for i in walls.indices {
            for j in walls.indices where j > i {
                let a = walls[i],b = walls[j]
                guard a.thickness > 0,b.thickness > 0 else { continue }
                let na = a.segment.leftNormal,nb = b.segment.leftNormal
                let determinant = na.x*nb.y-na.y*nb.x
                guard abs(determinant) > 0.15 else { continue }
                for pa in [a.start,a.end] { for pb in [b.start,b.end] where pa.distance(to: pb) <= 0.025 {
                    let height = min(a.height,b.height)
                    func solid(_ wall: Wall,_ point: Point2D) -> Bool {
                        WallGeometry().wallBoxes(wall,openings: room.openings.filter { $0.wallID == wall.id }).contains {
                            $0.bottom < 0.001 && $0.top >= height-0.001 && ($0.segment.start.distance(to: point) < 0.025 || $0.segment.end.distance(to: point) < 0.025)
                        }
                    }
                    guard solid(a,pa),solid(b,pb) else { continue }
                    let center = (pa+pb)*0.5
                    var polygon: [Point2D] = []
                    for sa in [-1.0,1.0] { for sb in [-1.0,1.0] {
                        let da = na.x*center.x+na.y*center.y+sa*a.thickness/2
                        let db = nb.x*center.x+nb.y*center.y+sb*b.thickness/2
                        let point = Point2D(x: (da*nb.y-na.y*db)/determinant,y: (na.x*db-da*nb.x)/determinant)
                        polygon.append(point)
                    } }
                    // Do not create long spikes at acute corners or bridge real unscanned gaps.
                    guard polygon.allSatisfy({ $0.distance(to: center) <= max(a.thickness,b.thickness)*2 }) else { continue }
                    polygon.sort { atan2($0.y-center.y,$0.x-center.x) < atan2($1.y-center.y,$1.x-center.x) }
                    // Add only the missing part of the corner, not coplanar caps over existing walls.
                    var pieces = [polygon]
                    for wall in [a,b] {
                        let n = wall.segment.leftNormal*(wall.thickness/2)
                        let rectangle = [wall.start+n,wall.end+n,wall.end-n,wall.start-n]
                        pieces = pieces.flatMap { subtract($0,rectangle) }
                    }
                    for piece in pieces where abs(Polygon2D.signedArea(piece)) > 1e-8 {
                      let average = piece.reduce(Point2D.zero,+)*(1/Double(piece.count))
                      let c = room.transform.apply(average)
                      for index in piece.indices {
                        let p = room.transform.apply(piece[index]),q = room.transform.apply(piece[(index+1)%piece.count])
                        let low = PlanMeshBuilder.point(p,y: 0),high = PlanMeshBuilder.point(p,y: height)
                        let nextLow = PlanMeshBuilder.point(q,y: 0),nextHigh = PlanMeshBuilder.point(q,y: height)
                        result.addQuad(low,high,nextHigh,nextLow)
                        result.addTriangle(PlanMeshBuilder.point(c,y: height),nextHigh,high)
                        result.addTriangle(PlanMeshBuilder.point(c,y: 0),low,nextLow)
                      }
                    }
                } }
            }
        }
        return result
    }
    private static func subtract(_ polygon: [Point2D],_ rectangle: [Point2D]) -> [[Point2D]] {
        let clip = Polygon2D.signedArea(rectangle) >= 0 ? rectangle : rectangle.reversed().map { $0 }
        var inside = polygon,outside: [[Point2D]] = []
        func halfPlane(_ points: [Point2D],_ a: Point2D,_ b: Point2D,keepInside: Bool) -> [Point2D] {
            guard !points.isEmpty else { return [] }
            func distance(_ p: Point2D) -> Double { (b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x) }
            var result: [Point2D] = []
            for i in points.indices {
                let p = points[i],q = points[(i+1)%points.count],dp = distance(p),dq = distance(q)
                let pin = keepInside ? dp >= 0 : dp <= 0,qin = keepInside ? dq >= 0 : dq <= 0
                if pin { result.append(p) }
                if pin != qin,abs(dp-dq) > 1e-12 { result.append(p+(q-p)*(dp/(dp-dq))) }
            }
            return result
        }
        for i in clip.indices {
            let a = clip[i],b = clip[(i+1)%clip.count]
            let part = halfPlane(inside,a,b,keepInside: false)
            if part.count >= 3 { outside.append(part) }
            inside = halfPlane(inside,a,b,keepInside: true)
        }
        return outside
    }
}
