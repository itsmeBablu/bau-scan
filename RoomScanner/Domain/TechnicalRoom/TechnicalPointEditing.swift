import Foundation

enum TechnicalPointEditing {
    enum Axis: String, CaseIterable { case free, x, y, z, orthogonal }
    enum PointError: Error { case invalidPoint }
    static func adjust(_ point: TechnicalPoint3, origin: TechnicalPoint3?, axis: Axis, gridMetres: Double,
                       snapPoints: [TechnicalPoint3], snapDistance: Double = 0.05) throws -> TechnicalPoint3 {
        guard valid(point), gridMetres.isFinite, gridMetres >= 0, snapDistance.isFinite, snapDistance >= 0,
              origin.map(valid) ?? true else { throw PointError.invalidPoint }
        var result = snapPoints.filter(valid).min(by: { $0.distance(to: point) < $1.distance(to: point) })
            .flatMap { $0.distance(to: point) <= snapDistance ? $0 : nil } ?? point
        if gridMetres > 0 {
            result = .init(x: (result.x / gridMetres).rounded() * gridMetres, y: (result.y / gridMetres).rounded() * gridMetres, z: (result.z / gridMetres).rounded() * gridMetres)
        }
        if let origin {
            var lock = axis
            if lock == .orthogonal {
                let delta = [abs(result.x - origin.x), abs(result.y - origin.y), abs(result.z - origin.z)]
                lock = [Axis.x, .y, .z][delta.firstIndex(of: delta.max()!)!]
            }
            switch lock {
            case .x: result.y = origin.y; result.z = origin.z
            case .y: result.x = origin.x; result.z = origin.z
            case .z: result.x = origin.x; result.y = origin.y
            default: break
            }
        }
        guard valid(result) else { throw PointError.invalidPoint }
        return result
    }
    static func valid(_ point: TechnicalPoint3) -> Bool { [point.x, point.y, point.z].allSatisfy { $0.isFinite && abs($0) < 100_000 } }
}
