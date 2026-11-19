import SwiftUI
import RealityKit
#if os(iOS)
import ARKit
import AVFoundation
#endif

/// Visualiseur `RealityView` commun iOS / macOS (D13).
/// - 3D: virtual camera with framework orbit controls.
/// - 2D: flattened walls, locked zenith camera, drag/pinch pan-zoom.
/// - AR (iOS): camera-backed ARView, model anchored on a horizontal plane.
struct ViewerView: View {
    let house: House
    @Bindable var state: ViewerState

    /// Root of the scene, rebuilt when visual options change.
    @State private var sceneRoot = Entity()
    @State private var camera = PerspectiveCamera()
    @State private var twoDPan: CGSize = .zero
    @State private var twoDZoom: CGFloat = 1

    var body: some View {
        #if os(iOS)
        if state.mode == .ar {
            CameraARView(house: house, state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            virtualView
        }
        #else
        virtualView
        #endif
    }

    private var virtualView: some View {
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
            content.camera = .virtual
        }
        .realityViewCameraControls(state.mode == .threeD ? .orbit : .none)
        .gesture(state.mode == .twoD ? twoDGestures : nil)
        .onChange(of: state.mode) { _, _ in modeChanged() }
        .onChange(of: state.showDimensions) { _, _ in rebuildScene() }
        .onChange(of: state.showObjects) { _, _ in rebuildScene() }
        .onChange(of: house) { _, _ in rebuildScene(); resetView() }
        .onChange(of: state.resetToken) { _, _ in resetView() }
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
    }

    private func modeChanged() {
        rebuildScene()
        frameCamera()
    }

    private func resetView() {
        twoDPan = .zero; twoDZoom = 1
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

#if os(iOS)
/// Uses ARView's camera feed and a world-tracking session for floor/table placement.
private struct CameraARView: View {
    let house: House
    @Bindable var state: ViewerState
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var requested = false
    @State private var cameraStatus = "Starting AR camera…"
    @State private var cameraFailed = false

    var body: some View {
        Group {
            if !ARWorldTrackingConfiguration.isSupported {
                ContentUnavailableView("AR is unavailable", systemImage: "arkit", description: Text("Use a supported iPhone or iPad to view your scan in AR."))
            } else if authorized {
                NativeARView(house: house, dimensions: state.showDimensions, objects: state.showObjects,
                             scale: state.arScale, resetToken: state.resetToken, active: scenePhase == .active,
                             status: $cameraStatus, failed: $cameraFailed)
                    .overlay(alignment: .top) {
                        VStack(spacing: 8) {
                            Text(cameraStatus).font(.callout)
                            if cameraFailed {
                                Button("Restart AR camera") { cameraFailed = false; state.resetToken += 1 }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding()
                    }
            } else if requested {
                ContentUnavailableView {
                    Label("Camera access needed", systemImage: "camera")
                } description: {
                    Text("Allow camera access in Settings to view your scan in AR.")
                } actions: {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } else {
                ProgressView("Opening camera…")
            }
        }
        .task {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                authorized = await AVCaptureDevice.requestAccess(for: .video)
            }
            requested = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
        }
    }
}

private struct NativeARView: UIViewRepresentable {
    let house: House
    let dimensions: Bool
    let objects: Bool
    let scale: ARScale
    let resetToken: Int
    let active: Bool
    @Binding var status: String
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CameraBackedARView {
        let view = CameraBackedARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.environment.background = .cameraFeed()
        view.session.delegate = context.coordinator
        let coordinator = context.coordinator
        view.onWindowChanged = { [weak coordinator, weak view] in
            guard let view else { return }
            coordinator?.updateSession(view)
        }
        configure(view, coordinator: coordinator)
        return view
    }

    func updateUIView(_ view: CameraBackedARView, context: Context) {
        configure(view, coordinator: context.coordinator)
    }

    private func configure(_ view: CameraBackedARView, coordinator: Coordinator) {
        coordinator.report = { message, failure in
            status = message; failed = failure
        }
        coordinator.update(view, house: house, dimensions: dimensions, objects: objects,
                           scale: scale, resetToken: resetToken, active: active)
    }

    static func dismantleUIView(_ view: CameraBackedARView, coordinator: Coordinator) {
        view.onWindowChanged = nil
        coordinator.stop()
        view.session.delegate = nil
        view.session.pause()
        view.scene.anchors.removeAll()
    }

    @MainActor final class Coordinator: NSObject, ARSessionDelegate {
        private var previousHouse: House?
        private var dimensions = false
        private var objects = false
        private var scale: ARScale?
        private var resetToken: Int?
        private var running = false
        private var active = false
        private var needsReset = true
        private var hasFrame = false
        private var failedSession = false
        private weak var anchor: AnchorEntity?
        private var lastStatus = ""
        var report: ((String, Bool) -> Void)?
        var watchdog: Task<Void, Never>?

        func stop() {
            active = false
            running = false
            watchdog?.cancel()
            report = nil
        }

        func updateSession(_ view: ARView) {
            guard !failedSession else { return }
            guard active, view.window != nil else {
                if running { view.session.pause(); running = false }
                watchdog?.cancel()
                return
            }
            if !running || needsReset {
                let configuration = ARWorldTrackingConfiguration()
                configuration.planeDetection = [.horizontal]
                configuration.environmentTexturing = .automatic
                view.environment.background = .cameraFeed()
                view.session.run(configuration, options: needsReset ? [.resetTracking, .removeExistingAnchors] : [])
                needsReset = false
                running = true
                hasFrame = false
                lastStatus = ""
                watchdog?.cancel()
                watchdog = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled, let self, self.running, !self.hasFrame else { return }
                    self.report?("The AR camera has not delivered any frames. Restart AR, or close another app using the camera.", true)
                }
            }
        }

        func update(_ view: ARView, house: House, dimensions: Bool, objects: Bool, scale: ARScale, resetToken: Int, active: Bool) {
            let reset = self.resetToken != resetToken
            self.active = active
            if reset { needsReset = true; failedSession = false }
            updateSession(view)
            guard previousHouse != house || self.dimensions != dimensions || self.objects != objects || self.scale != scale || reset else { return }
            var builder = PlanSceneBuilder()
            builder.options.showDimensions = dimensions
            builder.options.showObjects = objects
            let model = builder.makeScene(for: house)
            let bounds = house.bounds
            model.position = bounds.isEmpty ? .zero : SIMD3(Float(-bounds.center.x), 0, Float(bounds.center.y))
            let container = Entity()
            container.addChild(model)
            container.scale = SIMD3(repeating: Float(scale.rawValue))
            let classification: AnchoringComponent.Target.Classification = scale == .real ? .floor : .any
            let anchor = AnchorEntity(.plane(.horizontal, classification: classification, minimumBounds: SIMD2(0.3, 0.3)))
            anchor.addChild(container)
            view.scene.anchors.removeAll()
            view.scene.addAnchor(anchor)
            self.anchor = anchor
            previousHouse = house; self.dimensions = dimensions; self.objects = objects
            self.scale = scale; self.resetToken = resetToken
        }

        nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                self.hasFrame = true
                let message = self.anchor?.isAnchored == true ? "Model placed. Move around to inspect it." : "Camera is live. Move slowly to find a floor or table."
                if self.lastStatus != message {
                    self.lastStatus = message
                    self.report?(message, false)
                }
            }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.running = false
                self?.failedSession = true
                self?.watchdog?.cancel()
                self?.report?("AR camera failed: \(message)", true)
            }
        }

        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor [weak self] in
                self?.report?("AR camera was interrupted. Restart AR to resume.", true)
            }
        }
    }
}

/// Starts camera tracking only after UIKit attaches the view to a visible window.
private final class CameraBackedARView: ARView {
    var onWindowChanged: (() -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChanged?()
    }
}
#endif
