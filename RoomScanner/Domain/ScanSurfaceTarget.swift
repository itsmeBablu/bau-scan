import Foundation
import simd

struct ScanSurfaceTarget: Equatable {
    let point: TechnicalPoint3
    var elementID: UUID? = nil

    /// Use a tracked opening's finite face for glass, where LiDAR may see through
    /// to the next room. A closer depth hit still wins (e.g. a chair before a wall).
    static func resolve(origin: SIMD3<Float>, direction: SIMD3<Float>, observed: SIMD3<Float>?, scan: ScanInput?) -> Self? {
        let ray = simd_normalize(direction)
        func target(_ p: SIMD3<Float>, id: UUID? = nil) -> Self {
            .init(point: .init(x: Double(p.x), y: Double(p.y), z: Double(p.z)), elementID: id)
        }
        var distance = observed.map { simd_distance(origin, $0) } ?? .infinity
        var result = observed.map { target($0) }
        guard let scan else { return result }
        if let observed {
            for object in scan.objects {
                let local = simd_inverse(object.transform) * SIMD4(observed, 1)
                let half = object.dimensions / 2
                if abs(local.x) <= half.x + 0.03, abs(local.y) <= half.y + 0.03, abs(local.z) <= half.z + 0.03 {
                    result = target(observed, id: object.id)
                    break
                }
            }
        }
        func intersection(_ s: ScanSurface) -> Float? {
            let inverse = simd_inverse(s.transform)
            let start = inverse * SIMD4(origin, 1), delta = inverse * SIMD4(ray, 0)
            guard abs(delta.z) > 1e-5 else { return nil }
            let t = -start.z / delta.z, p = start + delta * t
            guard t >= 0.1, t <= 8, abs(p.x) <= s.dimensions.x / 2, abs(p.y) <= s.dimensions.y / 2 else { return nil }
            if s.polygonCorners.count >= 3 {
                let contour = s.polygonCorners.map { Point2D(x: Double($0.x), y: Double($0.y)) }
                guard Polygon2D.contains(contour, .init(x: Double(p.x), y: Double(p.y))) else { return nil }
            }
            return t
        }
        let apertures = scan.openings.compactMap { surface in intersection(surface).map { (surface, $0) } }
        for surface in scan.walls {
            guard let t = intersection(surface), t < distance + (result?.elementID == nil ? 0.02 : 0),
                  !apertures.contains(where: { $0.0.parentID == surface.id || abs($0.1 - t) < 0.04 }) else { continue }
            distance = t
            result = target(origin + ray * t, id: surface.id)
        }
        for (surface,t) in apertures where surface.category != .opening && t <= distance + 0.02 {
            distance = t
            result = target(origin + ray * t, id: surface.id)
        }
        return result
    }
}
