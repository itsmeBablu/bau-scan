import Foundation

/// Presentation direction from the longest visible-room wall, in house plan
/// coordinates. Does not rotate floors, rooms or scan coordinates in storage.
enum FloorPatternDirection {
    static func angle(rooms: [FloorPlan]) -> Double {
        let segments = rooms.flatMap { room in
            room.walls.map { Segment2D(start: room.transform.apply($0.start), end: room.transform.apply($0.end)) }
        }.filter { $0.length.isFinite && $0.length > 1e-8 }
        func normalized(_ angle: Double) -> Double {
            let value = angle.truncatingRemainder(dividingBy: .pi)
            return value < 0 ? value + .pi : value
        }
        let wall = segments.sorted {
            if abs($0.length - $1.length) > 1e-7 { return $0.length > $1.length }
            return normalized($0.angle) < normalized($1.angle)
        }.first
        return wall.map { normalized($0.angle) } ?? 0
    }
}
