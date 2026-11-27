import Foundation

enum ScanNoteRegistration {
    /// Resolve against the complete capture before the viewer selects a story.
    static func registered(_ notes: [ARNote], house: House, scans: [ScanInput], singleRoom: Bool) -> [ARNote] {
        struct Frame {
            let room: FloorPlan
            let polygon: [Point2D]
            let floor: Double?
            let transform: Transform2D
            func display(_ raw: TechnicalPoint3) -> TechnicalPoint3? {
                guard let floor else { return nil }
                let p = transform.apply(.init(x: raw.x, y: -raw.z))
                return .init(x: p.x, y: raw.y - floor, z: -p.y)
            }
        }
        let frames = house.allRooms.compactMap { room -> Frame? in
            let polygon = room.floorPolygon.map(room.transform.apply)
            guard Polygon2D.area(polygon) > 0, room.ceilingHeight.upperBound > 0 else { return nil }
            let scan = scans.first { $0.id == (room.sourceCaptureID ?? room.id) }
            var transform = room.transform
            if singleRoom, let longest = scan?.walls.max(by: { $0.dimensions.x < $1.dimensions.x }) {
                var angle = atan2(-Double(longest.transform.columns.0.z), Double(longest.transform.columns.0.x))
                while angle > .pi/2 { angle -= .pi }
                while angle <= -.pi/2 { angle += .pi }
                transform.rotation -= angle
            }
            return Frame(room: room, polygon: polygon, floor: scan.map { StoryDetector.floorHeight(of: $0) }, transform: transform)
        }
        return notes.map { original in
            var note = original
            note.displayPosition = nil
            note.displayCameraPosition = nil
            note.markerIconPosition = nil
            let candidates = frames.filter { frame in
                if let id = original.roomID {
                    return frame.room.id == id || frame.room.sourceCaptureID == id
                }
                return original.level == nil || frame.room.story == original.level
            }
            let owners = original.elementID.map { id in
                candidates.filter { f in f.room.walls.contains { $0.id == id } ||
                    f.room.openings.contains { $0.id == id } || f.room.objects.contains { $0.id == id } }
            } ?? []
            let matches = (owners.isEmpty ? candidates : owners).compactMap { frame -> (Frame, TechnicalPoint3, Double)? in
                guard let point = original.displayPosition ?? original.position.flatMap(frame.display) else { return nil }
                let p = Point2D(x: point.x, y: -point.z)
                let inside = Polygon2D.contains(frame.polygon, p)
                let distance = inside ? 0 : frame.polygon.indices.map { i in
                    Segment2D(start: frame.polygon[i], end: frame.polygon[(i + 1) % frame.polygon.count]).distance(to: p)
                }.min() ?? .infinity
                // An unidentified legacy anchor must have spatial evidence for its room.
                if original.roomID == nil && (distance > 0.02 || point.y < -0.15 || point.y > frame.room.ceilingHeight.upperBound + 0.15) { return nil }
                return (frame, point, distance)
            }
            guard let distance = matches.map({ $0.2 }).min() else { return note }
            let adjacent = matches.filter { $0.2 <= distance + 0.001 }
            // A tap on a shared wall belongs to the side from which it was observed.
            let cameraRooms = adjacent.filter { frame, _, _ in
                guard let camera = original.cameraPosition.flatMap(frame.display) else { return false }
                return camera.y >= -0.15 && camera.y <= frame.room.ceilingHeight.upperBound + 0.15 &&
                    Polygon2D.contains(frame.polygon, .init(x: camera.x, y: -camera.z))
            }
            let ownersAtPoint = cameraRooms.count == 1 ? cameraRooms : adjacent
            guard let (frame, point, _) = ownersAtPoint.first,
                  ownersAtPoint.count == 1 || original.roomID != nil else { return note }
            let anchor = contained(onElement(original.elementID, point: point, room: frame.room), in: frame.room)
            note.displayPosition = anchor
            let offset = original.audioFileName == nil ? 0.12 : 0.28
            let top = frame.room.ceilingHeight.upperBound
            let radius = min(Double(AnnotationPresentation.iconSize) / 2, top / 2)
            note.markerIconPosition = .init(x: anchor.x, y: min(top - radius, max(radius, anchor.y + offset)), z: anchor.z)
            if let camera = original.displayCameraPosition ?? original.cameraPosition.flatMap(frame.display) {
                note.displayCameraPosition = contained(camera, in: frame.room)
            }
            note.level = frame.room.story
            note.roomID = frame.room.id
            return note
        }
    }

    /// Refine the hit against its identified face after RoomPlan finishes the scan.
    private static func onElement(_ id: UUID?, point: TechnicalPoint3, room: FloorPlan) -> TechnicalPoint3 {
        guard let id else { return point }
        let segment: Segment2D
        let heights: ClosedRange<Double>
        if let opening = room.openings.first(where: { $0.id == id }) {
            segment = opening.segment
            heights = opening.sillHeight...(opening.sillHeight + max(0, opening.height))
        } else if let wall = room.wall(withID: id) {
            segment = wall.segment
            heights = 0...max(0, wall.height)
        } else if let object = room.objects.first(where: { $0.id == id }) {
            let center = room.transform.apply(object.center)
            let angle = object.angle + room.transform.rotation
            let delta = Point2D(x: point.x, y: -point.z) - center
            let local = Transform2D(translation: .zero, rotation: -angle).apply(delta)
            let w = abs(object.size.width) / 2, d = abs(object.size.depth) / 2
            let bounded = Point2D(x: min(w, max(-w, local.x)), y: min(d, max(-d, local.y)))
            let p = Transform2D(translation: center, rotation: angle).apply(bounded)
            return .init(x: p.x, y: point.y, z: -p.y)
        } else { return point }
        let face = Segment2D(start: room.transform.apply(segment.start), end: room.transform.apply(segment.end))
        let p = face.closestPoint(to: .init(x: point.x, y: -point.z))
        return .init(x: p.x, y: min(heights.upperBound, max(heights.lowerBound, point.y)), z: -p.y)
    }

    /// Move a missed anchor toward the inside of its nearest edge. Check the
    /// candidate because an edge endpoint can also belong to a re-entrant corner.
    static func contained(_ point: TechnicalPoint3, in room: FloorPlan) -> TechnicalPoint3 {
        let polygon = room.floorPolygon.map(room.transform.apply)
        let p = Point2D(x: point.x, y: -point.z)
        var corrected = p
        if polygon.count >= 3, !Polygon2D.contains(polygon, p) {
            let winding: Double = Polygon2D.signedArea(polygon) >= 0 ? 1 : -1
            var best = Double.infinity
            for i in polygon.indices {
                let edge = Segment2D(start: polygon[i], end: polygon[(i + 1) % polygon.count])
                let length = edge.length
                guard length > 0 else { continue }
                let direction = edge.direction, delta = p - edge.start
                let inset = min(0.015, length / 4)
                let along = max(inset, min(length - inset, delta.x * direction.x + delta.y * direction.y))
                let candidate = edge.start + direction * along + edge.leftNormal * (winding * inset)
                let distance = candidate.distance(to: p)
                if distance < best && Polygon2D.contains(polygon, candidate) {
                    best = distance
                    corrected = candidate
                }
            }
            if !best.isFinite { corrected = Polygon2D.interiorPoint(polygon) }
        }
        let height = room.walls.map(\.height).max() ?? room.ceilingHeight.upperBound
        return .init(x: corrected.x, y: min(max(0.015, height - 0.015), max(0.015, point.y)), z: -corrected.y)
    }

    static func visible(_ notes: [ARNote], in house: House) -> [ARNote] {
        let rooms = Set(house.allRooms.map(\.id))
        return notes.filter { $0.displayPosition != nil && $0.roomID.map(rooms.contains) == true }
    }
}
