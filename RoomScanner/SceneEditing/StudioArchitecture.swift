import SceneKit
import simd

/// Native adaptation of SmartBau's straight-wall face profile and through-depth mitres.
/// Captured centrelines and dimensions are unchanged; this builds the design display only.
enum StudioWallProfile {
    static func mesh(_ wall: Wall,room: FloorPlan,visible: Set<UUID>) -> TriangleMesh {
        let openings = room.openings.filter { $0.wallID == wall.id }
        let length = wall.length,height = wall.height
        guard length > 0,height > 0 else { return TriangleMesh() }
        guard openings.count <= 32 else {
            var fallback = TriangleMesh()
            for box in WallGeometry().wallBoxes(wall,openings: openings) { PlanMeshBuilder.addBox(box,transform: room.transform,to: &fallback) }
            return fallback
        }
        let direction = wall.segment.direction,normal = wall.segment.leftNormal
        let holes = openings.map { opening -> (Double,Double,Double,Double) in
            let position = (opening.center-wall.start).x*direction.x+(opening.center-wall.start).y*direction.y
            let bottom = opening.kind == .door ? 0 : opening.sillHeight
            return (max(0,position-opening.width/2),min(length,position+opening.width/2),max(0,bottom),min(height,bottom+opening.height))
        }.filter { $0.1 > $0.0 && $0.3 > $0.2 }
        let xs = Array(Set([0,length]+holes.flatMap { [$0.0,$0.1] })).sorted()
        let ys = Array(Set([0,height]+holes.flatMap { [$0.2,$0.3] })).sorted()
        let nx = xs.count-1,ny = ys.count-1
        var solid = Array(repeating: false,count: nx*ny)
        for y in 0..<ny { for x in 0..<nx {
            let mx = (xs[x]+xs[x+1])/2,my = (ys[y]+ys[y+1])/2
            solid[y*nx+x] = !holes.contains { mx > $0.0 && mx < $0.1 && my > $0.2 && my < $0.3 }
        } }
        func occupied(_ x: Int,_ y: Int) -> Bool { x >= 0 && x < nx && y >= 0 && y < ny && solid[y*nx+x] }
        func endpointIsSolid(_ other: Wall,_ start: Bool) -> Bool {
            let point = start ? other.start : other.end
            return !room.openings.filter { $0.wallID == other.id }.contains { $0.segment.distance(to: point) < 0.025 }
        }
        func offset(start: Bool,side: Double) -> Double {
            guard endpointIsSolid(wall,start) else { return 0 }
            let endpoint = start ? wall.start : wall.end
            for other in room.walls where other.id != wall.id && visible.contains(other.id) {
                for otherStart in [true,false] {
                    let junction = otherStart ? other.start : other.end
                    guard endpoint.distance(to: junction) <= 0.025,endpointIsSolid(other,otherStart) else { continue }
                    let d = other.segment.direction,det = direction.x*d.y-direction.y*d.x
                    guard abs(det) > 0.15 else { continue }
                    let otherSide = start == otherStart ? -side : side
                    let a = endpoint+normal*(side*wall.thickness/2)
                    let b = junction+other.segment.leftNormal*(otherSide*other.thickness/2)
                    let delta = b-a,t = (delta.x*d.y-delta.y*d.x)/det
                    guard abs(t) <= min(length/3,max(wall.thickness,other.thickness)*2+0.025) else { continue }
                    return t
                }
            }
            return 0
        }
        let shifts = [offset(start: true,side: 1),offset(start: true,side: -1),offset(start: false,side: 1),offset(start: false,side: -1)]
        func point(_ x: Double,_ y: Double,_ side: Double) -> SIMD3<Float> {
            let shift = abs(x) < 1e-7 ? shifts[side > 0 ? 0 : 1] : abs(x-length) < 1e-7 ? shifts[side > 0 ? 2 : 3] : 0
            return PlanMeshBuilder.point(room.transform.apply(wall.start+direction*(x+shift)+normal*(side*wall.thickness/2)),y: y)
        }
        var mesh = TriangleMesh()
        for y in 0..<ny { for x in 0..<nx where occupied(x,y) {
            let a0 = point(xs[x],ys[y],1),a1 = point(xs[x+1],ys[y],1),a2 = point(xs[x+1],ys[y],-1),a3 = point(xs[x],ys[y],-1)
            let b0 = point(xs[x],ys[y+1],1),b1 = point(xs[x+1],ys[y+1],1),b2 = point(xs[x+1],ys[y+1],-1),b3 = point(xs[x],ys[y+1],-1)
            mesh.addQuad(a0,b0,b1,a1); mesh.addQuad(a2,b2,b3,a3)
            if !occupied(x,y+1) { mesh.addQuad(b3,b2,b1,b0) }
            if !occupied(x,y-1) { mesh.addQuad(a0,a1,a2,a3) }
            if !occupied(x+1,y) { mesh.addQuad(a1,b1,b2,a2) }
            if !occupied(x-1,y) { mesh.addQuad(a3,b3,b0,a0) }
        } }
        return mesh
    }
}

/// Removes exact coincident triangles across architectural nodes, without moving geometry.
struct StudioSurfaceDeduplicator {
    private var seen = Set<[Int64]>()
    mutating func clean(_ mesh: TriangleMesh) -> TriangleMesh {
        var result = TriangleMesh()
        for triangle in mesh.triangles {
            let points = [mesh.positions[Int(triangle.x)],mesh.positions[Int(triangle.y)],mesh.positions[Int(triangle.z)]]
            guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && abs($0.x) < 1_000_000 && abs($0.y) < 1_000_000 && abs($0.z) < 1_000_000 }) else { continue }
            let keys = points.map { [Int64((Double($0.x)*100_000).rounded()),Int64((Double($0.y)*100_000).rounded()),Int64((Double($0.z)*100_000).rounded())] }.sorted { $0.lexicographicallyPrecedes($1) }
            if seen.insert(keys.flatMap { $0 }).inserted { result.addTriangle(points[0],points[1],points[2]) }
        }
        return result
    }
}

@MainActor enum StudioWindowModel {
    /// Closed framing adapted from SmartBau windowGeometry.ts. Operation is not inferred.
    static func make(_ opening: Opening,wall: Wall?,transform: Transform2D) -> SCNNode {
        let root = SCNNode(); root.name = "shell:window"
        let center = transform.apply(opening.center)
        root.position = SCNVector3(center.x,opening.sillHeight+opening.height/2,-center.y)
        root.simdOrientation = simd_quatf(angle: Float(opening.angle+transform.rotation),axis: SIMD3(0,1,0))
        let width = opening.width,height = opening.height,rail = min(0.045,min(width,height)/10)
        let frame = StudioSceneBuilder.material(.init(x: 0.92,y: 0.93,z: 0.94),roughness: 0.45)
        let glass = StudioSceneBuilder.material(.init(x: 0.65,y: 0.84,z: 0.91),roughness: 0.08,metal: 0.1)
        glass.transparency = 0.32; glass.isDoubleSided = true; glass.writesToDepthBuffer = false
        let depth = min(0.08,max(0.025,(wall?.thickness ?? 0.1)*0.7))
        func box(_ x: Double,_ y: Double,_ w: Double,_ h: Double,_ d: Double,_ material: SCNMaterial,_ name: String) {
            guard w > 0,h > 0,d > 0 else { return }
            let node = SCNNode(geometry: SCNBox(width: w,height: h,length: d,chamferRadius: 0))
            node.name = name; node.geometry?.materials = [material]; node.position = SCNVector3(x,y,0)
            if name == "glazing" { node.renderingOrder = 10 }
            root.addChildNode(node)
        }
        // Side jambs span the opening; horizontal rails fit between them without overlap.
        box(-(width-rail)/2,0,rail,height,depth,frame,"frame:left")
        box((width-rail)/2,0,rail,height,depth,frame,"frame:right")
        box(0,-(height-rail)/2,width-2*rail,rail,depth,frame,"frame:sill")
        box(0,(height-rail)/2,width-2*rail,rail,depth,frame,"frame:head")
        box(0,0,width-2*rail-0.002,height-2*rail-0.002,0.012,glass,"glazing")
        return root
    }
}

@MainActor enum StudioDimensionOverlay {
    static func add(to scene: SCNScene,document: SceneEditDocument,rooms: [FloorPlan],visibleWalls: Set<UUID>,selection: UUID?) {
        let root = SCNNode(); root.name = "dimensions"
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = platformColor(CGColor(gray: 0.15,alpha: 1))
        func dimension(_ a: SIMD3<Double>,_ b: SIMD3<Double>,value: Double,parent: SCNNode) {
            let delta = b-a,length = simd_length(delta)
            guard length > 0.005 else { return }
            let line = SCNNode(geometry: SCNCylinder(radius: 0.002,height: length))
            line.geometry?.materials = [material]; line.simdPosition = SIMD3<Float>((a+b)/2)
            line.simdOrientation = simd_quatf(from: SIMD3<Float>(0,1,0),to: SIMD3<Float>(delta/length)); line.castsShadow = false; parent.addChildNode(line)
            let text = SCNText(string: value.formatted(.number.precision(.fractionLength(2)))+" m",extrusionDepth: 0)
            text.font = .systemFont(ofSize: 12,weight: .medium); text.flatness = 0.4; text.materials = [material]
            let label = SCNNode(geometry: text); label.name = "dimension-label"
            let bounds = text.boundingBox
            label.pivot = SCNMatrix4MakeTranslation((bounds.max.x+bounds.min.x)/2,bounds.min.y,0)
            label.scale = SCNVector3(0.006,0.006,0.006)
            label.simdPosition = SIMD3<Float>((a+b)/2+SIMD3(0,0.025,0))
            let billboard = SCNBillboardConstraint(); billboard.freeAxes = .all; label.constraints = [billboard]
            label.castsShadow = false; parent.addChildNode(label)
        }
        var count = 0
        for room in rooms { for wall in room.walls where visibleWalls.contains(wall.id) && count < 64 {
            count += 1
            let a = room.transform.apply(wall.start),b = room.transform.apply(wall.end)
            dimension(.init(a.x,wall.height+0.12,-a.y),.init(b.x,wall.height+0.12,-b.y),value: wall.length,parent: root)
        } }
        if let item = document.presentationObjects.first(where: { $0.id == selection }) {
            let group = SCNNode(); group.simdPosition = SIMD3(Float(item.position.x),Float(item.position.y),Float(item.position.z)); group.simdOrientation = simd_quatf(vector: SIMD4<Float>(item.orientation.vector))
            root.addChildNode(group)
            let w = item.size.x/2,h = item.size.y/2,d = item.size.z/2
            dimension(.init(-w,h+0.12,d+0.12),.init(w,h+0.12,d+0.12),value: item.size.x,parent: group)
            dimension(.init(w+0.12,-h,d+0.12),.init(w+0.12,h,d+0.12),value: item.size.y,parent: group)
            dimension(.init(w+0.12,h+0.12,-d),.init(w+0.12,h+0.12,d),value: item.size.z,parent: group)
        }
        scene.rootNode.addChildNode(root)
    }
}

/// Removes coplanar room-floor overlap in the design display. Source contours stay intact.
/// Clipping is bounded; exceptionally complex regions retain their original geometry.
struct StudioFloorCoverage {
    private struct Cover { let story: Int; let triangle: [Point2D]; let bounds: Rect2D }
    private var covers: [Cover] = []
    private var operations = 0
    mutating func mesh(_ room: FloorPlan) -> TriangleMesh {
        let bounds = room.floorBounds
        guard !bounds.isEmpty else { return TriangleMesh() }
        let outline = room.floorPolygon.count >= 3 && Polygon2D.triangulation(room.floorPolygon).1 ? room.floorPolygon :
            [.init(x: bounds.minX,y: bounds.minY),.init(x: bounds.maxX,y: bounds.minY),.init(x: bounds.maxX,y: bounds.maxY),.init(x: bounds.minX,y: bounds.maxY)]
        let world = outline.map(room.transform.apply),triangles = Polygon2D.triangulation(world).0
        var result = TriangleMesh(),additions: [Cover] = []
        func overlaps(_ a: Rect2D,_ b: Rect2D) -> Bool { a.minX < b.maxX-1e-8 && a.maxX > b.minX+1e-8 && a.minY < b.maxY-1e-8 && a.maxY > b.minY+1e-8 }
        for triangle in triangles {
            let polygon = [world[triangle.0],world[triangle.1],world[triangle.2]],box = Rect2D.bounding(polygon)
            var pieces = [polygon]
            for cover in covers where cover.story == room.story && overlaps(box,cover.bounds) {
                guard operations < 250_000,pieces.count < 256 else { pieces = [polygon]; break }
                operations += max(1,pieces.count)
                pieces = pieces.flatMap { StudioWallJoins.subtract($0,cover.triangle) }.map { Polygon2D.simplified($0,tolerance: 1e-8) }.filter { $0.count >= 3 && Polygon2D.area($0) > 1e-9 }
                if pieces.isEmpty { break }
            }
            for piece in pieces {
                var part = room; part.transform = .identity; part.floorPolygon = piece; part.walls = []; part.openings = []; part.objects = []
                var mesh = TriangleMesh()
                PlanMeshBuilder.addFloor(part,transform: .identity,thickness: room.displayFloorSlabThickness,to: &mesh)
                let offset = UInt32(result.positions.count)
                result.positions += mesh.positions; result.normals += mesh.normals
                result.triangles += mesh.triangles.map { $0 &+ SIMD3<UInt32>(repeating: offset) }
            }
            additions.append(Cover(story: room.story,triangle: polygon,bounds: box))
        }
        covers += additions
        return result
    }
}
