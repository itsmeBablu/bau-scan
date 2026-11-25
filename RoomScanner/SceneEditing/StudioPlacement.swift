import Foundation
import simd

/// Conservative oriented envelopes: touching is allowed; penetration beyond 2 mm is rejected.
/// This is a design aid, not an engineering clash report for the raw scan mesh.
enum StudioPlacement {
    /// Whole-object oriented box picking, including empty spaces between model parts.
    static func rayIntersection(_ item: SceneEditObject,origin: SIMD3<Double>,direction: SIMD3<Double>) -> Double? {
        let inverse = item.orientation.inverse
        let p = inverse.act(origin-SIMD3(item.position.x,item.position.y,item.position.z)),v = inverse.act(direction)
        let half = SIMD3(item.size.x,item.size.y,item.size.z)/2
        var near = 0.0,far = 1.0
        for axis in 0..<3 {
            if abs(v[axis]) < 1e-10 { if p[axis] < -half[axis] || p[axis] > half[axis] { return nil }; continue }
            let a = (-half[axis]-p[axis])/v[axis],b = (half[axis]-p[axis])/v[axis]
            near = max(near,min(a,b)); far = min(far,max(a,b))
            if near > far { return nil }
        }
        return near
    }
    enum Failure: LocalizedError {
        case overlap(String), floor, outsideFloor
        var errorDescription: String? {
            switch self {
            case .overlap(let name): "Placement overlaps \(name). Move it clear or explicitly enable Allow overlaps for an intentional connection."
            case .floor: "The object would extend below the design floor."
            case .outsideFloor: AppLanguage.text("studio.floor.outside")
            }
        }
    }
    static func corners(_ item: SceneEditObject) -> [SIMD3<Double>] {
        var result: [SIMD3<Double>] = []
        let center = SIMD3(item.position.x,item.position.y,item.position.z)
        for x in [-0.5,0.5] { for y in [-0.5,0.5] { for z in [-0.5,0.5] {
            result.append(center+item.orientation.act(SIMD3(x*item.size.x,y*item.size.y,z*item.size.z)))
        } } }
        return result
    }
    static func intersects(_ a: SceneEditObject,_ b: SceneEditObject) -> Bool {
        let delta = SIMD3(a.position.x-b.position.x,a.position.y-b.position.y,a.position.z-b.position.z)
        let radius = (simd_length(SIMD3(a.size.x,a.size.y,a.size.z))+simd_length(SIMD3(b.size.x,b.size.y,b.size.z)))/2
        if simd_length_squared(delta) > radius*radius { return false }
        let unit = [SIMD3<Double>(1,0,0),SIMD3(0,1,0),SIMD3(0,0,1)]
        let aa = unit.map { a.orientation.act($0) },bb = unit.map { b.orientation.act($0) }
        var axes = aa+bb
        for x in aa { for y in bb { let cross = simd_cross(x,y); if simd_length(cross) > 1e-8 { axes.append(simd_normalize(cross)) } } }
        let ac = corners(a),bc = corners(b)
        for axis in axes {
            let av = ac.map { simd_dot($0,axis) },bv = bc.map { simd_dot($0,axis) }
            if av.max()! <= bv.min()!+0.002 || bv.max()! <= av.min()!+0.002 { return false }
        }
        return true
    }
    static func conflicts(in document: SceneEditDocument,story: Int) -> [String] {
        let items = document.presentationObjects.filter { $0.story == story }
        var found: [String] = []
        for item in items {
            if let other = items.first(where: { $0.id != item.id && intersects(item,$0) }) {
                found.append(item.name+" ↔ "+other.name)
            } else if (try? check(item,in: document)) == nil { found.append(item.name+" ↔ shell / floor") }
            if found.count == 20 { break }
        }
        return found
    }
    static func check(_ item: SceneEditObject,in document: SceneEditDocument) throws {
        try item.validate()
        guard corners(item).allSatisfy({ $0.y >= -0.002 }) else { throw Failure.floor }
        guard footprintInside(item,in:document) else { throw Failure.outsideFloor }
        for other in document.presentationObjects where other.id != item.id && other.story == item.story {
            if intersects(item,other) { throw Failure.overlap(other.name) }
        }
        for wall in walls(document,story: item.story) {
            if intersects(item,wall) { throw Failure.overlap("a scanned wall") }
        }
    }
    private static func walls(_ document: SceneEditDocument,story: Int) -> [SceneEditObject] {
        document.architecturalShell.stories.filter { $0.index == story }.flatMap(\.rooms).flatMap { room in
            room.walls.filter { document.includesElement($0.id) }.flatMap { wall in WallGeometry().wallBoxes(wall,openings: room.openings.filter { $0.wallID == wall.id }).map { box in
                let center = room.transform.apply(box.segment.midpoint)
                return SceneEditObject(origin: "Shell",name: "Wall",family: .box,position: .init(x: center.x,y: (box.top+box.bottom)/2,z: -center.y),size: .init(x: box.segment.length,y: box.height,z: box.thickness),yaw: box.segment.angle+room.transform.rotation,story: story)
            } }
        }
    }
    static func snapped(_ item: SceneEditObject,in document: SceneEditDocument,axis: TechnicalPointEditing.Axis = .free) -> SceneEditObject {
        var result = item
        if axis == .y { result.position.y = (result.position.y/0.05).rounded()*0.05; return result }
        result.position.x = (result.position.x/0.05).rounded()*0.05
        result.position.z = (result.position.z/0.05).rounded()*0.05
        var closest = 0.12
        for wall in walls(document,story: item.story) {
            let normal = wall.orientation.act(SIMD3<Double>(0,0,1)),along = wall.orientation.act(SIMD3<Double>(1,0,0))
            let center = SIMD3(result.position.x,result.position.y,result.position.z)
            let origin = SIMD3(wall.position.x,wall.position.y,wall.position.z)
            let distance = simd_dot(center-origin,normal)
            let extent = corners(result).map { abs(simd_dot($0-center,normal)) }.max() ?? 0
            guard abs(simd_dot(center-origin,along)) <= wall.size.x/2 else { continue }
            let offset = (distance >= 0 ? 1.0 : -1.0)*(extent+wall.size.z/2)-distance
            if abs(offset) < closest {
                let adjusted = center+normal*offset
                result.position.x = adjusted.x; result.position.z = adjusted.z
                closest = abs(offset)
            }
        }
        if axis == .x { result.position.y = item.position.y; result.position.z = item.position.z }
        if axis == .z { result.position.x = item.position.x; result.position.y = item.position.y }
        return result
    }
    static func floorPolygons(_ document: SceneEditDocument,story: Int) -> [[Point2D]] {
        document.architecturalShell.allRooms.filter { $0.story == story }.flatMap { room -> [[Point2D]] in
            let regions = document.floorRegions?.filter { $0.roomID == room.id }.map(\.polygon) ?? []
            return (regions.isEmpty ? [room.floorPolygon] : regions).filter { $0.count >= 3 }.map { $0.map(room.transform.apply) }
        }
    }
    static func footprintInside(_ item: SceneEditObject,in document: SceneEditDocument) -> Bool {
        let polygons = floorPolygons(document,story:item.story)
        guard !polygons.isEmpty else { return false }
        let projected = corners(item).map { Point2D(x:$0.x,y:-$0.z) }
        guard corners(item).allSatisfy({ corner in
            let point = Point2D(x:corner.x,y:-corner.z)
            return polygons.contains { polygon in
                Polygon2D.contains(polygon,point) || polygon.indices.contains { i in
                    Segment2D(start:polygon[i],end:polygon[(i+1)%polygon.count]).distance(to:point) <= 0.002
                }
            }
        }) else { return false }
        // Corners alone miss concave notches and holes inside the box projection.
        let points = Array(Set(projected)).sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ a: Point2D,_ b: Point2D,_ c: Point2D) -> Double { (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x) }
        func chain(_ points: [Point2D]) -> [Point2D] {
            var result: [Point2D] = []
            for p in points { while result.count >= 2 && cross(result[result.count-2],result[result.count-1],p) <= 0 { result.removeLast() }; result.append(p) }
            return result
        }
        let hull = Array(chain(points).dropLast())+Array(chain(Array(points.reversed())).dropLast())
        var remaining = [hull]
        for polygon in polygons {
            let triangulation = Polygon2D.triangulation(polygon)
            guard triangulation.complete else { return false }
            for (a,b,c) in triangulation.triangles {
                remaining = remaining.flatMap { subtract($0,triangle:[polygon[a],polygon[b],polygon[c]]) }
                guard remaining.count <= 10_000 else { return false }
                if remaining.isEmpty { return true }
            }
        }
        return remaining.reduce(0) { $0+Polygon2D.area($1) } <= 1e-8
    }
    private static func subtract(_ subject: [Point2D],triangle: [Point2D]) -> [[Point2D]] {
        var inside = subject,outside: [[Point2D]] = []
        for i in triangle.indices {
            let a = triangle[i],b = triangle[(i+1)%3]
            func side(_ p: Point2D) -> Double { (b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x) }
            var keep: [Point2D] = [],remove: [Point2D] = []
            guard var previous = inside.last else { break }
            for point in inside {
                let u = side(previous),v = side(point)
                if (u >= 0) != (v >= 0) {
                    let t = u/(u-v),hit = previous+(point-previous)*t
                    keep.append(hit); remove.append(hit)
                }
                if v >= 0 { keep.append(point) } else { remove.append(point) }
                previous = point
            }
            if remove.count >= 3,Polygon2D.area(remove) > 1e-10 { outside.append(remove) }
            inside = keep
        }
        return outside
    }
    static func available(_ item: SceneEditObject,in document: SceneEditDocument,allowOverlap: Bool) throws -> SceneEditObject {
        try item.validate()
        guard corners(item).allSatisfy({ $0.y >= -0.002 }) else { throw Failure.floor }
        if footprintInside(item,in:document) && (allowOverlap || (try? check(item,in:document)) != nil) { return item }
        let polygons = floorPolygons(document,story:item.story)
        guard let largest = polygons.max(by:{ Polygon2D.area($0) < Polygon2D.area($1) }) else { throw Failure.floor }
        var origin = item
        let center = Polygon2D.interiorPoint(largest)
        origin.position.x = center.x; origin.position.z = -center.y
        let step = max(item.size.x,item.size.z,0.5)+0.1
        for radius in 0...8 { for x in -radius...radius { for z in -radius...radius where abs(x) == radius || abs(z) == radius {
            var candidate = origin
            candidate.position.x += Double(x)*step; candidate.position.z += Double(z)*step
            guard footprintInside(candidate,in:document) else { continue }
            if allowOverlap || (try? check(candidate,in: document)) != nil { return candidate }
        } } }
        throw Failure.overlap("existing geometry; no free position was found")
    }
}
