import Foundation

/// RoomPlan confidence level, platform-neutral.
enum Confidence: String, Codable, Comparable {
    case low, medium, high
    private var rank: Int { switch self { case .low: 0; case .medium: 1; case .high: 2 } }
    static func < (a: Confidence, b: Confidence) -> Bool { a.rank < b.rank }
}

/// RoomPlan section label (`CapturedRoom.Section.Label`), platform-neutral.
enum RoomLabel: String, Codable, CaseIterable {
    case livingRoom, bedroom, bathroom, kitchen, diningRoom, unidentified
}

/// Planar placement of a room within house coordinates.
/// Identity in v1; computed by multi-room alignment in v2.
struct Transform2D: Codable, Equatable {
    var translation: Point2D
    /// Rotation around vertical axis, radians.
    var rotation: Double

    static let identity = Transform2D(translation: .zero, rotation: 0)

    func apply(_ p: Point2D) -> Point2D {
        let c = cos(rotation), s = sin(rotation)
        return Point2D(x: c * p.x - s * p.y + translation.x, y: s * p.x + c * p.y + translation.y)
    }
}

/// Wall: floor footprint segment + height. Thickness is not measured by
/// RoomPlan: constant visual thickness (`FloorPlan.defaultWallThickness`).
struct Wall: Codable, Equatable, Identifiable {
    var id: UUID
    var segment: Segment2D
    var height: Double
    var thickness: Double
    var confidence: Confidence

    var start: Point2D { segment.start }
    var end: Point2D { segment.end }
    var length: Double { segment.length }
}

/// Door, window, or opening, attached to a wall when provided by RoomPlan.
struct Opening: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case door, window, opening }
    var id: UUID
    var kind: Kind
    var wallID: UUID?
    var center: Point2D
    var width: Double
    var height: Double
    /// Parapet / sill height (bottom of opening above floor); 0 for a door.
    var sillHeight: Double
    /// Orientation in plan, radians ('width' axis).
    var angle: Double
    var confidence: Confidence

    /// Floor footprint of the opening.
    var segment: Segment2D {
        let d = Point2D(x: cos(angle), y: sin(angle)) * (width / 2)
        return Segment2D(start: center - d, end: center + d)
    }
}

/// Detected furniture/equipment represented by an oriented 2D box.
struct PlacedObject: Codable, Equatable, Identifiable {
    var id: UUID
    var category: String
    var center: Point2D
    var size: Size2D
    var height: Double
    var angle: Double
    var confidence: Confidence
}

/// Pivot model of a room. Meters, `Double`, pure Swift. Serialized in
/// `plan.json` to be readable without RoomPlan (Mac); recomputable from `room.json`.
struct FloorPlan: Codable, Equatable, Identifiable {
    /// 2: house area = union of rooms (not their sum), compound room names
    /// from all RoomPlan sections. House saved in v1 is renamed upon reading.
    static let schemaVersion = 2
    static let defaultWallThickness = 0.10
    /// Presentation slab only; not a measured structural floor thickness.
    static let defaultFloorSlabThickness = 0.05
    enum FloorOutlineSource: String,Codable { case capturedSurface, wallBoundary, boundsEstimate }

    var id: UUID
    var name: String
    var label: RoomLabel
    var story: Int
    var transform: Transform2D
    var walls: [Wall]
    var openings: [Opening]
    var objects: [PlacedObject]
    /// Floor polygon, counterclockwise order, empty if indeterminable.
    var floorPolygon: [Point2D]
    var ceilingHeight: ClosedRange<Double>
    var floorOutlineSource: FloorOutlineSource? = nil
    var floorSlabThickness: Double? = nil
    /// Multiple physical rooms may come from one continuous RoomPlan capture.
    var sourceCaptureID: UUID? = nil

    /// Floor extents must never grow to include loose furniture outside the room.
    var floorBounds: Rect2D {
        Rect2D.bounding(floorPolygon.count >= 3 && Polygon2D.area(floorPolygon) > 1e-8 && Polygon2D.triangulation(floorPolygon).1 ? floorPolygon : walls.flatMap { [$0.start,$0.end] })
    }

    var displayFloorSlabThickness: Double {
        guard let value = floorSlabThickness,value.isFinite,(0.005...2).contains(value) else { return Self.defaultFloorSlabThickness }
        return value
    }

    /// Bounding box of all rendered geometry (walls, openings, objects, floor).
    var bounds: Rect2D {
        var pts = walls.flatMap { [$0.start, $0.end] } + floorPolygon
        pts += openings.flatMap { [$0.segment.start, $0.segment.end] }
        for o in objects {
            let c = cos(o.angle), s = sin(o.angle), hw = o.size.width / 2, hd = o.size.depth / 2
            pts += [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)].map { (x, y) in Point2D(x: o.center.x + x * c - y * s, y: o.center.y + x * s + y * c) }
        }
        return Rect2D.bounding(pts)
    }

    func wall(withID id: UUID?) -> Wall? {
        guard let id else { return nil }
        return walls.first { $0.id == id }
    }
}

/// House aggregate: N rooms distributed across stories. In v1: single room.
struct House: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var stories: [Story]

    init(id: UUID = UUID(), name: String, stories: [Story]) { self.id = id; self.name = name; self.stories = stories }

    /// Single-room house.
    init(room: FloorPlan) {
        self.init(name: room.name, stories: [Story(index: room.story, rooms: [room])])
    }

    var allRooms: [FloorPlan] { stories.flatMap(\.rooms) }

    /// Bounding box of all rooms in house coordinates (transforms applied).
    var bounds: Rect2D {
        var pts: [Point2D] = []
        for r in allRooms where !r.bounds.isEmpty {
            let b = r.bounds
            pts += [Point2D(x: b.minX, y: b.minY), Point2D(x: b.maxX, y: b.minY), Point2D(x: b.maxX, y: b.maxY), Point2D(x: b.minX, y: b.maxY)].map(r.transform.apply)
        }
        return Rect2D.bounding(pts)
    }
}

struct Story: Codable, Equatable {
    var index: Int
    var rooms: [FloorPlan]
}
