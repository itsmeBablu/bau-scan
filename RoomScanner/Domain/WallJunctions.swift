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
            var pieces = [[segment.start - n, segment.end - n, segment.end + n, segment.start + n]]
            for footprint in occupied {
                pieces = pieces.flatMap { subtract($0, convex: footprint) }
            }
            walls[i].footprints = pieces
            occupied += pieces
        }
    }

    /// Disjoint convex pieces of subject outside a convex clip polygon.
    private static func subtract(_ subject: [Point2D], convex clip: [Point2D]) -> [[Point2D]] {
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
