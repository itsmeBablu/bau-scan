import Foundation
import simd

/// 2D plan point in meters. Coordinates: X right, Y up on the
/// sheet. A RoomPlan point (x, y, z) projects to (x, -z): top-down view.
struct Point2D: Codable, Equatable, Hashable {
    var x: Double
    var y: Double

    static let zero = Point2D(x: 0, y: 0)

    init(x: Double, y: Double) { self.x = x; self.y = y }

    /// Ground projection of a RoomPlan position (Y up, floor = XZ plane).
    init(projecting v: SIMD3<Float>) { self.init(x: Double(v.x), y: -Double(v.z)) }

    func distance(to other: Point2D) -> Double { (self - other).length }
    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: Point2D { let l = length; return l > 0 ? Point2D(x: x / l, y: y / l) : .zero }

    static func + (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Point2D, k: Double) -> Point2D { Point2D(x: a.x * k, y: a.y * k) }

    func isClose(to other: Point2D, tolerance: Double) -> Bool { distance(to: other) <= tolerance }
}

struct Size2D: Codable, Equatable, Hashable {
    var width: Double
    var depth: Double
}

/// Oriented 2D segment (start → end).
struct Segment2D: Codable, Equatable, Hashable {
    var start: Point2D
    var end: Point2D

    var length: Double { start.distance(to: end) }
    var midpoint: Point2D { (start + end) * 0.5 }
    var direction: Point2D { (end - start).normalized }
    /// Segment angle relative to X axis, in radians, in ]-π, π].
    var angle: Double { atan2(end.y - start.y, end.x - start.x) }
    /// Unit normal to the left of traversal direction.
    var leftNormal: Point2D { let d = direction; return Point2D(x: -d.y, y: d.x) }

    /// Distance from point to segment (clamped to endpoints).
    func distance(to p: Point2D) -> Double {
        let ab = end - start
        let ab2 = ab.x * ab.x + ab.y * ab.y
        guard ab2 > 0 else { return start.distance(to: p) }
        let t = max(0, min(1, ((p.x - start.x) * ab.x + (p.y - start.y) * ab.y) / ab2))
        return p.distance(to: start + ab * t)
    }
}

/// Axis-aligned bounding box, in meters.
struct Rect2D: Codable, Equatable, Hashable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    static let empty = Rect2D(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)

    var isEmpty: Bool { minX > maxX || minY > maxY }
    var width: Double { isEmpty ? 0 : maxX - minX }
    var height: Double { isEmpty ? 0 : maxY - minY }
    var center: Point2D { Point2D(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }

    func union(_ p: Point2D) -> Rect2D {
        Rect2D(minX: min(minX, p.x), minY: min(minY, p.y), maxX: max(maxX, p.x), maxY: max(maxY, p.y))
    }

    func insetBy(_ d: Double) -> Rect2D {
        Rect2D(minX: minX - d, minY: minY - d, maxX: maxX + d, maxY: maxY + d)
    }

    static func bounding(_ points: [Point2D]) -> Rect2D {
        points.reduce(.empty) { $0.union($1) }
    }
}

enum Polygon2D {
    /// Signed area (shoelace formula); positive if contour is traversed
    /// counterclockwise. Returns 0 for fewer than 3 points.
    static func signedArea(_ pts: [Point2D]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var s = 0.0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    static func area(_ pts: [Point2D]) -> Double { abs(signedArea(pts)) }

    /// Geometric center (centroid) of a 2D polygon.
    static func centroid(_ pts: [Point2D]) -> Point2D {
        guard pts.count >= 3 else { return pts.first ?? .zero }
        var cx = 0.0, cy = 0.0
        let a6 = 6 * signedArea(pts)
        guard abs(a6) > 1e-12 else {
            let sum = pts.reduce(Point2D.zero, +)
            return sum * (1.0 / Double(pts.count))
        }
        for i in pts.indices {
            let p0 = pts[i], p1 = pts[(i + 1) % pts.count]
            let cross = p0.x * p1.y - p1.x * p0.y
            cx += (p0.x + p1.x) * cross
            cy += (p0.y + p1.y) * cross
        }
        return Point2D(x: cx / a6, y: cy / a6)
    }

    /// Guaranteed interior point of polygon for placing labels (name, area).
    static func interiorPoint(_ pts: [Point2D], fallback: Point2D = .zero) -> Point2D {
        guard pts.count >= 3 else { return fallback }
        let c = centroid(pts)
        if contains(pts, c) { return c }
        if contains(pts, fallback) { return fallback }
        // If centroid falls outside a concave room (e.g. L-shaped),
        // search for centroid of a valid triangle from ear-clipping triangulation.
        let tris = triangulate(pts)
        for (i, j, k) in tris {
            let triCenter = (pts[i] + pts[j] + pts[k]) * (1.0 / 3.0)
            if contains(pts, triCenter) { return triCenter }
        }
        return pts.first ?? fallback
    }

    /// Point-in-polygon test (ray casting parity).
    static func contains(_ pts: [Point2D], _ p: Point2D) -> Bool {
        guard pts.count >= 3 else { return false }
        var inside = false
        var j = pts.count - 1
        for i in pts.indices {
            let a = pts[i], b = pts[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Triangulation of a simple polygon (convex or concave, without holes) via
    /// ear clipping. Returns index triplets in `pts`.
    /// Removes nearly collinear vertices (chord distance < `tolerance`) and duplicates.
    /// RoomPlan produces floor polygons with 40+ vertices, most of which are collinear.
    static func simplified(_ pts: [Point2D], tolerance: Double = 0.01) -> [Point2D] {
        guard pts.count > 3 else { return pts }
        var out = pts
        var changed = true
        while changed && out.count > 3 {
            changed = false
            for i in out.indices {
                let a = out[(i + out.count - 1) % out.count], b = out[i], c = out[(i + 1) % out.count]
                let seg = Segment2D(start: a, end: c)
                if a.distance(to: b) < tolerance || seg.distance(to: b) < tolerance { out.remove(at: i); changed = true; break }
            }
        }
        return out
    }

    static func triangulate(_ pts: [Point2D]) -> [(Int, Int, Int)] { triangulation(pts).triangles }

    /// Like `triangulate`, reporting whether the whole polygon could be clipped (`complete`).
    /// `false` = degenerate contour (self-intersection, duplicate vertices): partial result.
    static func triangulation(_ pts: [Point2D]) -> (triangles: [(Int, Int, Int)], complete: Bool) {
        guard pts.count >= 3 else { return ([], false) }
        // Always processes in counterclockwise order.
        let ccw = signedArea(pts) >= 0
        var idx = Array(pts.indices)
        if !ccw { idx.reverse() }
        var tris: [(Int, Int, Int)] = []
        var guardCount = 0
        while idx.count > 3 && guardCount < 10_000 {
            guardCount += 1
            var earFound = false
            for i in idx.indices {
                let ia = idx[(i + idx.count - 1) % idx.count], ib = idx[i], ic = idx[(i + 1) % idx.count]
                let a = pts[ia], b = pts[ib], c = pts[ic]
                // Convex vertex?
                if cross(b - a, c - b) <= 1e-12 { continue }
                // No other vertex inside triangle?
                var contains = false
                for j in idx where j != ia && j != ib && j != ic {
                    if pointInTriangle(pts[j], a, b, c) { contains = true; break }
                }
                if contains { continue }
                tris.append((ia, ib, ic))
                idx.remove(at: i)
                earFound = true
                break
            }
            if !earFound { break }   // degenerate polygon: clean exit
        }
        var complete = idx.count == 3
        if idx.count == 3 {
            // Last triplet: ignored if flat (collinear vertices) to avoid NaN normal.
            let a = pts[idx[0]], b = pts[idx[1]], c = pts[idx[2]]
            if abs(cross(b - a, c - a)) > 1e-12 { tris.append((idx[0], idx[1], idx[2])) }
            else if tris.isEmpty { complete = false }
        }
        return (tris, complete)
    }

    /// Clips `subject` against a **convex** counterclockwise polygon
    /// (Sutherland-Hodgman). Convexity of clipper is required for
    /// algorithm validity: clipping is always performed using triangles from `triangulate`,
    /// never against an arbitrary concave room contour.
    static func clip(_ subject: [Point2D], byConvex clipper: [Point2D]) -> [Point2D] {
        guard subject.count >= 3, clipper.count >= 3 else { return [] }
        var out = subject
        for i in clipper.indices {
            if out.isEmpty { return [] }
            let a = clipper[i], b = clipper[(i + 1) % clipper.count]
            let input = out
            out.removeAll(keepingCapacity: true)
            var prev = input[input.count - 1]
            var prevInside = cross(b - a, prev - a) >= -1e-12
            for point in input {
                let inside = cross(b - a, point - a) >= -1e-12
                if inside != prevInside, let x = lineIntersection(prev, point, a, b) { out.append(x) }
                if inside { out.append(point) }
                prev = point; prevInside = inside
            }
        }
        return out
    }

    /// Intersection area of multiple simple polygons (0 if disjoint).
    static func intersectionArea(_ polygons: [[Point2D]]) -> Double {
        intersectionPieces(polygons).reduce(0) { $0 + area($1) }
    }

    /// Area of the **union** of multiple simple polygons via inclusion-exclusion with
    /// prunes early when intersection is empty. Adjacent rooms overlap
    /// slightly (wall thickness, scan boundary inaccuracy); summing their areas
    /// overestimates area — measured at +2.14 m² on initial real scans.
    static func unionArea(_ polygons: [[Point2D]]) -> Double {
        let polys = polygons.filter { $0.count >= 3 }
        guard !polys.isEmpty else { return 0 }
        var total = 0.0
        func walk(from start: Int, pieces: [[Point2D]], sign: Double) {
            total += sign * pieces.reduce(0) { $0 + area($1) }
            guard start < polys.count else { return }
            for j in start..<polys.count {
                let next = clipPieces(pieces, by: polys[j])
                if !next.isEmpty { walk(from: j + 1, pieces: next, sign: -sign) }
            }
        }
        for i in polys.indices { walk(from: i + 1, pieces: convexPieces(of: polys[i]), sign: 1) }
        return total
    }

    private static func intersectionPieces(_ polygons: [[Point2D]]) -> [[Point2D]] {
        let polys = polygons.filter { $0.count >= 3 }
        guard let first = polys.first else { return [] }
        var pieces = convexPieces(of: first)
        for poly in polys.dropFirst() {
            if pieces.isEmpty { return [] }
            pieces = clipPieces(pieces, by: poly)
        }
        return pieces
    }

    /// Each convex piece is iteratively clipped by each polygon triangle.
    private static func clipPieces(_ pieces: [[Point2D]], by polygon: [Point2D]) -> [[Point2D]] {
        let tris = convexPieces(of: polygon)
        guard !tris.isEmpty else { return [] }
        var out: [[Point2D]] = []
        for piece in pieces {
            for t in tris {
                let c = clip(piece, byConvex: t)
                if c.count >= 3, area(c) > 1e-12 { out.append(c) }
            }
        }
        return out
    }

    private static func convexPieces(of polygon: [Point2D]) -> [[Point2D]] {
        triangulate(polygon).map { [polygon[$0.0], polygon[$0.1], polygon[$0.2]] }
    }

    /// Intersection of segment `p1p2` with **line** `ab` (known to intersect
    /// construction: `p1` and `p2` lie on opposite sides of `ab`).
    private static func lineIntersection(_ p1: Point2D, _ p2: Point2D, _ a: Point2D, _ b: Point2D) -> Point2D? {
        let d1 = p2 - p1, d2 = b - a
        let den = cross(d1, d2)
        guard abs(den) > 1e-15 else { return nil }
        let t = cross(a - p1, d2) / den
        return Point2D(x: p1.x + d1.x * t, y: p1.y + d1.y * t)
    }

    private static func cross(_ u: Point2D, _ v: Point2D) -> Double { u.x * v.y - u.y * v.x }

    private static func pointInTriangle(_ p: Point2D, _ a: Point2D, _ b: Point2D, _ c: Point2D) -> Bool {
        let d1 = cross(b - a, p - a), d2 = cross(c - b, p - b), d3 = cross(a - c, p - c)
        let hasNeg = d1 < -1e-12 || d2 < -1e-12 || d3 < -1e-12
        let hasPos = d1 > 1e-12 || d2 > 1e-12 || d3 > 1e-12
        return !(hasNeg && hasPos)
    }

    static func perimeter(_ pts: [Point2D]) -> Double {
        guard pts.count >= 2 else { return 0 }
        return pts.indices.reduce(0.0) { $0 + pts[$1].distance(to: pts[($1 + 1) % pts.count]) }
    }

    /// Chains segments (walls) into a closed contour: each endpoint is
    /// connected to the nearest endpoint of an unused segment,
    /// within `tolerance`. Returns nil if chain does not close
    /// (missing wall, partial scan).
    static func chain(_ segments: [Segment2D], tolerance: Double) -> [Point2D]? {
        guard segments.count >= 3 else { return nil }
        var remaining = segments
        var current = remaining.removeFirst()
        var contour = [current.start, current.end]
        while !remaining.isEmpty {
            let tail = contour[contour.count - 1]
            var bestIndex: Int? = nil
            var bestDistance = tolerance
            var bestReversed = false
            for (i, seg) in remaining.enumerated() {
                let dStart = seg.start.distance(to: tail)
                let dEnd = seg.end.distance(to: tail)
                if dStart <= bestDistance { bestDistance = dStart; bestIndex = i; bestReversed = false }
                if dEnd <= bestDistance { bestDistance = dEnd; bestIndex = i; bestReversed = true }
            }
            guard let idx = bestIndex else { return nil }
            current = remaining.remove(at: idx)
            let next = bestReversed ? current.start : current.end
            contour.append(next)
        }
        // Closure: the final point must connect back to the first point.
        guard contour.first!.isClose(to: contour.last!, tolerance: tolerance) else { return nil }
        contour.removeLast()
        return contour
    }
}

extension simd_float4x4 {
    /// Translation (colonne 3).
    var translation: SIMD3<Float> { SIMD3(columns.3.x, columns.3.y, columns.3.z) }
    /// Local X axis (column 0), representing the 'width' direction of a RoomPlan surface.
    var xAxis: SIMD3<Float> { SIMD3(columns.0.x, columns.0.y, columns.0.z) }
    /// Axe Y local (colonne 1).
    var yAxis: SIMD3<Float> { SIMD3(columns.1.x, columns.1.y, columns.1.z) }
    /// Axe Z local (colonne 2).
    var zAxis: SIMD3<Float> { SIMD3(columns.2.x, columns.2.y, columns.2.z) }
}
