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
    var moving = false
    var onSelect: ((UUID?) -> Void)?
    var onMove: ((UUID,TechnicalPoint3) -> Bool)?
    func configure(_ document: SceneEditDocument,story: Int,cutaway: Bool,selected: UUID?,moving: Bool,reset: Int,showDimensions: Bool = false) {
        guard let view else { return }
        self.moving = moving; view.allowsCameraControl = !moving
        let rendering = document.renderingSnapshot
        if view.scene == nil || previousRendering != rendering || previousStory != story || previousCutaway != cutaway || previousDimensions != showDimensions || (showDimensions && previousDimensionSelection != selected) {
            let scene = StudioSceneBuilder.scene(document,story: story,cutaway: cutaway,showDimensions: showDimensions,dimensionSelection: selected)
            scene.rootNode.addChildNode(camera); view.scene = scene; view.pointOfView = camera
            if previous == nil || previousStory != story { frame(document,story: story) }
            previousRendering = rendering; previousStory = story; previousCutaway = cutaway
            previousDimensions = showDimensions; previousDimensionSelection = selected
        }
        previous = document
        if resetToken != reset { resetToken = reset; frame(document,story: story) }
        self.selected = selected; highlight(selected)
        applyCameraAppearance(document)
        viewportDidLayout()
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
        guard let view else { return nil }
        for hit in view.hitTest(point,options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            var node: SCNNode? = hit.node
            while let current = node {
                if current.name?.hasPrefix("object:") == true { return current }
                node = current.parent
            }
        }
        return nil
    }
    func tap(_ point: CGPoint) {
        let node = objectNode(at: point)
        let id = node?.name.flatMap { UUID(uuidString: String($0.dropFirst(7))) }
        selected = id; highlight(id); onSelect?(id)
    }
    func beginDrag(_ point: CGPoint) {
        guard moving,let node = objectNode(at: point) else { return }
        tap(point); dragNode = node; dragOrigin = node.simdPosition
        dragStart = plane(point,y: dragOrigin.y)
    }
    func drag(_ point: CGPoint) {
        guard let node = dragNode,let start = dragStart,let hit = plane(point,y: dragOrigin.y) else { return }
        let position = dragOrigin+hit-start
        guard abs(position.x) <= 1000,abs(position.z) <= 1000 else { return }
        node.simdPosition = position
    }
    func endDrag(cancelled: Bool = false) {
        defer { dragNode = nil; dragStart = nil }
        guard let node = dragNode,let id = node.name.flatMap({ UUID(uuidString: String($0.dropFirst(7))) }) else { return }
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
        view?.scene?.rootNode.enumerateChildNodes { node,_ in
            guard let geometry = node.geometry else { return }
            var ancestor: SCNNode? = node
            var active = false
            while let current = ancestor {
                if current.name == id.map({ "object:"+$0.uuidString }) { active = true; break }
                ancestor = current.parent
            }
            for material in geometry.materials { material.emission.contents = active ? platformColor(CGColor(red: 0.12,green: 0.23,blue: 0.30,alpha: 1)) : platformColor(CGColor(gray: 0,alpha: 1)) }
        }
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
    func makeCoordinator() -> Gestures { .init(controller) }
    func makeUIView(context: Context) -> SCNView {
        let view = StudioIOSSceneView(); view.studio = controller; view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30; view.autoenablesDefaultLighting = false
        controller.view = view
        let tap = UITapGestureRecognizer(target: context.coordinator,action: #selector(Gestures.tap(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator,action: #selector(Gestures.pan(_:)))
        pan.maximumNumberOfTouches = 1; pan.isEnabled = moving; context.coordinator.pan = pan
        view.addGestureRecognizer(tap); view.addGestureRecognizer(pan)
        view.accessibilityLabel = "Design Studio 3D scene"
        return view
    }
    func updateUIView(_ view: SCNView,context: Context) {
        context.coordinator.pan?.isEnabled = moving
        controller.configure(document,story: story,cutaway: cutaway,selected: selected,moving: moving,reset: reset,showDimensions: showDimensions)
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
    func makeNSView(context: Context) -> StudioMacSceneView {
        let view = StudioMacSceneView(); view.studio = controller
        view.antialiasingMode = .multisampling4X; view.preferredFramesPerSecond = 30
        controller.view = view; return view
    }
    func updateNSView(_ view: StudioMacSceneView,context: Context) {
        controller.configure(document,story: story,cutaway: cutaway,selected: selected,moving: moving,reset: reset,showDimensions: showDimensions)
    }
}
final class StudioMacSceneView: SCNView {
    weak var studio: StudioSceneController?
    override func layout() { super.layout(); studio?.viewportDidLayout() }
    private var start: CGPoint?
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow,from: nil); start = p
        if studio?.moving == true { studio?.beginDrag(p) } else { super.mouseDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        if studio?.moving == true { studio?.drag(convert(event.locationInWindow,from: nil)) } else { super.mouseDragged(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow,from: nil)
        if studio?.moving == true { studio?.endDrag() }
        else {
            super.mouseUp(with: event)
            if let start,hypot(p.x-start.x,p.y-start.y) < 5 { studio?.tap(p) }
        }
        start = nil
    }
}
#endif
