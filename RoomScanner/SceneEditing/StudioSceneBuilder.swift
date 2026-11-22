import SceneKit
import simd

/// Native, bounded procedural models. These are design representations, not new scan evidence.
@MainActor enum StudioSceneBuilder {
    static func material(_ color: TechnicalPoint3,roughness: Double = 0.7,metal: Double = 0) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = platformColor(CGColor(red: color.x,green: color.y,blue: color.z,alpha: 1))
        m.roughness.contents = roughness; m.metalness.contents = metal
        return m
    }
    static func scene(_ document: SceneEditDocument,story: Int?,cutaway: Bool,decorated: Bool = true) -> SCNScene {
        let scene = SCNScene()
        let roomIDs = Set(document.shell.stories.filter { story == nil || $0.index == story }.flatMap(\.rooms).map(\.id))
        let rooms = document.shell.allRooms.filter { roomIDs.contains($0.id) }
        let floorMaterial = material(document.floorColor,roughness: 0.85)
        if document.source != .technical {
            floorMaterial.diffuse.contents = floorTexture(document.floorColor)
            floorMaterial.diffuse.wrapS = .repeat; floorMaterial.diffuse.wrapT = .repeat
            floorMaterial.diffuse.mipFilter = .linear
        }
        let wallMaterial = material(document.wallColor)
        for room in rooms {
            var visibleWalls = Set<UUID>()
            let roomCenter = room.transform.apply(room.bounds.center)
            var floor = TriangleMesh()
            PlanMeshBuilder.addFloor(room,transform: room.transform,thickness: 0.08,to: &floor)
            if !floor.isEmpty { scene.rootNode.addChildNode(meshNode(floor,material: floorMaterial,name: "shell:floor")) }
            for wall in room.walls where document.includesElement(wall.id) {
                let midpoint = room.transform.apply(wall.segment.midpoint)
                // Presentation cutaway only. Complete walls remain in the saved shell and exports.
                if cutaway && (midpoint.x-roomCenter.x)-(midpoint.y-roomCenter.y) > 0.15 { continue }
                visibleWalls.insert(wall.id)
                var mesh = TriangleMesh()
                for box in WallGeometry().wallBoxes(wall,openings: room.openings.filter { $0.wallID == wall.id }) {
                    PlanMeshBuilder.addBox(box,transform: room.transform,to: &mesh)
                }
                if !mesh.isEmpty { scene.rootNode.addChildNode(meshNode(mesh,material: wallMaterial,name: "shell:wall")) }
            }
            let joins = StudioWallJoins.mesh(room: room,visible: visibleWalls)
            if !joins.isEmpty { scene.rootNode.addChildNode(meshNode(joins,material: wallMaterial,name: "shell:wall-joins")) }
            for opening in room.openings where opening.kind != .opening && document.includesElement(opening.wallID) {
                guard let box = WallGeometry().panelBox(opening,wall: room.wall(withID: opening.wallID)) else { continue }
                let midpoint = room.transform.apply(box.segment.midpoint)
                if cutaway && (midpoint.x-roomCenter.x)-(midpoint.y-roomCenter.y) > 0.15 { continue }
                var mesh = TriangleMesh(); PlanMeshBuilder.addBox(box,transform: room.transform,to: &mesh)
                let m = material(opening.kind == .door ? .init(x: 0.57,y: 0.39,z: 0.24) : .init(x: 0.61,y: 0.77,z: 0.80),roughness: 0.3)
                scene.rootNode.addChildNode(meshNode(mesh,material: m,name: "shell:opening"))
            }
        }
        for item in document.presentationObjects where story == nil || item.story == story { scene.rootNode.addChildNode(model(item,technical: document.source == .technical)) }
        if decorated {
            let night = document.source != .technical && document.lighting == .night
            let winter = document.source != .technical && document.season == .winter
            scene.background.contents = platformColor(CGColor(gray: night ? 0.09 : 0.87,alpha: 1))
            let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
            ambient.light?.intensity = night ? 220 : 400
            ambient.light?.color = platformColor(CGColor(red: 1,green: winter ? 0.87 : 0.96,blue: winter ? 0.73 : 0.94,alpha: 1))
            scene.rootNode.addChildNode(ambient)
            let light = SCNNode(); light.light = SCNLight(); light.light?.type = .directional
            light.light?.intensity = night ? 500 : 850; light.light?.castsShadow = document.source != .technical
            light.light?.shadowMode = .deferred; light.light?.shadowRadius = 6
            light.light?.shadowSampleCount = 8; light.light?.shadowMapSize = .init(width: 1024,height: 1024)
            light.light?.automaticallyAdjustsShadowProjection = true
            light.light?.shadowBias = 0.005
            light.light?.shadowColor = platformColor(CGColor(gray: 0,alpha: 0.24))
            light.eulerAngles = SCNVector3(-Double.pi/3,-Double.pi/5,0); scene.rootNode.addChildNode(light)
        }
        return scene
    }
    static func meshNode(_ mesh: TriangleMesh,material: SCNMaterial,name: String) -> SCNNode {
        let source = SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0.x,$0.y,$0.z) })
        let normals = SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0.x,$0.y,$0.z) })
        let indices = mesh.triangles.flatMap { [$0.x,$0.y,$0.z] }
        let uv = SCNGeometrySource(textureCoordinates: mesh.positions.map { CGPoint(x: Double($0.x)/1.2,y: Double($0.z)/1.2) })
        let geometry = SCNGeometry(sources: [source,normals,uv],elements: [SCNGeometryElement(indices: indices,primitiveType: .triangles)])
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry); node.name = name; return node
    }
    private static func floorTexture(_ base: TechnicalPoint3) -> CGImage? {
        guard let context = CGContext(data: nil,width: 512,height: 512,bitsPerComponent: 8,bytesPerRow: 2048,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for row in 0..<4 {
            let variation = Double(row%3-1)*0.025
            context.setFillColor(CGColor(red: min(1,max(0,base.x+variation)),green: min(1,max(0,base.y+variation)),blue: min(1,max(0,base.z+variation)),alpha: 1))
            context.fill(CGRect(x: 0,y: row*128,width: 512,height: 128))
            context.setStrokeColor(CGColor(gray: 0.12,alpha: 0.20)); context.setLineWidth(2)
            context.move(to: CGPoint(x: 0,y: row*128)); context.addLine(to: CGPoint(x: 512,y: row*128))
            let split = row%2 == 0 ? 170 : 350
            context.move(to: CGPoint(x: split,y: row*128)); context.addLine(to: CGPoint(x: split,y: (row+1)*128)); context.strokePath()
            context.setStrokeColor(CGColor(gray: 0.15,alpha: 0.045)); context.setLineWidth(1)
            for line in 1..<12 {
                let y = CGFloat(row*128+line*10)
                context.move(to: CGPoint(x: 0,y: y)); context.addCurve(to: CGPoint(x: 512,y: y+3),control1: CGPoint(x: 170,y: y-4),control2: CGPoint(x: 340,y: y+6)); context.strokePath()
            }
        }
        return context.makeImage()
    }
    static func model(_ item: SceneEditObject,technical: Bool = false) -> SCNNode {
        let root = SCNNode(); root.name = "object:"+item.id.uuidString
        root.simdPosition = SIMD3(Float(item.position.x),Float(item.position.y),Float(item.position.z))
        root.simdOrientation = simd_quatf(vector: SIMD4<Float>(item.orientation.vector))
        let w = item.size.x,h = item.size.y,d = item.size.z
        let main = material(item.color,roughness: item.finish == .fabric ? 0.95 : item.finish == .metal ? 0.28 : 0.65,metal: item.finish == .metal ? 0.75 : 0)
        if technical {
            // Exact parametric envelope. No rounded-off corners or invented equipment details.
            let geometry: SCNGeometry
            if [SceneFurniture.pipe,.roundDuct,.cylinder,.tank].contains(item.family) {
                let cylinder = SCNCylinder(radius: w/2,height: h)
                cylinder.radialSegmentCount = 24; cylinder.heightSegmentCount = 1
                geometry = cylinder
            } else { geometry = SCNBox(width: w,height: h,length: d,chamferRadius: 0) }
            geometry.materials = [main]
            let child = SCNNode(geometry: geometry)
            if geometry is SCNCylinder { child.simdScale.z = Float(d/w) }
            root.addChildNode(child); return root
        }
        let cream = material(.init(x: 0.90,y: 0.87,z: 0.77),roughness: 0.8)
        let wood = material(.init(x: 0.64,y: 0.43,z: 0.23))
        let dark = material(.init(x: 0.11,y: 0.14,z: 0.15),roughness: 0.3)
        let metal = material(.init(x: 0.65,y: 0.67,z: 0.68),roughness: 0.25,metal: 0.8)
        func box(_ x: Double,_ y: Double,_ z: Double,_ width: Double,_ height: Double,_ depth: Double,_ m: SCNMaterial? = nil,_ rounded: Bool = true) {
            let a = max(0.001,width*w),b = max(0.001,height*h),c = max(0.001,depth*d)
            let geometry = SCNBox(width: a,height: b,length: c,chamferRadius: rounded ? min(a,b,c)*0.16 : 0)
            geometry.chamferSegmentCount = 3; geometry.materials = [m ?? main]
            let node = SCNNode(geometry: geometry); node.position = SCNVector3(x*w,(y-0.5)*h,z*d); root.addChildNode(node)
        }
        func cylinder(_ x: Double,_ y: Double,_ z: Double,_ radius: Double,_ height: Double,_ m: SCNMaterial? = nil) {
            let geometry = SCNCylinder(radius: radius*min(w,d),height: height*h)
            geometry.radialSegmentCount = 20; geometry.heightSegmentCount = 1; geometry.materials = [m ?? main]
            let node = SCNNode(geometry: geometry); node.position = SCNVector3(x*w,(y-0.5)*h,z*d); root.addChildNode(node)
        }
        func legs(_ top: Double) {
            let thickness = min(min(w,d)*0.15,min(0.06,max(0.015,min(w,d)*0.07)))
            for x in [-0.40,0.40] { for z in [-0.38,0.38] { box(x,top/2,z,thickness/w,top,thickness/d,wood) } }
        }
        switch item.family {
        case .sofa:
            legs(0.17); box(0,0.32,0,0.98,0.30,0.96)
            box(0,0.73,-0.39,0.98,0.54,0.22)
            let arm = min(w*0.18,min(0.18,max(0.03,w*0.08)))/w
            for x in [-0.5+arm/2,0.5-arm/2] { box(x,0.55,0,arm,0.44,0.96) }
            let count = max(1,min(4,Int((w/0.7).rounded())))
            for i in 0..<count { box(-0.37+0.74*(Double(i)+0.5)/Double(count),0.51,0.07,0.74/Double(count)-0.01,0.12,0.70,cream) }
        case .bed:
            legs(0.12); box(0,0.28,0,0.98,0.32,0.98,wood)
            box(0,0.50,0.02,0.94,0.20,0.94,cream); box(0,0.74,-0.46,0.98,0.52,0.08)
            for x in w >= 1.2 ? [-0.23,0.23] : [0] { box(x,0.65,-0.28,w >= 1.2 ? 0.40 : 0.80,0.12,0.22) }
        case .chair:
            legs(0.46); box(0,0.48,0,0.98,0.12,0.96); box(0,0.76,-0.40,0.96,0.48,0.16)
        case .table:
            legs(0.92); box(0,0.95,0,1,0.10,1,wood)
        case .television:
            box(0,0.56,0,1,0.88,0.65,dark); box(0,0.56,0.34,0.92,0.78,0.03,material(.init(x: 0.18,y: 0.27,z: 0.31),roughness: 0.2))
            box(0,0.12,0,0.10,0.20,0.35,metal); box(0,0.03,0,0.50,0.06,0.85,dark)
        case .cabinet,.refrigerator,.stove,.washer,.electricalPanel,.shower:
            box(0,0.50,-0.03,1,1,0.94)
            if item.family == .stove { box(0,0.99,0,0.94,0.02,0.92,dark); box(0,0.47,0.47,0.78,0.48,0.04,dark) }
            else if item.family == .washer { cylinder(0,0.5,0,0.24,0.05,metal); box(0,0.5,0.47,0.62,0.60,0.04,dark) }
            else {
                let modules = item.family == .cabinet ? max(1,min(12,Int((w/0.6).rounded()))) : 1
                for i in 0..<modules {
                    let x = -0.5+(Double(i)+0.5)/Double(modules)
                    box(x,0.51,0.46,0.96/Double(modules),0.90,0.04,main)
                    box(x+0.27/Double(modules),0.62,0.49,min(0.03,0.025/w),0.18,0.02,metal)
                }
            }
        case .sink,.bathtub:
            box(0,0.15,0,1,0.30,1,cream)
            for x in [-0.45,0.45] { box(x,0.64,0,0.10,0.72,1,cream) }
            for z in [-0.45,0.45] { box(0,0.64,z,0.80,0.72,0.10,cream) }
        case .toilet:
            cylinder(0,0.28,0.12,0.32,0.55,cream); box(0,0.53,0.1,0.83,0.12,0.7,cream)
            box(0,0.73,-0.34,0.88,0.54,0.30,cream)
        case .radiator:
            let count = max(3,min(24,Int(w/0.06)))
            for i in 0..<count { box(-0.5+(Double(i)+0.5)/Double(count),0.5,0,0.88/Double(count),1,1,cream) }
        case .boiler,.tank:
            cylinder(0,0.50,0,0.48,0.88)
            box(0,0.57,0.47,0.24,0.16,0.04,dark)
            cylinder(0,0.95,0,0.40,0.10,cream); cylinder(0,0.05,0,0.40,0.10,metal)
        case .pump: cylinder(0,0.5,0,0.40,0.75); box(0,0.20,0,0.95,0.16,0.95,metal)
        case .manifold:
            box(0,0.7,0,1,0.12,0.4,metal); box(0,0.3,0,1,0.12,0.4,metal)
            for i in 0..<6 { cylinder(-0.42+Double(i)*0.168,0.5,0,0.045,0.9,metal) }
        case .pipe,.roundDuct,.cylinder: cylinder(0,0.5,0,0.5,1)
        case .rectangularDuct,.box: box(0,0.5,0,1,1,1,nil,item.family != .rectangularDuct)
        }
        return root
    }
}
