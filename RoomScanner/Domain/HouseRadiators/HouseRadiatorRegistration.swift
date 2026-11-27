import Foundation

/// Associates observations from the continuous House session with final RoomPlan rooms.
/// Independent close-up sessions must never be treated as registered House geometry.
enum HouseRadiatorRegistration {
    static func associate(_ observations: [HouseRadiator],house: House,structure: StructureInput) throws -> HouseRadiatorSurvey {
        var items: [HouseRadiator] = []
        for observation in observations {
            guard observation.frontCorners.count == 3, observation.capturedInHouseCoordinates == true else { throw HouseRadiatorSurvey.Failure.invalid }
            let point = Point2D(x: observation.wallSample.point.x,y: -observation.wallSample.point.z)
            let bottom = observation.frontCorners[0].y
            let rooms = house.allRooms.filter { room in
                guard let input = structure.rooms.first(where: { $0.id == (room.sourceCaptureID ?? room.id) }) else { return false }
                let floor = StoryDetector.floorHeight(of: input)
                return bottom >= floor-0.15 && bottom <= floor+room.ceilingHeight.upperBound
            }
            let front = (observation.frontCorners[0] + observation.frontCorners[1]) * 0.5
            let inside = rooms.filter {
                Polygon2D.contains($0.floorPolygon.map($0.transform.apply), .init(x: front.x, y: -front.z))
            }
            let eligible = inside.isEmpty ? (rooms.isEmpty ? house.allRooms : rooms) : inside
            let candidates = eligible.flatMap { room in room.walls.map { (room.id,$0,$0.segment.distance(to: point)) } }
            var item = observation
            if let nearest = candidates.min(by: { $0.2 < $1.2 }) {
                item.roomID = nearest.0; item.wallID = nearest.1.id
                if nearest.2 > 1 || rooms.isEmpty { item.notes += " Room/wall association is approximate; verify against the House scan." }
            } else if let room = eligible.first {
                item.roomID = room.id; item.wallID = nil
                item.notes += " No scanned wall was available for association."
            } else { throw HouseRadiatorSurvey.Failure.unassigned }
            item.houseFloorElevation = nil
            if let room = rooms.first(where: { $0.id == item.roomID }),
               let input = structure.rooms.first(where: { $0.id == (room.sourceCaptureID ?? room.id) }) {
                item.houseFloorElevation = StoryDetector.floorHeight(of: input)
            }
            items.append(item)
        }
        let result = HouseRadiatorSurvey(houseID: house.id,radiators: items)
        try result.validate(for: house)
        return result
    }
}
