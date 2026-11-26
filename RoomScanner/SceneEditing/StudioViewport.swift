import SwiftUI
import SceneKit
import Metal

enum StudioCameraFraming {
    static func distance(width: Double,height: Double,depth: Double,aspect: Double) -> Double {
        let radius = max(0.5,sqrt(width*width+height*height+depth*depth)/2)
        let verticalHalfAngle = 21*Double.pi/180
        let halfAngle = min(verticalHalfAngle,atan(tan(verticalHalfAngle)*max(0.1,aspect)))
        return radius/sin(halfAngle)*1.08
    }
}

@MainActor final class StudioSceneController: NSObject {
    weak var view: SCNView?
    let camera = SCNNode()
    private var previous: SceneEditDocument?
    private var previousStory: Int?
    private var previousCutaway = false
    private var previousRendering: SceneEditDocument?
    private var previousDimensions = false
    private var previousDimensionSelection: UUID?
    private var resetToken = 0
    private var lastAspect = 0.0
    private var selected: UUID?
    private var dragNode: SCNNode?
    private var dragStart: SIMD3<Float>?
    private var dragOrigin = SIMD3<Float>.zero
    private var dragAxis: SIMD3<Float>?
    private var dragOrientation = simd_quatf()
    private var rotationStart: Float?
    private var rotationDelta = 0.0
    private var dragScreenStart = CGPoint.zero
    private let selectionOverlay = SCNNode()
    var moving = false
    var rotating = false
    var selectedIDs: Set<UUID> = [] { didSet { if oldValue != selectedIDs { highlight(selected) } } }
    var manipulating: Bool { moving || rotating }
    var onSelect: ((UUID?) -> Void)?
    var onNote:((UUID)->Void)?
    private var notes:[ARNote] = []
    private let noteRoot = SCNNode()
    func setNotes(_ values:[ARNote]) {
        guard values != notes else { return }; notes = values; updateNotes()
    }
    private func updateNotes() {
        noteRoot.removeFromParentNode(); noteRoot.childNodes.forEach { $0.removeFromParentNode() }
        for note in notes.suffix(256) {
            if let level = note.level,level != previousStory { continue }
            guard let p = note.viewingPosition else { continue }
            let node = iconNode(symbol:note.audioFileName == nil ? "mappin" : AnnotationPresentation.audioSymbol,name:"note:"+note.id.uuidString)
            let height = note.audioFileName == nil ? 0.12 : 0.28
            node.position = SCNVector3(p.x,p.y+height,p.z); noteRoot.addChildNode(node)
            if let stem = annotationLine(from:p,to:.init(x:p.x,y:p.y+height,z:p.z)) { noteRoot.addChildNode(stem) }
            if let camera = note.viewingCameraPosition,let ray = annotationLine(from:camera,to:p) { noteRoot.addChildNode(ray) }
        }
        view?.scene?.rootNode.addChildNode(noteRoot)
    }
    private func iconNode(symbol:String,name:String) -> SCNNode {
        let material = SCNMaterial(); material.lightingModel = .constant; material.isDoubleSided = true
        material.readsFromDepthBuffer = false; material.writesToDepthBuffer = false
        material.diffuse.contents = AnnotationIcon.image(symbol)
        let node = SCNNode(geometry:SCNPlane(width:0.16,height:0.16)); node.name = name
        node.renderingOrder = 1000
        node.geometry?.materials = [material]; node.constraints = [SCNBillboardConstraint()]; return node
    }
    private func annotationLine(from a:TechnicalPoint3,to b:TechnicalPoint3) -> SCNNode? {
        let start = SIMD3<Float>(Float(a.x),Float(a.y),Float(a.z)),end = SIMD3<Float>(Float(b.x),Float(b.y),Float(b.z))
        let delta = end-start,length = simd_length(delta)
        guard length.isFinite,length > 0.001 else { return nil }
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = platformColor(CGColor(red:0.45,green:0.4,blue:0.95,alpha:1))
        let node = SCNNode(geometry:SCNCylinder(radius:0.002,height:CGFloat(length)))
        node.geometry?.materials = [material]; node.simdPosition = (start+end)/2
        node.simdOrientation = simd_quatf(from:SIMD3(0,1,0),to:delta/length); return node
    }
    var onPhoto: ((UUID) -> Void)?
    private var photos: [SurveyPhotoImage] = []
    private let photoRoot = SCNNode()
    private var selectedPhotoID:UUID?
    func selectPhotoMarker(_ id:UUID?) { selectedPhotoID = id; updatePhotoSelection() }
    private func updatePhotoSelection() {
        for node in photoRoot.childNodes {
            let selected = selectedPhotoID.map { node.name == "photo:"+$0.uuidString } ?? false
            if let icon = node.childNodes.first { icon.scale = selected ? SCNVector3(1.25,1.25,1.25) : SCNVector3(1,1,1) }
        }
    }
    func setPhotos(_ photos: [SurveyPhotoImage]) {
        guard self.photos != photos else { return }; self.photos = photos
        updatePhotos()
    }
    private func updatePhotos() {
        photoRoot.removeFromParentNode()
        photoRoot.childNodes.forEach { $0.removeFromParentNode() }
        for image in photos {
            if let roomID = image.photo.roomID,
               let room = previous?.shell.allRooms.first(where:{ $0.id == roomID }), room.story != previousStory { continue }
            let m = image.photo.viewingPose
            guard m.count == 16 else { continue }
            let node = SCNNode()
            node.name = "photo:"+image.id.uuidString
            node.simdTransform = simd_float4x4(columns:(
                SIMD4(Float(m[0]),Float(m[1]),Float(m[2]),0),SIMD4(Float(m[4]),Float(m[5]),Float(m[6]),0),
                SIMD4(Float(m[8]),Float(m[9]),Float(m[10]),0),SIMD4(Float(m[12]),Float(m[13]),Float(m[14]),1)))
            let body = iconNode(symbol:AnnotationPresentation.cameraSymbol,name:node.name ?? "")
            node.addChildNode(body)
            let corners = AnnotationPresentation.directionCorners
            for i in corners.indices {
                if let ray = annotationLine(from:.init(x:0,y:0,z:0),to:corners[i]) { node.addChildNode(ray) }
                if let edge = annotationLine(from:corners[i],to:corners[(i+1)%4]) { node.addChildNode(edge) }
            }
            photoRoot.addChildNode(node)
        }
        view?.scene?.rootNode.addChildNode(photoRoot)
        updatePhotoSelection()
    }
    func flyToPhoto(_ photo: SurveyPhoto) {
        let m = photo.viewingPose
        guard m.count == 16 else { return }
        camera.simdTransform = simd_float4x4(columns:(
            SIMD4(Float(m[0]),Float(m[1]),Float(m[2]),0),SIMD4(Float(m[4]),Float(m[5]),Float(m[6]),0),
            SIMD4(Float(m[8]),Float(m[9]),Float(m[10]),0),SIMD4(Float(m[12]),Float(m[13]),Float(m[14]),1)))
        view?.defaultCameraController.target = SCNVector3(Float(m[12]-m[8]),Float(m[13]-m[9]),Float(m[14]-m[10]))
    }
    var onMove: ((UUID,TechnicalPoint3) -> Bool)?
    var onRotate: ((UUID,Double) -> Bool)?
    var movementAxis: TechnicalPointEditing.Axis {
        if dragAxis == SIMD3<Float>(1,0,0) { return .x }
        if dragAxis == SIMD3<Float>(0,1,0) { return .y }
        if dragAxis == SIMD3<Float>(0,0,1) { return .z }
        return .free
    }
    func configure(_ document: SceneEditDocument,story: Int,cutaway: Bool,selected: UUID?,moving: Bool,reset: Int,showDimensions: Bool = false,rotating: Bool = false) {
        guard let view else { return }
        self.moving = moving && selectedIDs.count <= 1
        self.rotating = rotating && selectedIDs.count <= 1
        view.allowsCameraControl = !manipulating
        let rendering = document.renderingSnapshot
        let layoutChanged = view.scene == nil || previousStory != story || previousCutaway != cutaway || previousDimensions != showDimensions || (showDimensions && previousDimensionSelection != selected)
        if dragNode == nil && (previousRendering != rendering || layoutChanged) {
            let patched = !layoutChanged && !showDimensions && patchObjects(document, rendering:rendering, story:story)
            if !patched {
                let scene = StudioSceneBuilder.scene(document,story: story,cutaway: cutaway,showDimensions: showDimensions,dimensionSelection: selected)
                scene.rootNode.addChildNode(camera); view.scene = scene; view.pointOfView = camera
                if previous == nil || previousStory != story { frame(document,story: story) }
            }
            previousRendering = rendering; previousStory = story; previousCutaway = cutaway
            previousDimensions = showDimensions; previousDimensionSelection = selected
        }
        previous = document
        if photoRoot.parent !== view.scene?.rootNode { updatePhotos() }
        if noteRoot.parent !== view.scene?.rootNode { updateNotes() }
        if resetToken != reset { resetToken = reset; frame(document,story: story) }
        self.selected = selected; highlight(selected)
        applyCameraAppearance(document)
        viewportDidLayout()
    }
    /// Patch only object changes when the complete non-object rendering state is
    /// identical. Architecture, templates, lighting, floors and dimensions keep
    /// their established full-build path. Drag callbacks still own active gestures.
    private func patchObjects(_ document:SceneEditDocument,rendering:SceneEditDocument,story:Int) -> Bool {
        guard let before = previousRendering,let root = view?.scene?.rootNode else { return false }
        var oldShell = before,newShell = rendering
        oldShell.objects = []; newShell.objects = []
        guard oldShell == newShell else { return false }
        let old = Dictionary(grouping:before.presentationObjects.filter { $0.story == story },by:\.id)
        let new = Dictionary(grouping:rendering.presentationObjects.filter { $0.story == story },by:\.id)
        guard old.values.allSatisfy({ $0.count == 1 }),new.values.allSatisfy({ $0.count == 1 }) else { return false }
        // Refuse partial scene state; the caller will rebuild deterministically.
        guard old.keys.allSatisfy({ root.childNode(withName:"object:"+$0.uuidString,recursively:false) != nil }) else { return false }
        let interval = PerformanceTrace.begin("StudioObjectUpdate")
        defer { interval.end() }
        for id in old.keys where new[id] == nil { root.childNode(withName:"object:"+id.uuidString,recursively:false)?.removeFromParentNode() }
        for item in document.presentationObjects where item.story == story && old[item.id]?.first != new[item.id]?.first {
            root.childNode(withName:"object:"+item.id.uuidString,recursively:false)?.removeFromParentNode()
            root.addChildNode(StudioSceneBuilder.model(item,technical:document.source == .technical,
                                                      refinedTechnical:document.technicalTemplate != nil && document.technicalTemplate != .captured))
        }
        return true
    }
    private func applyCameraAppearance(_ document: SceneEditDocument) {
        camera.camera?.screenSpaceAmbientOcclusionIntensity = document.source == .technical ? 0 : 0.55
        camera.camera?.screenSpaceAmbientOcclusionRadius = 0.25
        camera.camera?.screenSpaceAmbientOcclusionBias = 0.03
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = document.source == .technical ? 0 : -0.2
    }
    func viewportDidLayout() {
        guard let view,view.bounds.width > 0,view.bounds.height > 0,let document = previous,let story = previousStory else { return }
        let aspect = Double(view.bounds.width/view.bounds.height)
        guard abs(aspect-lastAspect) > 0.01 else { return }
        lastAspect = aspect; frame(document,story: story)
    }
    private func frame(_ document: SceneEditDocument,story: Int) {
        let house = House(name: "",stories: document.shell.stories.filter { $0.index == story })
        var bounds = house.bounds
        let items = document.presentationObjects.filter { $0.story == story }
        var lowest = 0.0,highest = max(1,house.allRooms.flatMap(\.walls).map(\.height).max() ?? 1)
        for item in items {
            for point in StudioPlacement.corners(item) {
                bounds = bounds.union(.init(x: point.x,y: -point.z))
                lowest = min(lowest,point.y); highest = max(highest,point.y)
            }
        }
        let center = bounds.isEmpty ? SIMD3<Float>(0,0.7,0) : SIMD3(Float(bounds.center.x),Float((highest+lowest)/2),Float(-bounds.center.y))
        let aspect = view.map { $0.bounds.width > 0 && $0.bounds.height > 0 ? Double($0.bounds.width/$0.bounds.height) : 1 } ?? 1
        let distance = Float(StudioCameraFraming.distance(width: max(1,bounds.width),height: highest-lowest,depth: max(1,bounds.height),aspect: aspect))
        camera.camera = SCNCamera(); camera.camera?.fieldOfView = 42
        applyCameraAppearance(document)
        camera.camera?.zNear = 0.02; camera.camera?.zFar = Double(max(4000,distance*3))
        camera.simdPosition = center+simd_normalize(SIMD3<Float>(1.05,0.95,1.05))*distance
        camera.look(at: SCNVector3(center.x,center.y,center.z))
        view?.defaultCameraController.target = SCNVector3(center.x,center.y,center.z)
    }
    private func objectNode(at point: CGPoint) -> SCNNode? {
        guard let view,let previous,let root = view.scene?.rootNode else { return nil }
        let a = view.unprojectPoint(SCNVector3(Float(point.x),Float(point.y),0)),b = view.unprojectPoint(SCNVector3(Float(point.x),Float(point.y),1))
        let origin = SIMD3(Double(a.x),Double(a.y),Double(a.z)),direction = SIMD3(Double(b.x-a.x),Double(b.y-a.y),Double(b.z-a.z))
        var nearest = Double.infinity,result: SCNNode?
        for item in previous.presentationObjects {
            guard let node = root.childNode(withName: "object:"+item.id.uuidString,recursively: false),
                  let distance = StudioPlacement.rayIntersection(item,origin: origin,direction: direction),distance < nearest else { continue }
            nearest = distance; result = node
        }
        return result
    }
    func tap(_ point: CGPoint) {
        if let hits = view?.hitTest(point,options:[.searchMode:SCNHitTestSearchMode.all.rawValue]) {
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name,name.hasPrefix("note:"),let id = UUID(uuidString:String(name.dropFirst(5))) { onNote?(id); return }
                    if let name = current.name,name.hasPrefix("photo:"),let id = UUID(uuidString:String(name.dropFirst(6))) {
                        onPhoto?(id); return
                    }
                    node = current.parent
                }
            }
        }
        if gizmoAxis(at: point) != nil || hitsRotationRing(point) { return }
        let node = objectNode(at: point)
        let id = node?.name.flatMap { UUID(uuidString: String($0.dropFirst(7))) }
        selected = id; highlight(id); onSelect?(id)
    }
    func beginDrag(_ point: CGPoint) {
        guard manipulating else { return }
        dragAxis = gizmoAxis(at: point)
        let node: SCNNode?
        if (dragAxis != nil || hitsRotationRing(point)),let selected { node = view?.scene?.rootNode.childNode(withName: "object:"+selected.uuidString,recursively: false) }
        else { node = objectNode(at: point) }
        guard let node else { return }
        dragNode = node; dragOrigin = node.simdPosition; dragScreenStart = point
        dragOrientation = node.simdOrientation; rotationDelta = 0
        if dragAxis == nil && !hitsRotationRing(point) { tap(point) }
        dragStart = plane(point,y: dragOrigin.y)
        rotationStart = dragStart.map { atan2($0.z-dragOrigin.z,$0.x-dragOrigin.x) }
    }
    func drag(_ point: CGPoint) {
        guard let node = dragNode else { return }
        if rotating {
            guard let start = rotationStart,let hit = plane(point,y: dragOrigin.y) else { return }
            let angle = start-atan2(hit.z-dragOrigin.z,hit.x-dragOrigin.x)
            rotationDelta = Double(atan2(sin(angle),cos(angle)))
            node.simdOrientation = simd_quatf(angle: Float(rotationDelta),axis: SIMD3(0,1,0))*dragOrientation
            selectionOverlay.childNode(withName: "selection-envelope",recursively: false)?.simdOrientation = node.simdOrientation
            return
        }
        let position: SIMD3<Float>
        if let axis = dragAxis,let view {
            let a = view.projectPoint(SCNVector3(dragOrigin.x,dragOrigin.y,dragOrigin.z))
            let b = view.projectPoint(SCNVector3(dragOrigin.x+axis.x,dragOrigin.y+axis.y,dragOrigin.z+axis.z))
            let screen = SIMD2<Double>(Double(b.x-a.x),Double(b.y-a.y))
            guard simd_length_squared(screen) > 64 else { return }
            let delta = SIMD2<Double>(point.x-dragScreenStart.x,point.y-dragScreenStart.y)
            position = dragOrigin+axis*Float(simd_dot(delta,screen)/simd_length_squared(screen))
        } else {
            guard let start = dragStart,let hit = plane(point,y: dragOrigin.y) else { return }
            position = dragOrigin+hit-start
        }
        guard [position.x,position.y,position.z].allSatisfy({ $0.isFinite && abs($0) <= 1000 }) else { return }
        node.simdPosition = position
        selectionOverlay.simdPosition = position
    }
    func endDrag(cancelled: Bool = false) {
        defer { dragNode = nil; dragStart = nil; dragAxis = nil; rotationStart = nil; highlight(selected) }
        guard let node = dragNode,let id = node.name.flatMap({ UUID(uuidString: String($0.dropFirst(7))) }) else { return }
        if rotating {
            if cancelled || onRotate?(id,rotationDelta) != true { node.simdOrientation = dragOrientation }
            return
        }
        if cancelled { node.simdPosition = dragOrigin; return }
        let p = node.simdPosition
        if onMove?(id,.init(x: Double(p.x),y: Double(p.y),z: Double(p.z))) != true { node.simdPosition = dragOrigin }
    }
    private func plane(_ point: CGPoint,y: Float) -> SIMD3<Float>? {
        guard let view else { return nil }
        let a = view.unprojectPoint(SCNVector3(Float(point.x),Float(point.y),0))
        let b = view.unprojectPoint(SCNVector3(Float(point.x),Float(point.y),1))
        let near = SIMD3(Float(a.x),Float(a.y),Float(a.z)),far = SIMD3(Float(b.x),Float(b.y),Float(b.z))
        let ray = far-near
        guard abs(ray.y) > 0.00001 else { return nil }
        let t = (y-near.y)/ray.y
        guard t >= 0,t <= 1 else { return nil }
        return near+ray*t
    }
    private func highlight(_ id: UUID?) {
        selectionOverlay.removeFromParentNode()
        view?.scene?.rootNode.enumerateChildNodes { node,_ in
            guard let geometry = node.geometry else { return }
            var ancestor: SCNNode? = node
            var active = false
            while let current = ancestor {
                if let name = current.name,
                   name == id.map({ "object:"+$0.uuidString }) || selectedIDs.contains(where: { name == "object:"+$0.uuidString }) { active = true; break }
                ancestor = current.parent
            }
            for material in geometry.materials { material.emission.contents = active ? platformColor(CGColor(red: 0.12,green: 0.23,blue: 0.30,alpha: 1)) : platformColor(CGColor(gray: 0,alpha: 1)) }
        }
        selectionOverlay.childNodes.forEach { $0.removeFromParentNode() }
        guard let id,let item = previous?.presentationObjects.first(where: { $0.id == id }),let root = view?.scene?.rootNode else { return }
        selectionOverlay.name = "selection-overlay"
        selectionOverlay.simdPosition = SIMD3(Float(item.position.x),Float(item.position.y),Float(item.position.z))
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = platformColor(CGColor(red: 0.1,green: 0.5,blue: 1,alpha: 1))
        material.fillMode = .lines; material.readsFromDepthBuffer = false; material.writesToDepthBuffer = false
        let half = SIMD3<Float>(Float(item.size.x+0.015),Float(item.size.y+0.015),Float(item.size.z+0.015))/2
        let corners = [SIMD3(-half.x,-half.y,-half.z),SIMD3(half.x,-half.y,-half.z),SIMD3(half.x,half.y,-half.z),SIMD3(-half.x,half.y,-half.z),SIMD3(-half.x,-half.y,half.z),SIMD3(half.x,-half.y,half.z),SIMD3(half.x,half.y,half.z),SIMD3(-half.x,half.y,half.z)]
        let source = SCNGeometrySource(vertices: corners.map { SCNVector3($0.x,$0.y,$0.z) })
        let edges: [UInt32] = [0,1,1,2,2,3,3,0,4,5,5,6,6,7,7,4,0,4,1,5,2,6,3,7]
        let box = SCNGeometry(sources: [source],elements: [SCNGeometryElement(indices: edges,primitiveType: .line)])
        material.fillMode = .fill; box.materials = [material]
        let outline = SCNNode(geometry: box); outline.name = "selection-envelope"
        outline.simdOrientation = simd_quatf(vector: SIMD4<Float>(item.orientation.vector)); outline.renderingOrder = 1000; outline.castsShadow = false
        selectionOverlay.addChildNode(outline)
        if moving {
            let length = Float(min(1.2,max(0.45,max(item.size.x,item.size.y,item.size.z)*0.45)))
            for (name,axis,color) in [("x",SIMD3<Float>(1,0,0),CGColor(red: 0.95,green: 0.2,blue: 0.2,alpha: 1)),("y",SIMD3<Float>(0,1,0),CGColor(red: 0.2,green: 0.8,blue: 0.3,alpha: 1)),("z",SIMD3<Float>(0,0,1),CGColor(red: 0.1,green: 0.5,blue: 1,alpha: 1))] {
                let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = platformColor(color); m.readsFromDepthBuffer = false
                let shaft = SCNNode(geometry: SCNCylinder(radius: 0.014,height: Double(length)))
                shaft.simdPosition = axis*length/2; shaft.simdOrientation = simd_quatf(from: SIMD3(0,1,0),to: axis)
                let tip = SCNNode(geometry: SCNCone(topRadius: 0,bottomRadius: 0.045,height: 0.12))
                tip.simdPosition = axis*(length+0.06); tip.simdOrientation = shaft.simdOrientation
                for node in [shaft,tip] { node.name = "gizmo:"+name; node.geometry?.materials = [m]; node.renderingOrder = 1001; node.castsShadow = false; selectionOverlay.addChildNode(node) }
                let label = SCNText(string: name.uppercased(),extrusionDepth: 0); label.font = .systemFont(ofSize: 12,weight: .bold); label.materials = [m]
                let text = SCNNode(geometry: label); text.scale = SCNVector3(0.008,0.008,0.008); text.simdPosition = axis*(length+0.16); text.constraints = [SCNBillboardConstraint()]; text.renderingOrder = 1001; text.castsShadow = false
                selectionOverlay.addChildNode(text)
            }
        }
        if rotating {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: max(item.size.x,item.size.z)/2+0.18,pipeRadius: 0.018))
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = platformColor(CGColor(red: 0.95,green: 0.65,blue: 0.1,alpha: 1)); m.readsFromDepthBuffer = false
            ring.geometry?.materials = [m]; ring.name = "gizmo:rotate"; ring.renderingOrder = 1001; ring.castsShadow = false
            selectionOverlay.addChildNode(ring)
        }
        root.addChildNode(selectionOverlay)
    }
    private func hitsRotationRing(_ point: CGPoint) -> Bool {
        rotating && view?.hitTest(point,options: [.searchMode: SCNHitTestSearchMode.all.rawValue]).contains { $0.node.name == "gizmo:rotate" } == true
    }
    private func gizmoAxis(at point: CGPoint) -> SIMD3<Float>? {
        guard moving,let view else { return nil }
        for hit in view.hitTest(point,options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            switch hit.node.name {
            case "gizmo:x": return SIMD3(1,0,0)
            case "gizmo:y": return SIMD3(0,1,0)
            case "gizmo:z": return SIMD3(0,0,1)
            default: continue
            }
        }
        return nil
    }
    func png() throws -> Data {
        guard let view,let scene = view.scene,let camera = view.pointOfView else { throw SceneEditDocument.Failure.exportFailed }
        highlight(nil); defer { highlight(selected) }
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(),options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0,with: .init(width: 1920,height: 1440),antialiasingMode: .multisampling4X)
        #if os(iOS)
        guard let data = image.pngData() else { throw SceneEditDocument.Failure.exportFailed }
        #else
        guard let tiff = image.tiffRepresentation,let rep = NSBitmapImageRep(data: tiff),let data = rep.representation(using: .png,properties: [:]) else { throw SceneEditDocument.Failure.exportFailed }
        #endif
        return data
    }
}

#if os(iOS)
struct StudioViewport: UIViewRepresentable {
    let controller: StudioSceneController
    let document: SceneEditDocument
    let story: Int
    let cutaway: Bool
    let selected: UUID?
    let moving: Bool
    let reset: Int
    var showDimensions = false
    var rotating = false
    func makeCoordinator() -> Gestures { .init(controller) }
    func makeUIView(context: Context) -> SCNView {
        let view = StudioIOSSceneView(); view.studio = controller; view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30; view.autoenablesDefaultLighting = false
        controller.view = view
        let tap = UITapGestureRecognizer(target: context.coordinator,action: #selector(Gestures.tap(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator,action: #selector(Gestures.pan(_:)))
        pan.maximumNumberOfTouches = 1; pan.isEnabled = moving || rotating; context.coordinator.pan = pan
        view.addGestureRecognizer(tap); view.addGestureRecognizer(pan)
        view.accessibilityLabel = "Design Studio 3D scene"
        return view
    }
    func updateUIView(_ view: SCNView,context: Context) {
        context.coordinator.pan?.isEnabled = moving || rotating
        controller.configure(document,story: story,cutaway: cutaway,selected: selected,moving: moving,reset: reset,showDimensions: showDimensions,rotating: rotating)
    }
    @MainActor final class Gestures: NSObject {
        let controller: StudioSceneController
        weak var pan: UIPanGestureRecognizer?
        init(_ controller: StudioSceneController) { self.controller = controller }
        @objc func tap(_ gesture: UITapGestureRecognizer) { controller.tap(gesture.location(in: gesture.view)) }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began: controller.beginDrag(point)
            case .changed: controller.drag(point)
            case .ended: controller.endDrag()
            case .cancelled,.failed: controller.endDrag(cancelled: true)
            default: break
            }
        }
    }
}
private final class StudioIOSSceneView: SCNView {
    weak var studio: StudioSceneController?
    override func layoutSubviews() { super.layoutSubviews(); studio?.viewportDidLayout() }
}
#else
struct StudioViewport: NSViewRepresentable {
    let controller: StudioSceneController
    let document: SceneEditDocument
    let story: Int
    let cutaway: Bool
    let selected: UUID?
    let moving: Bool
    let reset: Int
    var showDimensions = false
    var rotating = false
    func makeNSView(context: Context) -> StudioMacSceneView {
        let view = StudioMacSceneView(); view.studio = controller
        view.antialiasingMode = .multisampling4X; view.preferredFramesPerSecond = 30
        controller.view = view; return view
    }
    func updateNSView(_ view: StudioMacSceneView,context: Context) {
        controller.configure(document,story: story,cutaway: cutaway,selected: selected,moving: moving,reset: reset,showDimensions: showDimensions,rotating: rotating)
    }
}
final class StudioMacSceneView: SCNView {
    weak var studio: StudioSceneController?
    override func layout() { super.layout(); studio?.viewportDidLayout() }
    private var start: CGPoint?
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow,from: nil); start = p
        if studio?.manipulating == true { studio?.beginDrag(p) } else { super.mouseDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        if studio?.manipulating == true { studio?.drag(convert(event.locationInWindow,from: nil)) } else { super.mouseDragged(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow,from: nil)
        if studio?.manipulating == true { studio?.endDrag() }
        else {
            super.mouseUp(with: event)
            if let start,hypot(p.x-start.x,p.y-start.y) < 5 { studio?.tap(p) }
        }
        start = nil
    }
}
#endif
