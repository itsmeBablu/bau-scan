import Foundation

/// Convex room-owned floor pieces in house coordinates, with overlap removed.
/// Room measurement polygons are never modified.
enum HouseFloorGeometry {
    struct Piece {
        let roomID: UUID
        let polygon: [Point2D]
    }

    static func pieces(house: House) -> [Piece] {
        if house.stories.count > 1 {
            return house.stories.flatMap { pieces(house:House(id:house.id,name:house.name,stories:[$0])) }
        }
        var result: [Piece] = []
        for room in house.allRooms {
            let local: [Point2D]
            if room.floorPolygon.count >= 3,Polygon2D.triangulation(room.floorPolygon).complete { local = room.floorPolygon }
            else if !room.walls.isEmpty,!room.floorBounds.isEmpty {
                let b = room.floorBounds
                local = [.init(x:b.minX,y:b.minY),.init(x:b.maxX,y:b.minY),.init(x:b.maxX,y:b.maxY),.init(x:b.minX,y:b.maxY)]
            } else { local = [] }
            let polygon = local.map(room.transform.apply)
            var fragments = Polygon2D.triangulate(polygon).map { [polygon[$0.0], polygon[$0.1], polygon[$0.2]] }
            for occupied in result {
                fragments = fragments.flatMap { WallJunctions.subtract($0, convex: occupied.polygon) }
            }
            result += fragments.map { Piece(roomID: room.id, polygon: $0) }
        }
        return result
    }
}
