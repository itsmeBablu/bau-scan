import Foundation

/// Presentation projection only. Original net room dimensions, raw openings and
/// host relationships stay unchanged. Resolved wall segments are house-space.
enum PlanOpeningPlacement {
    static func window(_ opening: Opening, in room: FloorPlan, graph: HouseWallGraph) -> Opening {
        guard opening.kind == .window,
              let host = graph.openingHosts.first(where: { $0.roomID == room.id && $0.openingID == opening.id }) else { return opening }
        let center = room.transform.apply(opening.center)
        guard let wall = graph.walls.filter({ host.wallIDs.contains($0.id) })
            .min(by: { $0.segment.distance(to: center) < $1.segment.distance(to: center) }), wall.segment.length > 1e-8 else { return opening }
        let delta = center - wall.segment.start
        let along = delta.x * wall.segment.direction.x + delta.y * wall.segment.direction.y
        let projected = wall.segment.start + wall.segment.direction * along
        let local = projected - room.transform.translation
        let c = cos(room.transform.rotation), s = sin(room.transform.rotation)
        var result = opening
        result.center = .init(x: c * local.x + s * local.y, y: -s * local.x + c * local.y)
        result.angle = wall.segment.angle - room.transform.rotation
        return result
    }
}
