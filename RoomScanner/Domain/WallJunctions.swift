import Foundation

/// Joins nearby centerlines, then partitions solid footprints deterministically.
/// Exporters must use footprints, rather than overlapping centerline boxes.
enum WallJunctions {
    static func resolve(_ walls: inout [ResolvedWall]) {
        let originals = walls
        for i in walls.indices {
            let segment = originals[i].segment
            var endpoints = [segment.start, segment.end]
            for endpoint in endpoints.indices {
                let originalEndpoint = endpoints[endpoint]
                var nearest = Double.infinity
                for j in originals.indices where i != j {
                    let other = originals[j].segment
                    let d = segment.direction, e = other.direction
                    let denominator = cross(d, e)
                    guard abs(denominator) > 0.05 else { continue }
                    let t = cross(other.start - segment.start, e) / denominator
                    let point = segment.start + d * t
                    let distance = originalEndpoint.distance(to: point)
                    let tolerance = (originals[i].thickness + originals[j].thickness) / 2 + 0.02
                    guard distance <= tolerance, distance < nearest,
                          other.distance(to: point) <= tolerance else { continue }
                    endpoints[endpoint] = point
                    nearest = distance
                }
            }
            if dot(endpoints[1] - endpoints[0], segment.direction) > 0.000001 {
                walls[i].segment = Segment2D(start: endpoints[0], end: endpoints[1])
            }
        }
        var occupied: [[Point2D]] = []
        for i in walls.indices {
            let segment = walls[i].segment
            let n = segment.leftNormal * (walls[i].thickness / 2)
            // Counterclockwise footprint for half-plane clipping.
            func corner(_ point:Point2D,_ offset:Point2D,_ away:Point2D) -> Point2D {
                let partners = walls.indices.filter { j in
                    j != i && (walls[j].segment.start.distance(to:point) < 1e-6 || walls[j].segment.end.distance(to:point) < 1e-6)
                        && abs(cross(segment.direction,walls[j].segment.direction)) > 0.05
                }
                guard partners.count == 1,let j = partners.first else { return point+offset }
                let other = walls[j].segment
                let otherAway = other.start.distance(to:point) < 1e-6 ? other.direction : other.direction * -1
                let side = (dot(offset,otherAway) >= 0 ? 1.0 : -1.0) * (dot(other.leftNormal,away) >= 0 ? 1.0 : -1.0)
                let partnerOffset = other.leftNormal * (walls[j].thickness/2*side)
                let origin = point+offset
                let distance = cross(point+partnerOffset-origin,other.direction)/cross(segment.direction,other.direction)
                guard abs(distance) <= 2*(walls[i].thickness+walls[j].thickness) else { return origin }
                return origin+segment.direction*distance
            }
            var pieces = [[corner(segment.start,n * -1,segment.direction),
                           corner(segment.end,n * -1,segment.direction * -1),
                           corner(segment.end,n,segment.direction * -1),
                           corner(segment.start,n,segment.direction)]]
            for footprint in occupied {
                pieces = pieces.flatMap { subtract($0, convex: footprint) }
            }
            walls[i].footprints = pieces
            occupied += pieces
        }
    }

    /// Disjoint convex pieces of subject outside a convex clip polygon.
    static func subtract(_ subject: [Point2D], convex clip: [Point2D]) -> [[Point2D]] {
        guard subject.count >= 3,clip.count >= 3 else { return subject.count >= 3 ? [subject] : [] }
        let clip = Polygon2D.signedArea(clip) < 0 ? Array(clip.reversed()) : clip
        let a = Rect2D.bounding(subject),b = Rect2D.bounding(clip)
        guard a.minX < b.maxX,a.maxX > b.minX,a.minY < b.maxY,a.maxY > b.minY else { return [subject] }
        var intersection = subject
        for index in clip.indices {
            intersection = halfPlane(intersection,a:clip[index],b:clip[(index+1)%clip.count],inside:true)
            if intersection.count < 3 { return [subject] }
        }
        let overlap = Polygon2D.area(intersection)
        guard overlap > 1e-10 else { return [subject] }
        if abs(Polygon2D.area(subject)-overlap) <= 1e-10 { return [] }
        var remaining = subject
        var result: [[Point2D]] = []
        for index in clip.indices {
            let a = clip[index], b = clip[(index + 1) % clip.count]
            let outside = halfPlane(remaining, a: a, b: b, inside: false)
            if outside.count >= 3, Polygon2D.area(outside) > 1e-10 { result.append(outside) }
            remaining = halfPlane(remaining, a: a, b: b, inside: true)
            if remaining.count < 3 { break }
        }
        return result
    }

    private static func halfPlane(_ polygon: [Point2D], a: Point2D, b: Point2D, inside: Bool) -> [Point2D] {
        guard let last = polygon.last else { return [] }
        var previous = last
        var result: [Point2D] = []
        func distance(_ p: Point2D) -> Double { cross(b - a, p - a) * (inside ? 1 : -1) }
        for point in polygon {
            let before = distance(previous), after = distance(point)
            if (before >= 0) != (after >= 0) {
                result.append(previous + (point - previous) * (before / (before - after)))
            }
            if after >= 0 { result.append(point) }
            previous = point
        }
        return result
    }

    private static func cross(_ a: Point2D, _ b: Point2D) -> Double { a.x * b.y - a.y * b.x }
    private static func dot(_ a: Point2D, _ b: Point2D) -> Double { a.x * b.x + a.y * b.y }
}
