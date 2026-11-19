import SwiftUI
import RealityKit

/// Visualiseur `RealityView` commun iOS / macOS (D13).
/// - 3D: virtual camera with framework orbit controls.
/// - 2D: flattened walls, locked zenith camera, drag/pinch pan-zoom.
/// - AR (iOS): `.spatialTracking` camera, model anchored on horizontal plane.
struct ViewerView: View {
    let house: House
    @Bindable var state: ViewerState

    /// Root of the scene, rebuilt when visual options change.
    @State private var sceneRoot = Entity()
    @State private var camera = PerspectiveCamera()
    @State private var twoDPan: CGSize = .zero
    @State private var twoDZoom: CGFloat = 1
    #if os(iOS)
    @State private var ar = ARPlacementController()
    #endif

    var body: some View {
        RealityView { content in
            rebuildScene()
            content.add(sceneRoot)
            content.add(camera)
            frameCamera()
            #if os(iOS)
            content.camera = .virtual
            #else
            content.camera = .virtual
            #endif
        } update: { content in
            #if os(iOS)
            content.camera = state.mode == .ar ? .spatialTracking : .virtual
            #endif
        }
        .realityViewCameraControls(state.mode == .threeD ? .orbit : .none)
        .gesture(state.mode == .twoD ? twoDGestures : nil)
        .onChange(of: state.mode) { _, _ in modeChanged() }
        .onChange(of: state.showDimensions) { _, _ in rebuildScene() }
        .onChange(of: state.showObjects) { _, _ in rebuildScene() }
        .onChange(of: house) { _, _ in rebuildScene(); resetView() }
        .onChange(of: state.resetToken) { _, _ in resetView() }
        #if os(iOS)
        .onChange(of: state.arScale) { _, _ in ar.apply(scale: state.arScale, to: sceneRoot) }
        #endif
        .background(AppTheme.darkCharcoal)
    }

    // MARK: - Scene

    private func rebuildScene() {
        var builder = PlanSceneBuilder()
        builder.options.showDimensions = state.showDimensions
        builder.options.showObjects = state.showObjects
        builder.options.flattenWalls = state.mode == .twoD
        let fresh = builder.makeScene(for: house)
        // Replaces children while preserving root entity (already attached to content).
        for child in sceneRoot.children.map({ $0 }) { child.removeFromParent() }
        for child in fresh.children.map({ $0 }) { sceneRoot.addChild(child) }
        // Recenters house at origin: RealityView orbit controls rotate
        // around world origin, and AR anchor places model by its center.
        let b = house.bounds
        sceneRoot.position = b.isEmpty ? .zero : SIMD3(Float(-b.center.x), 0, Float(b.center.y))
        #if os(iOS)
        if state.mode == .ar { ar.apply(scale: state.arScale, to: sceneRoot) } else { ar.detach(sceneRoot) }
        #endif
    }

    private func modeChanged() {
        #if os(iOS)
        if state.mode == .ar {
            rebuildScene()
            ar.start(root: sceneRoot, scale: state.arScale)
            return
        } else {
            ar.stop()
        }
        #endif
        rebuildScene()
        frameCamera()
    }

    private func resetView() {
        twoDPan = .zero; twoDZoom = 1
        #if os(iOS)
        if state.mode == .ar { ar.reset(root: sceneRoot, scale: state.arScale); return }
        #endif
        frameCamera()
    }

    /// Frames house (centered at origin): 3/4 view in 3D, top-down zenith in 2D.
    private func frameCamera() {
        let b = house.bounds
        let radius = Float(max(b.width, b.height, 2))
        let target = SIMD3<Float>(0, 0.5, 0)
        switch state.mode {
        case .twoD:
            let height = radius * 1.15 / CGFloat(twoDZoom).float
            let pan = SIMD3<Float>(Float(-twoDPan.width) * 0.002 * height, 0, Float(-twoDPan.height) * 0.002 * height)
            camera.look(at: target + pan, from: target + pan + SIMD3(0, height, 0.0001), relativeTo: nil)
        default:
            camera.look(at: target, from: target + SIMD3(radius * 0.9, radius * 0.8, radius * 1.1), relativeTo: nil)
        }
    }

    // MARK: - Gestes 2D

    private var twoDGestures: some Gesture {
        DragGesture()
            .onChanged { v in twoDPan = v.translation; frameCamera() }
            .onEnded { _ in }
            .simultaneously(with: MagnifyGesture()
                .onChanged { v in twoDZoom = min(max(v.magnification, 0.4), 6); frameCamera() })
    }
}

private extension CGFloat { var float: Float { Float(self) } }
