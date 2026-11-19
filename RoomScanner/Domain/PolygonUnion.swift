import Foundation

/// Exact vertical decomposition for simple polygons, including concave rooms.
/// Vertex and edge-intersection x coordinates delimit slabs in which union
/// cross-section length is linear. Midpoint integration is exact in each slab.
enum PolygonUnion {
    private struct Edge {
        let a: Point2D
        let b: Point2D
        func y(at x: Double) -> Double {
            a.y + (x - a.x) * (b.y - a.y) / (b.x - a.x)
        }
    }

    static func area(_ polygons: [[Point2D]]) -> Double {
        let polygons = polygons.filter { $0.count >= 3 }
        let edges = polygons.map { polygon in
            polygon.indices.map { Edge(a: polygon[$0], b: polygon[($0 + 1) % polygon.count]) }
        }
        let allEdges = edges.flatMap { $0 }
        var events = polygons.flatMap { $0.map(\.x) }
        for i in allEdges.indices {
            let first = allEdges[i]
            for j in allEdges.indices where j > i {
                let second = allEdges[j]
                let dx = first.b.x - first.a.x, dy = first.b.y - first.a.y
                let ex = second.b.x - second.a.x, ey = second.b.y - second.a.y
                let denominator = dx * ey - dy * ex
                guard abs(denominator) > 1e-12 else { continue }
                let qx = second.a.x - first.a.x, qy = second.a.y - first.a.y
                let t = (qx * ey - qy * ex) / denominator
                let u = (qx * dy - qy * dx) / denominator
                if t > 0, t < 1, u > 0, u < 1 {
                    events.append(first.a.x + t * dx)
                }
            }
        }
        events = Array(Set(events)).sorted()
        var total = 0.0
        for (left, right) in zip(events, events.dropFirst()) {
            guard right > left else { continue }
            let x = left + (right - left) / 2
            var intervals: [(Double, Double)] = []
            for polygonEdges in edges {
                let crossings = polygonEdges.filter {
                    min($0.a.x, $0.b.x) < x && x < max($0.a.x, $0.b.x)
                }.map { $0.y(at: x) }.sorted()
                for index in stride(from: 0, to: crossings.count - 1, by: 2) where index + 1 < crossings.count {
                    intervals.append((crossings[index], crossings[index + 1]))
                }
            }
            intervals.sort { $0.0 < $1.0 }
            guard var current = intervals.first else { continue }
            var length = 0.0
            for interval in intervals.dropFirst() {
                if interval.0 <= current.1 {
                    current.1 = max(current.1, interval.1)
                } else {
                    length += current.1 - current.0
                    current = interval
                }
            }
            length += current.1 - current.0
            total += (right - left) * length
        }
        return total
    }
}
