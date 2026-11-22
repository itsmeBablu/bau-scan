import Foundation
import RealityKit
import simd
import CoreGraphics

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif

/// `PlatformColor` from `CGColor` (AppKit initializer is failable, UIKit is not).
func platformColor(_ cg: CGColor) -> PlatformColor {
    #if canImport(UIKit)
    return UIColor(cgColor: cg)
    #else
    return NSColor(cgColor: cg) ?? NSColor(white: 0.95, alpha: 1)
    #endif
}

/// Builds RealityKit **parametric** scene for a house:
/// walls = boxes cut around openings, door/window panels,
/// floor textured with 2D plan, placed objects, optional 3D dimension lines.
/// Coordinates: plan (x, y) → RealityKit (x, height, -y), Y up, meters.
@MainActor
struct PlanSceneBuilder {
    struct Options {
        var showObjects = true
        var showDimensions = false
        var showFloorTexture = false
        /// Flattened walls (2D mode): visual height when `flattenWalls` is true.
        var flattenWalls = false
        var flattenedHeight: Float = 0.02
        var floorTexturePixelsPerMeter = 120.0
        var locale: Locale = .current
    }

    enum Names {
        static let root = "house"
        static let roomPrefix = "room:"
        static let walls = "walls"
        static let floor = "floor"
        static let objects = "objects"
        static let dimensions = "dimensions"
        static let panels = "panels"
    }

    var options = Options()
    var radiators: [HouseRadiator] = []

    // MARK: - Scene

    /// Root containing one entity per room, positioned by `FloorPlan.transform`.
    func makeScene(for house: House) -> Entity {
        let root = Entity()
        root.name = Names.root
        for room in house.allRooms {
            let e = makeRoom(room)
            e.name = Names.roomPrefix + room.id.uuidString
            e.position = SIMD3(Float(room.transform.translation.x), 0, Float(-room.transform.translation.y))
            e.orientation = simd_quatf(angle: Float(room.transform.rotation), axis: SIMD3(0, 1, 0))
            root.addChild(e)
        }
        if options.showObjects,!options.flattenWalls {
            for radiator in radiators where radiator.capturedInHouseCoordinates == true && house.allRooms.contains(where: { $0.id == radiator.roomID }) {
                guard let frame = try? RadiatorScanGeometry(frontCorners: radiator.frontCorners,wall: radiator.wallSample),
                      let floor = radiator.houseFloorElevation else { continue }
                let width = Float(radiator.width.metres),height = Float(radiator.height.metres),depth = Float(radiator.depth?.metres ?? 0)
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: platformColor(CGColor(gray: 0.88,alpha: 1)))
                material.roughness = .init(floatLiteral: 0.65); material.faceCulling = .none
                let mesh = depth > 0 ? MeshResource.generateBox(width: width,height: height,depth: depth) : MeshResource.generatePlane(width: width,height: height)
                let model = ModelEntity(mesh: mesh,materials: [material])
                let center = frame.origin+frame.right*(Double(width)/2)+frame.up*(Double(height)/2)-frame.frontNormal*(Double(depth)/2)
                model.position = SIMD3(Float(center.x),Float(center.y-floor),Float(center.z))
                model.orientation = simd_quatf(angle: Float(atan2(-frame.right.z,frame.right.x)),axis: SIMD3(0,1,0))
                model.name = "radiator:"+radiator.id.uuidString
                root.addChild(model)
            }
        }
        return root
    }

    /// `floorTint`: room floor tint within a house (palette `PlanRenderer.roomPalette`).
    func makeRoom(_ room: FloorPlan, floorTint: CGColor? = nil) -> Entity {
        let roomEntity = Entity()
        let walls = Entity(); walls.name = Names.walls
        let panels = Entity(); panels.name = Names.panels
        for wall in room.walls {
            let openings = room.openings.filter { $0.wallID == wall.id }
            for box in wallBoxes(wall, openings: openings) {
                walls.addChild(makeBox(box, material: wallMaterial))
            }
        }
        if !options.flattenWalls {
            var local = room; local.transform = .identity
            let joins = StudioWallJoins.mesh(room: local, visible: Set(local.walls.map(\.id)))
            if !joins.isEmpty {
                var descriptor = MeshDescriptor(name: "wall-junctions")
                descriptor.positions = .init(joins.positions)
                descriptor.normals = .init(joins.normals)
                descriptor.primitives = .triangles(joins.triangles.flatMap { [$0.x, $0.y, $0.z] })
                if let mesh = try? MeshResource.generate(from: [descriptor]) {
                    let junction = ModelEntity(mesh: mesh, materials: [wallMaterial])
                    junction.name = "wall-junctions"
                    walls.addChild(junction)
                }
            }
        }
        for o in room.openings { if let panel = panelBox(o, wall: room.wall(withID: o.wallID)) {
            panels.addChild(makeBox(panel, material: o.kind == .window ? glassMaterial : doorMaterial))
        } }
        roomEntity.addChild(walls)
        roomEntity.addChild(panels)
        if let floor = makeFloor(room, tint: floorTint) { roomEntity.addChild(floor) }
        if options.showObjects {
            let objects = Entity(); objects.name = Names.objects
            for o in room.objects { objects.addChild(makeObject(o)) }
            roomEntity.addChild(objects)
        }
        if options.showDimensions {
            let dims = Entity(); dims.name = Names.dimensions
            for wall in room.walls { dims.addChild(makeDimensionLabel(wall, room: room)) }
            roomEntity.addChild(dims)
        }
        return roomEntity
    }

    // MARK: - Wall Geometry

    typealias WallBox = WallGeometry.Box

    /// Wall geometry based on options (flattened in 2D plan mode).
    var wallGeometry: WallGeometry { WallGeometry(flattenedHeight: options.flattenWalls ? Double(options.flattenedHeight) : nil) }

    /// Splits wall into solid boxes around openings (see `WallGeometry`).
    func wallBoxes(_ wall: Wall, openings: [Opening]) -> [WallBox] { wallGeometry.wallBoxes(wall, openings: openings) }

    /// Door panel (wood) or window glazing in opening.
    func panelBox(_ o: Opening, wall: Wall?) -> WallBox? { wallGeometry.panelBox(o, wall: wall) }

    private func makeBox(_ box: WallBox, material: RealityKit.Material) -> ModelEntity {
        let mesh = MeshResource.generateBox(width: Float(box.segment.length), height: Float(box.height), depth: Float(box.thickness))
        let e = ModelEntity(mesh: mesh, materials: [material])
        let mid = box.segment.midpoint
        e.position = SIMD3(Float(mid.x), Float(box.bottom + box.height / 2), Float(-mid.y))
        // Local X axis follows segment; plan angle is measured in coordinate space (x, y_plan) = (x, -z).
        e.orientation = simd_quatf(angle: Float(box.segment.angle), axis: SIMD3(0, 1, 0))
        return e
    }

    // MARK: - Floor, objets, cotes

    private func makeFloor(_ room: FloorPlan, tint: CGColor?) -> ModelEntity? {
        let b = room.floorBounds
        guard !b.isEmpty else { return nil }
        let polygonMesh = try? Self.floorMesh(polygon: room.floorPolygon,bounds: b)
        let mesh = polygonMesh ?? MeshResource.generatePlane(width: Float(b.width),depth: Float(b.height))
        let floorColor = tint.map(platformColor) ?? PlatformColor(red: 0.66, green: 0.58, blue: 0.47, alpha: 1)
        var material: RealityKit.Material = SimpleMaterial(color: floorColor, roughness: 0.8, isMetallic: false)
        if options.showFloorTexture {
            var r = PlanRenderer(); r.options.locale = options.locale; r.options.showObjects = false
            r.options.floorColor = floorColor.cgColor
            r.options.tintRooms = false
            if let img = r.floorTextureImage(House(room: untransformed(room)), bounds: b, pixelsPerMeter: options.floorTexturePixelsPerMeter),
               let tex = try? TextureResource.generate(from: img, options: .init(semantic: .color)) {
                var m = UnlitMaterial(); m.color = .init(texture: .init(tex)); material = m
            }
        }
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.name = Names.floor
        // Polygonal mesh is already in room coordinates; fallback plane is centered.
        e.position = polygonMesh != nil ? SIMD3(0, 0.001, 0) : SIMD3(Float(b.center.x), 0.001, Float(-b.center.y))
        return e
    }

    /// Floor mesh following room contour (ear-clipping triangulation),
    /// normalized UVs on `bounds` to map texture rendered by `floorTextureImage`
    /// (u = x croissant, v = 0 en haut de l'image = y_plan max).
    static func floorMesh(polygon: [Point2D], bounds: Rect2D) throws -> MeshResource {
        guard polygon.count >= 3 else { throw NSError(domain: "PlanSceneBuilder", code: 1) }
        let (tris,complete) = Polygon2D.triangulation(polygon)
        guard complete,!tris.isEmpty,bounds.width > 0,bounds.height > 0 else { throw NSError(domain: "PlanSceneBuilder", code: 2) }
        var desc = MeshDescriptor(name: "floor")
        desc.positions = MeshBuffers.Positions(polygon.map { SIMD3(Float($0.x), 0, Float(-$0.y)) })
        desc.normals = MeshBuffers.Normals(polygon.map { _ in SIMD3<Float>(0, 1, 0) })
        desc.textureCoordinates = MeshBuffers.TextureCoordinates(polygon.map {
            SIMD2(Float(($0.x - bounds.minX) / bounds.width), Float(($0.y - bounds.minY) / bounds.height))
        })
        // Visible top face: counterclockwise winding viewed from +Y.
        var indices: [UInt32] = []
        for (a, b, c) in tris {
            let pa = polygon[a], pb = polygon[b], pc = polygon[c]
            let ccw = (pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x) >= 0
            indices += ccw ? [UInt32(a), UInt32(b), UInt32(c)] : [UInt32(a), UInt32(c), UInt32(b)]
        }
        desc.primitives = .triangles(indices)
        return try MeshResource.generate(from: [desc])
    }

    /// The room is rendered in its local space (parent entity holds house transform).
    private func untransformed(_ room: FloorPlan) -> FloorPlan { var r = room; r.transform = .identity; return r }

    private func makeObject(_ o: PlacedObject) -> Entity {
        let mesh = MeshResource.generateBox(width: Float(o.size.width), height: Float(o.height), depth: Float(o.size.depth), cornerRadius: 0.01)
        let e = ModelEntity(mesh: mesh, materials: [objectMaterial(for: o.category)])
        e.name = "object:\(o.category)"
        e.position = SIMD3(Float(o.center.x), Float(o.height / 2), Float(-o.center.y))
        e.orientation = simd_quatf(angle: Float(o.angle), axis: SIMD3(0, 1, 0))
        let label = makeLabel(ObjectNaming.localizedName(o.category), size: 0.12, billboard: !options.flattenWalls)
        if options.flattenWalls {
            // Flat on object, readable from zenith (parent entity already has object rotation).
            label.position = SIMD3(0, Float(o.height / 2) + 0.005, 0)
            label.orientation = Self.flatOrientation(yaw: Self.readable(o.angle) - o.angle)
        } else {
            label.position = SIMD3(0, Float(o.height / 2) + 0.12, 0)
        }
        e.addChild(label)
        return e
    }

    /// Wall dimension line. In 3D: billboard text above wall. In 2D: text placed
    /// flat on exterior of wall, oriented for readability from top-down zenith view.
    /// billboard text viewed from top-down could otherwise appear flipped.
    private func makeDimensionLabel(_ wall: Wall, room: FloorPlan) -> Entity {
        let text = MeasurementFormat.length(wall.length, unit: .both, locale: options.locale)
        let color = PlatformColor(white: 0.12, alpha: 1)
        let mid = wall.segment.midpoint
        guard options.flattenWalls else {
            let label = makeLabel(text, size: 0.16, color: color)
            label.position = SIMD3(Float(mid.x), Float(wall.height + 0.15), Float(-mid.y))
            return label
        }
        let side = PlanRenderer.InteriorSide(polygon: room.floorPolygon, fallback: room.bounds.center)
        let outward = side.inward(of: wall.segment) * -1
        let pos = mid + outward * PlanRenderer.dimensionOffset
        let label = makeLabel(text, size: 0.16, color: color, billboard: false)
        label.position = SIMD3(Float(pos.x), Float(options.flattenedHeight) + 0.005, Float(-pos.y))
        label.orientation = Self.flatOrientation(yaw: Self.readable(wall.segment.angle))
        return label
    }

    /// Orientation of text laying on floor (facing +Y), rotated by `yaw`.
    /// coordinates (x, y_plan) = (x, -z), matching wall convention).
    static func flatOrientation(yaw: Double) -> simd_quatf {
        simd_quatf(angle: Float(yaw), axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
    }

    /// Angle normalized to ]-90°, 90°] for readable orientation.
    static func readable(_ a: Double) -> Double {
        var x = a; while x > .pi / 2 { x -= .pi }; while x <= -.pi / 2 { x += .pi }; return x
    }

    /// Centered 3D text with minimal extrusion.
    func makeLabel(_ text: String, size: Float, color: PlatformColor = PlatformColor(white: 0.25, alpha: 1), billboard: Bool = true) -> ModelEntity {
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.002, font: .systemFont(ofSize: CGFloat(size)),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping)
        let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        // generateText anchors text at bottom-left: recenter it.
        let bounds = mesh.bounds
        e.position = SIMD3(-bounds.center.x, 0, 0)
        let holder = ModelEntity()
        holder.addChild(e)
        if billboard { holder.components.set(BillboardComponent()) }
        return holder
    }

    // MARK: - Materials

    private var wallMaterial: RealityKit.Material { SimpleMaterial(color: PlatformColor(white: 0.93, alpha: 1), roughness: 0.8, isMetallic: false) }
    private var doorMaterial: RealityKit.Material { SimpleMaterial(color: PlatformColor(red: 0.62, green: 0.45, blue: 0.30, alpha: 1), roughness: 0.6, isMetallic: false) }
    private var glassMaterial: RealityKit.Material { SimpleMaterial(color: PlatformColor(red: 0.45, green: 0.72, blue: 1.0, alpha: 0.35), roughness: 0.1, isMetallic: false) }
    /// RoomPlan stores object categories, not photographed surface colours.
    /// Use opaque, natural materials appropriate to the detected category.
    private func objectMaterial(for category: String) -> RealityKit.Material {
        let color: PlatformColor
        let metallic: Bool
        switch category.lowercased() {
        case "table", "storage":
            color = PlatformColor(red: 0.54, green: 0.40, blue: 0.28, alpha: 1); metallic = false
        case "chair", "sofa":
            color = PlatformColor(red: 0.34, green: 0.40, blue: 0.44, alpha: 1); metallic = false
        case "bed":
            color = PlatformColor(red: 0.78, green: 0.76, blue: 0.71, alpha: 1); metallic = false
        case "sink", "toilet", "bathtub", "washerdryer", "dishwasher":
            color = PlatformColor(white: 0.88, alpha: 1); metallic = false
        case "refrigerator", "stove", "oven":
            color = PlatformColor(white: 0.56, alpha: 1); metallic = true
        case "television":
            color = PlatformColor(white: 0.09, alpha: 1); metallic = false
        default:
            color = PlatformColor(white: 0.55, alpha: 1); metallic = false
        }
        return SimpleMaterial(color: color, roughness: metallic ? 0.35 : 0.75, isMetallic: metallic)
    }
}
