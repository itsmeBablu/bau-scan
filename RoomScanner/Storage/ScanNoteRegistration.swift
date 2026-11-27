import Foundation

/// Apply the same capture-to-display registration as survey photographs.
enum ScanNoteRegistration {
    static func registered(_ notes:[ARNote],house:House,scans:[ScanInput],singleRoom:Bool) -> [ARNote] {
        notes.map { original in
            var note = original
            guard let point = note.position else { return note }
            let room = house.allRooms.first { Polygon2D.contains($0.floorPolygon.map($0.transform.apply),.init(x:point.x,y:-point.z)) && ($0.id == note.roomID || $0.sourceCaptureID == note.roomID) } ?? house.allRooms.first { $0.id == note.roomID } ?? house.allRooms.first { Polygon2D.contains($0.floorPolygon.map($0.transform.apply),.init(x:point.x,y:-point.z)) }
            guard let room,let scan = scans.first(where:{ $0.id == (room.sourceCaptureID ?? room.id) }) else { return note }
            var rotation = room.transform.rotation
            if singleRoom,let longest = scan.walls.max(by:{ $0.dimensions.x < $1.dimensions.x }) {
                var theta = atan2(-Double(longest.transform.columns.0.z),Double(longest.transform.columns.0.x))
                while theta > .pi/2 { theta -= .pi }; while theta <= -.pi/2 { theta += .pi }
                rotation -= theta
            }
            let c = cos(rotation),s = sin(rotation)
            if note.displayPosition == nil { note.displayPosition = .init(x:c*point.x+s*point.z+room.transform.translation.x,y:point.y-StoryDetector.floorHeight(of:scan),z:-s*point.x+c*point.z-room.transform.translation.y) }
            if note.displayCameraPosition == nil,let camera = note.cameraPosition {
                note.displayCameraPosition = .init(x:c*camera.x+s*camera.z+room.transform.translation.x,y:camera.y-StoryDetector.floorHeight(of:scan),z:-s*camera.x+c*camera.z-room.transform.translation.y)
            }
            if let point = note.displayPosition { note.displayPosition = contained(point,in:room) }
            if let camera = note.displayCameraPosition { note.displayCameraPosition = contained(camera,in:room) }
            note.level = room.story; note.roomID = room.id
            return note
        }
    }
    /// Display-only correction; original observed coordinates remain intact.
    static func contained(_ point:TechnicalPoint3,in room:FloorPlan) -> TechnicalPoint3 {
        let polygon = room.floorPolygon.map(room.transform.apply)
        let p = Point2D(x:point.x,y:-point.z)
        var corrected = p
        if polygon.count >= 3,!Polygon2D.contains(polygon,p) {
            let candidates = polygon.indices.map { i -> Point2D in
                let a = polygon[i],b = polygon[(i+1)%polygon.count],delta = b-a
                let length = delta.x*delta.x+delta.y*delta.y
                let t = length > 0 ? min(1,max(0,((p.x-a.x)*delta.x+(p.y-a.y)*delta.y)/length)) : 0
                return a+delta*t
            }
            if let nearest = candidates.min(by:{ $0.distance(to:p) < $1.distance(to:p) }) {
                let interior = Polygon2D.interiorPoint(polygon,fallback:room.transform.apply(room.floorBounds.center))
                corrected = nearest+(interior-nearest).normalized*0.015
            }
        }
        let height = room.walls.map(\.height).max() ?? room.ceilingHeight.upperBound
        return .init(x:corrected.x,y:min(max(0.015,height-0.015),max(0.015,point.y)),z:-corrected.y)
    }

}
