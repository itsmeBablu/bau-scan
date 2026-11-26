import SceneKit
import simd
#if os(iOS)
import UIKit
#else
import AppKit
#endif

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

/// Native SmartBau-style opening parts. Operation, hardware and trim are design presets.
@MainActor enum StudioOpeningParts {
    static func box(_ parent: SCNNode,_ name: String,_ x: Double,_ y: Double,_ z: Double,_ w: Double,_ h: Double,_ d: Double,_ material: SCNMaterial) {
        guard w > 0,h > 0,d > 0 else { return }
        let node = SCNNode(geometry: SCNBox(width: w,height: h,length: d,chamferRadius: 0))
        node.name = name; node.geometry?.materials = [material]; node.simdPosition = SIMD3(Float(x),Float(y),Float(z)); parent.addChildNode(node)
        if name == "glazing" { node.renderingOrder = 10 }
    }
    static func root(_ opening: Opening,_ transform: Transform2D,_ name: String) -> SCNNode {
        let node = SCNNode(); node.name = name
        let p = transform.apply(opening.center)
        node.simdPosition = SIMD3(Float(p.x),Float(opening.sillHeight+opening.height/2),Float(-p.y))
        node.simdOrientation = simd_quatf(angle: Float(opening.angle+transform.rotation),axis: SIMD3(0,1,0)); return node
    }
    static func glass() -> SCNMaterial {
        let m = StudioSceneBuilder.material(.init(x: 0.65,y: 0.84,z: 0.91),roughness: 0.08,metal: 0.1)
        m.transparency = 0.32; m.isDoubleSided = true; m.writesToDepthBuffer = false; return m
    }
    static func casing(_ parent: SCNNode,width w: Double,height h: Double,depth d: Double,rail: Double,door: Bool,material: SCNMaterial) {
        for side in [-1.0,1.0] {
            let z = side*(d/2+0.02),r = rail+0.04
            for x in [-1.0,1.0] { box(parent,"trim",x*(w/2+(0.04-rail)/2),0,z,r,h+0.04,0.018,material) }
            box(parent,"trim",0,(h+0.04-rail)/2,z,w-2*rail,rail+0.04,0.018,material)
            if !door { box(parent,"trim",0,-(h+0.04-rail)/2,z,w-2*rail,rail+0.04,0.018,material) }
        }
    }
}

@MainActor enum StudioWindowModel {
    static func make(_ opening: Opening,wall: Wall?,transform: Transform2D,template: SceneEditDocument.WindowTemplate = .fixed,angle: Double = 0) -> SCNNode {
        let root = StudioOpeningParts.root(opening,transform,"shell:window")
        let w = opening.width,h = opening.height,r = min(0.045,w/10,h/10),d = wall?.thickness ?? 0.1
        let frame = StudioSceneBuilder.material(.init(x: 0.92,y: 0.93,z: 0.94),roughness: 0.45),glass = StudioOpeningParts.glass()
        func box(_ parent: SCNNode,_ name: String,_ x: Double,_ y: Double,_ z: Double,_ width: Double,_ height: Double,_ depth: Double,_ m: SCNMaterial) { StudioOpeningParts.box(parent,name,x,y,z,width,height,depth,m) }
        box(root,"frame:left",-(w-r)/2,0,0,r,h,d+0.024,frame); box(root,"frame:right",(w-r)/2,0,0,r,h,d+0.024,frame)
        box(root,"frame:sill",0,-(h-r)/2,0,w-2*r,r,d+0.024,frame); box(root,"frame:head",0,(h-r)/2,0,w-2*r,r,d+0.024,frame)
        StudioOpeningParts.casing(root,width: w,height: h,depth: d,rail: r,door: false,material: frame)
        let iw = w-2*r,ih = h-2*r,gap = min(0.003,iw/20,ih/20)
        func sash(_ parent: SCNNode,_ x: Double,_ y: Double,_ z: Double,_ width: Double,_ height: Double) -> SCNNode {
            let leaf = SCNNode(); leaf.name = "window-sash"; leaf.simdPosition = SIMD3(Float(x),Float(y),Float(z)); parent.addChildNode(leaf)
            let rail = min(0.03,width/10,height/10)
            for side in [-1.0,1.0] { box(leaf,"sash-rail",side*(width-rail)/2,0,0,rail,height,0.045,frame); box(leaf,"sash-rail",0,side*(height-rail)/2,0,width-2*rail,rail,0.045,frame) }
            box(leaf,"glazing",0,0,0,width-2*rail,height-2*rail,0.012,glass)
            return leaf
        }
        switch template {
        case .fixed: box(root,"glazing",0,0,0,iw-gap,ih-gap,0.012,glass)
        case .casement:
            let pivot = SCNNode(); pivot.name = "window-hinge"; pivot.simdPosition.x = Float(-(iw-gap)/2); root.addChildNode(pivot)
            let leaf = sash(pivot,(iw-gap)/2,0,0,iw-gap,ih-gap)
            pivot.simdOrientation = simd_quatf(angle: -Float(min(90,max(0,angle)) * .pi/180),axis: SIMD3(0,1,0))
            let hardware = StudioSceneBuilder.material(.init(x: 0.65,y: 0.67,z: 0.68),roughness: 0.25,metal: 0.8)
            box(leaf,"window-handle",(iw-gap)/2-r,0,0.04,min(0.018,iw/15),min(0.12,ih/4),0.025,hardware)
            for y in [-ih*0.3,ih*0.3] { box(pivot,"window-hardware",0,y,0,r,min(0.08,ih/10),0.055,hardware) }
        case .sliding:
            _ = sash(root,-iw*0.245,0,-0.028,iw*0.51,ih-gap); _ = sash(root,iw*0.245,0,0.028,iw*0.51,ih-gap)
        case .doubleHung:
            _ = sash(root,0,ih*0.25,-0.025,iw-gap,ih/2-gap); _ = sash(root,0,-ih*0.25,0.025,iw-gap,ih/2-gap)
        }
        return root
    }
}

@MainActor enum StudioDoorModel {
    static func make(_ opening: Opening,wall: Wall?,transform: Transform2D,template: SceneEditDocument.DoorTemplate = .single,angle: Double = 0) -> SCNNode {
        let root = StudioOpeningParts.root(opening,transform,"shell:door")
        let w = opening.width,h = opening.height,r = min(0.05,w/10,h/10),d = wall?.thickness ?? 0.1
        let frame = StudioSceneBuilder.material(.init(x: 0.65,y: 0.48,z: 0.32)),wood = StudioSceneBuilder.material(.init(x: 0.72,y: 0.55,z: 0.37))
        let hardware = StudioSceneBuilder.material(.init(x: 0.72,y: 0.74,z: 0.77),roughness: 0.25,metal: 0.8)
        func box(_ parent: SCNNode,_ name: String,_ x: Double,_ y: Double,_ z: Double,_ width: Double,_ height: Double,_ depth: Double,_ m: SCNMaterial) { StudioOpeningParts.box(parent,name,x,y,z,width,height,depth,m) }
        for side in [-1.0,1.0] { box(root,"door-jamb",side*(w-r)/2,0,0,r,h,d+0.024,frame) }
        box(root,"door-head",0,(h-r)/2,0,w-2*r,r,d+0.024,frame)
        StudioOpeningParts.casing(root,width: w,height: h,depth: d,rail: r,door: true,material: frame)
        let gap = min(0.008,h/100),iw = w-2*r,lh = h-r-gap,cy = -h/2+gap+lh/2,leafDepth = 0.04
        let offset = max(0,d/2-leafDepth/2)
        let sides = template == .double || template == .sliding ? [-1.0,1.0] : [-1.0]
        for side in sides {
            let lw = template == .double ? iw/2-min(0.003,iw/100) : template == .sliding ? iw*0.52 : iw-min(0.006,iw/50)
            let pivot = SCNNode(); pivot.name = "door-leaf-pivot"; root.addChildNode(pivot)
            let leaf = SCNNode(); leaf.name = "door-leaf"; pivot.addChildNode(leaf)
            if template == .sliding {
                leaf.simdPosition = SIMD3(Float(side*(iw/4+min(1,max(0,angle)/90)*lw*0.9)),Float(cy),Float(side*max(0.025,offset)))
            } else {
                pivot.simdPosition = SIMD3(Float(side*iw/2),0,Float(offset))
                leaf.simdPosition = SIMD3(Float(-side*lw/2),Float(cy),0)
                pivot.simdOrientation = simd_quatf(angle: Float(side*min(120,max(0,angle)) * .pi/180),axis: SIMD3(0,1,0))
                for y in [-lh*0.3,0,lh*0.3] { box(pivot,"door-hinge",0,y,0,0.016,min(0.08,lh/10),0.02,hardware) }
            }
            if template == .glazed {
                let rail = min(0.07,lw/8,lh/12)
                for sign in [-1.0,1.0] { box(leaf,"leaf-rail",sign*(lw-rail)/2,0,0,rail,lh,leafDepth,wood); box(leaf,"leaf-rail",0,sign*(lh-rail)/2,0,lw-2*rail,rail,leafDepth,wood) }
                box(leaf,"glazing",0,0,0,lw-2*rail,lh-2*rail,0.012,StudioOpeningParts.glass())
            } else { box(leaf,"door-panel",0,0,0,lw,lh,leafDepth,wood) }
            for face in [-1.0,1.0] {
                let x = -side*max(0,lw/2-min(0.09,lw/4))
                box(leaf,"handle-stem",x,0,face*(leafDepth/2+0.0175),0.018,0.018,0.035,hardware)
                box(leaf,"door-handle",x,0,face*(leafDepth/2+0.035),min(0.12,lw/3),0.018,0.022,hardware)
            }
        }
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

/// One continuous design slab per level. Internal triangulation edges have no
/// vertical caps; only the outer boundary and actual thickness steps do.
enum StudioFloorSlab {
    /// Normalize all positive-winding contours together: overlapping rooms become
    /// one outline, while concave boundaries, courtyards and separate islands survive.
    static func outline(rooms: [FloorPlan],regions: [SceneEditDocument.FloorRegion] = [],minimumDepth: Double = 0) -> CGPath {
        let path = CGMutablePath()
        func add(_ points: [Point2D]) {
            guard points.count >= 3,points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
            let points = Polygon2D.signedArea(points) < 0 ? points.reversed().map { $0 } : points
            path.move(to: CGPoint(x: points[0].x,y: points[0].y))
            for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x,y: p.y)) }
            path.closeSubpath()
        }
        var walls = 0
        for room in rooms where room.displayFloorSlabThickness >= minimumDepth-1e-8 {
            let captured = regions.filter { $0.roomID == room.id }
            if !captured.isEmpty { for region in captured { add(region.polygon.map(room.transform.apply)) } }
            else {
                let b = room.floorBounds
                if room.floorPolygon.count >= 3 { add(room.floorPolygon.map(room.transform.apply)) }
                else if !b.isEmpty { add([.init(x: b.minX,y: b.minY),.init(x: b.maxX,y: b.minY),.init(x: b.maxX,y: b.maxY),.init(x: b.minX,y: b.maxY)].map(room.transform.apply)) }
            }
            for wall in room.walls where walls < 2000 {
                let along = wall.segment.direction*(wall.thickness/2),n = wall.segment.leftNormal*(wall.thickness/2)
                add([wall.start-along+n,wall.end+along+n,wall.end+along-n,wall.start-along-n].map(room.transform.apply)); walls += 1
            }
        }
        return path.normalized(using: .winding)
    }
    @MainActor static func node(rooms: [FloorPlan],regions: [SceneEditDocument.FloorRegion],material: SCNMaterial,textureScale: Double,patternAngle: Double = 0) -> SCNNode? {
        let root = SCNNode(); root.name = "shell:floor"
        // Rotate the temporary path into wall-aligned texture space, then rotate
        // its node back. The world-space floor outline remains exactly unchanged.
        root.simdOrientation = simd_quatf(angle: Float(patternAngle), axis: SIMD3<Float>(0,1,0))
        var previousDepth = 0.0
        for depth in Set(rooms.map(\.displayFloorSlabThickness)).sorted() {
            let original = outline(rooms: rooms,regions: regions,minimumDepth: depth)
            var alignment = CGAffineTransform(rotationAngle: -patternAngle)
            guard let path = original.copy(using: &alignment) else { continue }
            guard !path.isEmpty else { continue }
            #if os(iOS)
            let bezier = UIBezierPath(cgPath: path); bezier.usesEvenOddFillRule = true
            #else
            let bezier = NSBezierPath(cgPath: path); bezier.windingRule = .evenOdd
            #endif
            let shape = SCNShape(path: bezier,extrusionDepth: depth-previousDepth); shape.chamferRadius = 0
            let m = material.copy() as? SCNMaterial ?? material
            let bounds = path.boundingBoxOfPath
            #if os(iOS)
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(Double(bounds.width)/textureScale),Float(Double(bounds.height)/textureScale),1)
            #else
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(CGFloat(Double(bounds.width)/textureScale),CGFloat(Double(bounds.height)/textureScale),1)
            #endif
            shape.materials = [m]
            let layer = SCNNode(geometry: shape); layer.eulerAngles.x = -.pi/2; layer.simdPosition.y = -Float(depth)
            root.addChildNode(layer); previousDepth = depth
        }
        guard !root.childNodes.isEmpty else { return nil }
        // A single native compound floor object, rather than one prism per triangle.
        let floor = root.flattenedClone(); floor.name = "shell:floor"; return floor
    }
    private struct Line: Hashable { let angle: Int64; let offset: Int64 }
    private struct Event { let t: Double; let depth: Double; let side: Int; let change: Int }
    private struct Edge { let direction: Point2D; let normal: Point2D; let offset: Double; var events: [Event] }
    static func mesh(rooms: [FloorPlan]) -> TriangleMesh {
        var inputs = rooms
        // Cover the known wall footprints beneath interior floor contours. This
        // is a design display extension, not a change to measured room areas.
        for room in rooms { for wall in room.walls where inputs.count < 2000 {
            let along = wall.segment.direction*(wall.thickness/2),normal = wall.segment.leftNormal*(wall.thickness/2)
            var footprint = room
            footprint.id = wall.id; footprint.transform = .identity
            footprint.floorPolygon = [wall.start-along+normal,wall.end+along+normal,wall.end+along-normal,wall.start-along-normal].map(room.transform.apply)
            footprint.walls = []; footprint.openings = []; footprint.objects = []
            inputs.append(footprint)
        } }
        var coverage = StudioFloorCoverage(),result = TriangleMesh(),edges: [Line:Edge] = [:]
        for room in inputs {
            let source = coverage.mesh(room),depth = room.displayFloorSlabThickness
            for triangle in source.triangles {
                let points = [source.positions[Int(triangle.x)],source.positions[Int(triangle.y)],source.positions[Int(triangle.z)]]
                // Keep horizontal skins; rebuild sides after cancelling shared edges.
                guard points.allSatisfy({ abs($0.y) < 1e-6 }) || points.allSatisfy({ abs(Double($0.y)+depth) < 1e-5 }) else { continue }
                result.addTriangle(points[0],points[1],points[2])
                guard points.allSatisfy({ abs($0.y) < 1e-6 }) else { continue }
                let polygon = points.map { Point2D(x: Double($0.x),y: -Double($0.z)) }
                for i in 0..<3 {
                    let p = polygon[i],q = polygon[(i+1)%3],delta = q-p
                    guard delta.length > 1e-6 else { continue }
                    let unit = delta.normalized
                    let side = abs(unit.x) < 1e-5 ? (unit.y < 0 ? -1 : 1) : (unit.x < 0 ? -1 : 1)
                    let direction = delta.normalized*Double(side),normal = Point2D(x: -direction.y,y: direction.x)
                    let offset = p.x*normal.x+p.y*normal.y
                    let key = Line(angle: Int64((atan2(direction.y,direction.x)*100_000).rounded()),offset: Int64((offset*10_000).rounded()))
                    var edge = edges[key] ?? Edge(direction: direction,normal: normal,offset: offset,events: [])
                    let a = p.x*edge.direction.x+p.y*edge.direction.y,b = q.x*edge.direction.x+q.y*edge.direction.y
                    edge.events.append(.init(t: min(a,b),depth: depth,side: side,change: 1))
                    edge.events.append(.init(t: max(a,b),depth: depth,side: side,change: -1)); edges[key] = edge
                }
            }
        }
        for edge in edges.values {
            let events = edge.events.sorted { $0.t < $1.t }
            var positive: [Double:Int] = [:],negative: [Double:Int] = [:],previous: Double?
            for event in events {
                if let previous,event.t-previous > 1e-5 {
                    let left = positive.filter { $0.value > 0 }.keys.max() ?? 0,right = negative.filter { $0.value > 0 }.keys.max() ?? 0
                    if abs(left-right) > 1e-6 {
                        let a = edge.direction*previous+edge.normal*edge.offset,b = edge.direction*event.t+edge.normal*edge.offset
                        let p = left > right ? a : b,q = left > right ? b : a
                        result.addQuad(PlanMeshBuilder.point(q,y: -max(left,right)),PlanMeshBuilder.point(q,y: -min(left,right)),PlanMeshBuilder.point(p,y: -min(left,right)),PlanMeshBuilder.point(p,y: -max(left,right)))
                    }
                }
                if event.side > 0 { positive[event.depth,default: 0] += event.change }
                else { negative[event.depth,default: 0] += event.change }
                previous = event.t
            }
        }
        return result
    }
}

/// Display-only duplicate removal; source opening records and wall holes stay intact.
struct StudioOpeningDeduplicator {
    private struct Entry {
        let id: UUID; let roomID: UUID; let story: Int; let kind: Opening.Kind
        let center: Point2D; let direction: Point2D; let width: Double; let height: Double; let sill: Double; let thickness: Double
    }
    private var entries: [Entry] = []
    mutating func includes(_ opening: Opening,in room: FloorPlan) -> Bool {
        let angle = opening.angle+room.transform.rotation
        let item = Entry(id: opening.id,roomID: room.id,story: room.story,kind: opening.kind,center: room.transform.apply(opening.center),direction: .init(x: cos(angle),y: sin(angle)),width: opening.width,height: opening.height,sill: opening.sillHeight,thickness: room.wall(withID: opening.wallID)?.thickness ?? 0.1)
        for old in entries where old.story == item.story && old.kind == item.kind {
            if old.id == item.id { return false }
            let alignment = abs(old.direction.x*item.direction.x+old.direction.y*item.direction.y)
            guard abs(old.width-item.width) <= max(0.1,min(old.width,item.width)*0.15),abs(old.height-item.height) <= 0.15,abs(old.sill-item.sill) <= 0.08,
                  alignment >= cos(.pi/24) else { continue }
            let delta = item.center-old.center
            let along = abs(delta.x*old.direction.x+delta.y*old.direction.y),normal = abs(-delta.x*old.direction.y+delta.y*old.direction.x)
            // Continuous captures can duplicate a shared doorway inside the same
            // room record. Compare projected overlap, not room membership.
            let projectedWidth = item.width*alignment
            let overlap = max(0,min(old.width/2,along+projectedWidth/2)-max(-old.width/2,along-projectedWidth/2))
            let overlapRatio = overlap/max(old.width,projectedWidth)
            let wallDepth = min(0.25,max(0.08,max(old.thickness,item.thickness)+0.08))
            if overlapRatio >= 0.8 && normal <= wallDepth { return false }
        }
        entries.append(item); return true
    }
}
