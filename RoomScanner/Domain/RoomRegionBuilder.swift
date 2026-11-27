import Foundation

/// Splits continuous captures only at observed walls spanning the floor contour.
/// Open-plan labels alone never create an invented partition or measured area.
enum RoomRegionBuilder {
    static func rooms(from plan:FloorPlan, scan:ScanInput) -> [FloorPlan] {
        guard plan.floorOutlineSource != .boundsEstimate,plan.floorPolygon.count >= 3,plan.walls.count <= 500 else { return [plan] }
        var regions = [plan.floorPolygon]
        for wall in plan.walls.sorted(by:{ $0.length > $1.length }) {
            regions = regions.flatMap { split($0,by:wall.segment) }
            guard regions.count <= 64 else { return [plan] }
        }
        guard regions.count > 1 else { return [plan] }
        let total = regions.reduce(0) { $0+Polygon2D.area($1) }
        guard abs(total-Polygon2D.area(plan.floorPolygon)) < 0.01 else { return [plan] }
        // Stable order/IDs for reopening and for photo/note room associations.
        regions.sort { a,b in
            let x = Rect2D.bounding(a).center,y = Rect2D.bounding(b).center
            return x.x == y.x ? x.y < y.y : x.x < y.x
        }
        return regions.enumerated().map { index,polygon in
            var room = plan
            room.id = identifier(plan.id,index:index); room.sourceCaptureID = scan.id
            room.floorPolygon = polygon; room.floorOutlineSource = .wallBoundary
            room.walls = polygon.indices.compactMap { i in
                let edge = Segment2D(start:polygon[i],end:polygon[(i+1)%polygon.count])
                guard var source = plan.walls.filter({ parallel($0.segment,edge) && $0.segment.distance(to:edge.midpoint) < 0.26 })
                    .min(by:{ $0.segment.distance(to:edge.midpoint) < $1.segment.distance(to:edge.midpoint) }) else { return nil }
                source.segment = edge; return source
            }
            room.openings = plan.openings.filter { opening in room.walls.contains { $0.id == opening.wallID && $0.segment.distance(to:opening.center) < 0.26 } }
            room.objects = plan.objects.filter { object in regions.firstIndex(where:{ Polygon2D.contains($0,object.center) }) == index }
            let labels = (scan.sections ?? []).filter { Polygon2D.contains(polygon,Point2D(projecting:$0.center)) }.map(\.label)
            room.label = labels.first(where:{ $0 != .unidentified }) ?? .unidentified
            room.name = RoomNaming().proposedName(for:labels,existingNames:[])
            return room
        }
    }

    private static func split(_ polygon:[Point2D],by wall:Segment2D) -> [[Point2D]] {
        guard wall.length > 0.5 else { return [polygon] }
        let normal = wall.leftNormal
        func distance(_ point:Point2D) -> Double {
            let delta = point-wall.start
            return delta.x*normal.x+delta.y*normal.y
        }
        var intersections:[Point2D] = []
        for i in polygon.indices {
            let a = polygon[i],b = polygon[(i+1)%polygon.count],da = distance(a),db = distance(b)
            if abs(da) < 0.00001 { intersections.append(a) }
            if da*db < -0.00000001 { intersections.append(a+(b-a)*(da/(da-db))) }
        }
        // A partial wall must not be extended across an unobserved opening.
        guard intersections.count == 2,intersections.allSatisfy({ wall.distance(to:$0) <= 0.25 }) else { return [polygon] }
        func clipped(sign:Double) -> [Point2D] {
            var result:[Point2D] = []
            for i in polygon.indices {
                let a = polygon[i],b = polygon[(i+1)%polygon.count],da = distance(a)*sign,db = distance(b)*sign
                if da >= 0 { result.append(a) }
                if (da >= 0) != (db >= 0) { result.append(a+(b-a)*(da/(da-db))) }
            }
            return Polygon2D.simplified(result,tolerance:0.001)
        }
        let a = clipped(sign:1),b = clipped(sign:-1)
        guard a.count >= 3,b.count >= 3,Polygon2D.area(a) >= 1,Polygon2D.area(b) >= 1,
              Polygon2D.triangulation(a).1,Polygon2D.triangulation(b).1 else { return [polygon] }
        return [a,b]
    }
    private static func parallel(_ a:Segment2D,_ b:Segment2D) -> Bool {
        abs(a.direction.x*b.direction.x+a.direction.y*b.direction.y) > 0.995
    }
    private static func identifier(_ source:UUID,index:Int) -> UUID {
        guard index > 0 else { return source }
        var bytes = source.uuid
        bytes.14 ^= UInt8((index >> 8)&255); bytes.15 ^= UInt8(index&255)
        return UUID(uuid:bytes)
    }
}
