import Foundation

/// Apply the same capture-to-display registration as survey photographs.
enum ScanNoteRegistration {
    static func registered(_ notes:[ARNote],house:House,scans:[ScanInput],singleRoom:Bool) -> [ARNote] {
        notes.map { original in
            var note = original
            guard note.displayPosition == nil,let point = note.position else { return note }
            let room = house.allRooms.first { $0.id == note.roomID } ?? house.allRooms.first { Polygon2D.contains($0.floorPolygon.map($0.transform.apply),.init(x:point.x,y:-point.z)) }
            guard let room,let scan = scans.first(where:{ $0.id == room.id }) else { return note }
            var rotation = room.transform.rotation
            if singleRoom,let longest = scan.walls.max(by:{ $0.dimensions.x < $1.dimensions.x }) {
                var theta = atan2(-Double(longest.transform.columns.0.z),Double(longest.transform.columns.0.x))
                while theta > .pi/2 { theta -= .pi }; while theta <= -.pi/2 { theta += .pi }
                rotation -= theta
            }
            let c = cos(rotation),s = sin(rotation)
            note.displayPosition = .init(x:c*point.x+s*point.z+room.transform.translation.x,y:point.y-StoryDetector.floorHeight(of:scan),z:-s*point.x+c*point.z-room.transform.translation.y)
            note.level = room.story
            return note
        }
    }
}
