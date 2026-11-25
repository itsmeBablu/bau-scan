import Foundation

/// Shared solid definition for drawing and mesh export. Opening cuts are
/// projected onto their resolved host and applied to every junction fragment.
struct ResolvedWallGeometry {
    struct Solid {
        let wallID: Int
        let footprint: [Point2D]
        let bottom: Double
        let top: Double
    }

    static func solids(house: House, graph: HouseWallGraph) -> [Solid] {
        var result: [Solid] = []
        for wall in graph.walls {
            let rooms = house.allRooms.filter {
                wall.roomIdsOnSideA.contains($0.id) || wall.roomIdsOnSideB.contains($0.id)
            }
            let height = rooms.flatMap { room in
                room.walls.filter { wall.sourceWallIds.contains($0.id) }.map(\.height)
            }.max() ?? 0
            guard height > 0 else { continue }
            var openings: [(start: Double, end: Double, bottom: Double, top: Double)] = []
            for room in rooms {
                for opening in room.openings {
                    guard graph.openingHosts.contains(where: {
                        $0.roomID == room.id && $0.openingID == opening.id && $0.wallIDs.contains(wall.id)
                    }) else { continue }
                    let center = room.transform.apply(opening.center)
                    let segment = opening.segment
                    let first = room.transform.apply(segment.start)
                    let last = room.transform.apply(segment.end)
                    let a = projection(first, on: wall.segment)
                    let b = projection(last, on: wall.segment)
                    let bottom = opening.kind == .door ? 0 : max(0, opening.sillHeight)
                    guard center.x.isFinite, center.y.isFinite else { continue }
                    openings.append((min(a, b), max(a, b), bottom, min(height, bottom + opening.height)))
                }
            }
            let levels = Array(Set([0, height] + openings.flatMap { [$0.bottom, $0.top] }.filter { $0 >= 0 && $0 <= height })).sorted()
            for (bottom, top) in zip(levels, levels.dropFirst()) where top > bottom {
                let cuts = openings.filter { $0.bottom < top && $0.top > bottom }.sorted { $0.start < $1.start }
                for footprint in wall.footprints {
                    var pieces = [footprint]
                    for cut in cuts {
                        pieces = pieces.flatMap { polygon in
                            [clip(polygon, segment: wall.segment, at: cut.start, keepAfter: false),
                             clip(polygon, segment: wall.segment, at: cut.end, keepAfter: true)]
                                .filter { $0.count >= 3 && Polygon2D.area($0) > 1e-10 }
                        }
                    }
                    result += pieces.map { Solid(wallID: wall.id, footprint: $0, bottom: bottom, top: top) }
                }
            }
        }
        return result
    }

    private static func projection(_ point: Point2D, on segment: Segment2D) -> Double {
        let delta = point - segment.start
        return delta.x * segment.direction.x + delta.y * segment.direction.y
    }

    private static func clip(_ polygon: [Point2D], segment: Segment2D, at boundary: Double, keepAfter: Bool) -> [Point2D] {
        guard var previous = polygon.last else { return [] }
        var result: [Point2D] = []
        func distance(_ point: Point2D) -> Double {
            (projection(point, on: segment) - boundary) * (keepAfter ? 1 : -1)
        }
        for point in polygon {
            let a = distance(previous), b = distance(point)
            if (a >= 0) != (b >= 0) {
                result.append(previous + (point - previous) * (a / (a - b)))
            }
            if b >= 0 { result.append(point) }
            previous = point
        }
        return result
    }
}
