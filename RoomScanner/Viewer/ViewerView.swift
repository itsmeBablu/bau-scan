import SwiftUI
import RealityKit
import simd
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
    var radiators: [HouseRadiator] = []
    var photoPackageURL: URL? = nil
    @State private var showNotes = true
    @State private var noteError:String?
    @State private var notes:[ARNote] = []
    @State private var selectedNote:ARNote?
    @State private var noteRoot:URL?
    @State private var markerRoot = Entity()
    @State private var photos: [SurveyPhotoImage] = []
    @State private var showPhotos = true
    @State private var selectedPhoto: SurveyPhotoImage?
    @State private var photoError: String?
    @State private var pendingPhoto: SurveyPhotoImage?
    @AppStorage("measurementUnit") private var appUnit: MeasurementUnit = .both
    @Environment(\.projectPreferences) private var projectPreferences
    @Environment(\.locale) private var locale
    private var unit:MeasurementUnit { ProjectPreferenceResolution.unit(projectPreferences,appDefault:appUnit) }
    @State private var measureStart: SIMD3<Float>?
    @State private var lastMeasurementText: String?
    @State private var measureRoot = Entity()

    /// Root of the scene, rebuilt when visual options change.
    @State private var sceneRoot = Entity()
    @State private var camera = PerspectiveCamera()
    @State private var planNavigation = ViewerPlanNavigation()

    var body: some View {
        Group {
        #if os(iOS)
        if state.mode == .ar {
            CameraARView(house:house,state:state,radiators:radiators,notes:showNotes ? notes : [],photos:showPhotos ? photos.map(\.photo) : [],onNote:selectNote,onPhoto:selectPhoto)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            virtualView
        }
        #else
        virtualView
        #endif
        }
        .task(id:photoPackageURL) {
            guard let url = photoPackageURL else { return }
            noteRoot = ScanVoiceNoteLibrary.root
            do { notes = try await Task.detached { try ScanVoiceNoteLibrary.registeredNotes(packageURL:url,house:house) }.value; noteError = nil }
            catch { notes = []; noteError = AppLanguage.text("Could not open voice notes")+": "+error.localizedDescription }
            do { photos = try await Task.detached { try SurveyPhotoStore.images(from:url,house:house) }.value }
            catch { photos = []; photoError = "Survey photos could not be loaded: "+error.localizedDescription }
        }
        .overlay(alignment:.topLeading) {
            if !photos.isEmpty || !notes.isEmpty || photoError != nil || noteError != nil {
            VStack {
                if !photos.isEmpty { Toggle("Photos",isOn:$showPhotos).toggleStyle(.button) }
                if !notes.isEmpty { Toggle("Voice notes",isOn:$showNotes).toggleStyle(.button) }
                if let noteError { Text(noteError).font(.caption).foregroundStyle(DS.ColorToken.error.color) }
                if let photoError { Text(photoError).font(.caption).foregroundStyle(DS.ColorToken.error.color) }
            }.padding().dsMaterial(in:Capsule())
            }
        }
        .overlay(alignment: .top) {
            if state.isMeasuring || lastMeasurementText != nil {
                HStack(spacing: 10) {
                    if let last = lastMeasurementText {
                        Text("Measured: \(last)").bold()
                        Text("measure.copied").font(.caption).foregroundStyle(.secondary)
                        Button("Clear") {
                            lastMeasurementText = nil
                            measureStart = nil
                            measureRoot.children.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if measureStart != nil {
                        Text("Click second point").font(.callout)
                    } else {
                        Text("measure.clickTwoPoints").font(.callout)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .dsMaterial(in:Capsule())
                .padding(.top, 10)
            }
        }
        .sheet(item:$selectedNote) { note in VoiceNotePlayerSheet(note:note,root:noteRoot ?? ScanVoiceNoteLibrary.root) { saved in
            if let i = notes.firstIndex(where:{ $0.id == saved.id }) { var value = saved; value.displayPosition = notes[i].displayPosition; notes[i] = value }
        } }
        .sheet(item:$selectedPhoto) { photo in
            SurveyPhotoGallery(photos:photos,initial:photo.id) { flyToPhoto($0) }
        }
    }

    private var virtualView: some View {
        interactiveScene
            .onChange(of: state.mode) { _, _ in modeChanged() }
            .onChange(of: state.showDimensions) { _, _ in rebuildScene() }
            .onChange(of: state.showObjects) { _, _ in rebuildScene() }
            .onChange(of: house) { _, _ in rebuildScene(); resetView() }
            .onChange(of: radiators) { _, _ in rebuildScene() }
            .onChange(of: showNotes) { _,_ in updateMarkers() }
            .onChange(of: notes) { _, _ in updateMarkers() }
            .onChange(of: photos) { _, _ in updateMarkers() }
            .onChange(of: showPhotos) { _, _ in updateMarkers() }
    }
    private var sceneContent: some View {
        RealityView { content in
            rebuildScene()
            content.add(sceneRoot)
            content.add(measureRoot)
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
    }
    private var sceneTap: some Gesture {
        SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            if state.isMeasuring {
                guard let point = value.unproject(\.location,to: .scene) else { return }
                handleSceneTap(entity: value.entity,worldPosition: point)
            } else {
                handleSceneTap(entity: value.entity,worldPosition: nil)
            }
        }
    }
    private var interactiveScene: some View {
        sceneContent.simultaneousGesture(sceneTap).simultaneousGesture(
            TapGesture().targetedToEntity(where:.has(AnnotationTarget.self)).onEnded { value in
                guard !state.isMeasuring else { return }; handleSceneTap(entity:value.entity,worldPosition:nil)
            }
        )
        .onChange(of: state.isMeasuring) { _, active in
            if !active {
                measureStart = nil
                lastMeasurementText = nil
                measureRoot.children.removeAll()
            }
        }
        .onChange(of: state.resetToken) { _, _ in resetView() }
        .background(AppTheme.darkCharcoal)
    }

    private func handleSceneTap(entity: Entity,worldPosition: SIMD3<Float>?) {
            if state.isMeasuring {
                guard let worldPos = worldPosition else { return }
                if let start = measureStart {
                    let dist = Double(simd_distance(start, worldPos))
                    let text = MeasurementFormat.length(dist, unit: unit, locale: locale)
                    lastMeasurementText = text
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    #endif
                    measureRoot.children.removeAll()
                    measureRoot.addChild(makeLineEntity(from: start, to: worldPos))
                    measureStart = nil
                } else {
                    measureStart = worldPos
                    measureRoot.children.removeAll()
                    let marker = ModelEntity(mesh: .generateSphere(radius: 0.04), materials: [UnlitMaterial(color: .yellow)])
                    marker.position = worldPos
                    measureRoot.addChild(marker)
                }
                return
            }
            if entity.name.hasPrefix("scan-note:"),let id = UUID(uuidString:String(entity.name.dropFirst(10))) {
                selectedNote = notes.first { $0.id == id }; return
            }
            guard entity.name.hasPrefix(SurveyPhotoMarkers.prefix),
                  let id = UUID(uuidString:String(entity.name.dropFirst(SurveyPhotoMarkers.prefix.count))) else { return }
            selectedPhoto = photos.first { $0.id == id }
    }

    private func makeLineEntity(from p1: SIMD3<Float>, to p2: SIMD3<Float>) -> Entity {
        let container = Entity()
        let dist = simd_distance(p1, p2)
        guard dist > 0.001 else { return container }
        let material = UnlitMaterial(color: .yellow)
        let lineMesh = MeshResource.generateBox(width: 0.015, height: 0.015, depth: dist)
        let lineEntity = ModelEntity(mesh: lineMesh, materials: [material])
        lineEntity.position = (p1 + p2) / 2
        let dir = p2 - p1
        let up: SIMD3<Float> = abs(dir.x) < 0.001 && abs(dir.z) < 0.001 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        lineEntity.look(at: p2, from: lineEntity.position, upVector: up, relativeTo: nil)
        container.addChild(lineEntity)

        let sphereMesh = MeshResource.generateSphere(radius: 0.03)
        let sphere1 = ModelEntity(mesh: sphereMesh, materials: [material])
        sphere1.position = p1
        let sphere2 = ModelEntity(mesh: sphereMesh, materials: [material])
        sphere2.position = p2
        container.addChild(sphere1)
        container.addChild(sphere2)
        return container
    }

    // MARK: - Scene

    private func rebuildScene() {
        var builder = PlanSceneBuilder()
        builder.options.locale = locale
        builder.radiators = radiators
        builder.options.showDimensions = state.showDimensions
        builder.options.showObjects = state.showObjects
        builder.options.flattenWalls = state.mode == .twoD
        let fresh = builder.makeScene(for: house)
        // Replaces children while preserving root entity (already attached to content).
        for child in sceneRoot.children.map({ $0 }) { child.removeFromParent() }
        for child in fresh.children.map({ $0 }) { sceneRoot.addChild(child) }
        updateMarkers()
        // Recenters house at origin: RealityView orbit controls rotate
        // around world origin, and AR anchor places model by its center.
        let b = house.bounds
        sceneRoot.position = b.isEmpty ? .zero : SIMD3(Float(-b.center.x), 0, Float(b.center.y))
    }

    private func selectNote(_ id:UUID) { selectedNote = notes.first { $0.id == id } }
    private func selectPhoto(_ id:UUID) { selectedPhoto = photos.first { $0.id == id } }
    private func updateMarkers() {
        markerRoot.children.removeAll()
        if showPhotos { for photo in photos.suffix(200) { markerRoot.addChild(SurveyPhotoMarkers.entity(photo.photo)) } }
        for note in notes.suffix(256) where showNotes {
            guard let p = note.viewingPosition else { continue }
            markerRoot.addChild(AnnotationIcon.noteEntity(note,position:p))
        }
        sceneRoot.addChild(markerRoot)
    }

    private func flyToPhoto(_ photo: SurveyPhotoImage) {
        if state.mode != .threeD {
            pendingPhoto = photo
            state.mode = .threeD
            return
        }
        applyPhotoCamera(photo)
    }

    private func applyPhotoCamera(_ photo: SurveyPhotoImage) {
        let m = photo.photo.viewingPose
        guard m.count == 16 else { return }
        camera.transform = Transform(matrix:simd_float4x4(columns:(
            SIMD4(Float(m[0]),Float(m[1]),Float(m[2]),0),
            SIMD4(Float(m[4]),Float(m[5]),Float(m[6]),0),
            SIMD4(Float(m[8]),Float(m[9]),Float(m[10]),0),
            SIMD4(Float(m[12])+sceneRoot.position.x,Float(m[13]),Float(m[14])+sceneRoot.position.z,1))))
    }

    private func modeChanged() {
        rebuildScene()
        frameCamera()
        if let photo = pendingPhoto {
            pendingPhoto = nil
            applyPhotoCamera(photo)
        }
    }

    private func resetView() {
        planNavigation = ViewerPlanNavigation()
        frameCamera()
    }

    /// Frames house (centered at origin): 3/4 view in 3D, top-down zenith in 2D.
    private func frameCamera() {
        let b = house.bounds
        let radius = Float(max(b.width, b.height, 2))
        let target = SIMD3<Float>(0, 0.5, 0)
        switch state.mode {
        case .twoD:
            let height = radius * 1.15 / planNavigation.zoom.float
            let pan = SIMD3<Float>(Float(-planNavigation.pan.width) * 0.002 * height, 0, Float(-planNavigation.pan.height) * 0.002 * height)
            camera.look(at: target + pan, from: target + pan + SIMD3(0, height, 0.0001), relativeTo: nil)
        default:
            camera.look(at: target, from: target + SIMD3(radius * 0.9, radius * 0.8, radius * 1.1), relativeTo: nil)
        }
    }

    // MARK: - Gestes 2D

    private var twoDGestures: some Gesture {
        DragGesture()
            .onChanged { v in planNavigation.drag(v.translation); frameCamera() }
            .onEnded { v in planNavigation.endDrag(v.translation); frameCamera() }
            .simultaneously(with: MagnifyGesture()
                .onChanged { v in planNavigation.magnify(v.magnification); frameCamera() }
                .onEnded { v in planNavigation.endMagnify(v.magnification); frameCamera() })
    }
}

private extension CGFloat { var float: Float { Float(self) } }

#if os(iOS)
/// Uses ARView's camera feed and a world-tracking session for floor/table placement.
private struct CameraARView: View {
    let house: House
    @Bindable var state: ViewerState
    let radiators: [HouseRadiator]
    let notes:[ARNote]
    let photos:[SurveyPhoto]
    var onNote:(UUID)->Void
    var onPhoto:(UUID)->Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var requested = false
    @State private var visible = false
    @State private var cameraStatus = "Starting AR camera…"
    @State private var cameraFailed = false

    var body: some View {
        Group {
            if !ARWorldTrackingConfiguration.isSupported {
                ContentUnavailableView("AR is unavailable", systemImage: "arkit", description: Text("Use a supported iPhone or iPad to view your scan in AR."))
            } else if authorized {
                NativeARView(house: house, radiators: radiators, notes:notes,photos:photos,onNote:onNote,onPhoto:onPhoto,dimensions: state.showDimensions, objects: state.showObjects,
                             scale: state.arScale, resetToken: state.resetToken, active: scenePhase == .active && visible,
                             status: $cameraStatus, failed: $cameraFailed)
                    .id(state.resetToken)
                    .overlay(alignment: .top) {
                        VStack(spacing: 8) {
                            Text(cameraStatus).font(.callout)
                            if cameraFailed {
                                Button("Restart AR camera") { cameraFailed = false; state.resetToken += 1 }
                                    .dsProminentControl()
                            }
                        }
                            .padding(12)
                            .dsMaterial(in:RoundedRectangle(cornerRadius: DS.Radius.panel))
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
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onChange(of: state.resetToken) { _,_ in cameraStatus = "Starting AR camera…"; cameraFailed = false }
        .task {
            authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
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
    let radiators: [HouseRadiator]
    let notes:[ARNote]
    let photos:[SurveyPhoto]
    var onNote:(UUID)->Void
    var onPhoto:(UUID)->Void
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
        view.addGestureRecognizer(UITapGestureRecognizer(target:coordinator,action:#selector(Coordinator.tapped(_:))))
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
        coordinator.onNote = onNote; coordinator.onPhoto = onPhoto
        coordinator.report = { message, failure in
            status = message; failed = failure
        }
        coordinator.update(view, house: house, radiators: radiators, dimensions: dimensions, objects: objects,
                           scale: scale, resetToken: resetToken, active: active)
        coordinator.updateAnnotations(notes:notes,photos:photos)
    }

    static func dismantleUIView(_ view: CameraBackedARView, coordinator: Coordinator) {
        view.onWindowChanged = nil
        coordinator.stop()
        view.session.delegate = nil
        view.session.pause()
        view.scene.anchors.removeAll()
    }

    @MainActor final class Coordinator: NSObject, ARSessionDelegate {
        private weak var displayedModel:Entity?
        private let annotationRoot = Entity()
        private var previousNotes:[ARNote] = []
        private var previousPhotos:[SurveyPhoto] = []
        var onNote:((UUID)->Void)?
        var onPhoto:((UUID)->Void)?
        func updateAnnotations(notes:[ARNote],photos:[SurveyPhoto]) {
            guard let model = displayedModel else { return }
            guard notes != previousNotes || photos != previousPhotos || annotationRoot.parent !== model else { return }
            annotationRoot.children.removeAll()
            for note in notes.suffix(256) {
                guard let p = note.viewingPosition else { continue }
                annotationRoot.addChild(AnnotationIcon.noteEntity(note,position:p))
            }
            for photo in photos.suffix(200) { annotationRoot.addChild(SurveyPhotoMarkers.entity(photo)) }
            model.addChild(annotationRoot); previousNotes = notes; previousPhotos = photos
        }
        @objc func tapped(_ gesture:UITapGestureRecognizer) {
            guard let view = cameraView else { return }
            for hit in view.hitTest(gesture.location(in:view),query:.all,mask:.all) {
            var entity:Entity? = hit.entity
            while let current = entity {
                if current.name.hasPrefix("scan-note:"),let id = UUID(uuidString:String(current.name.dropFirst(10))) { onNote?(id); return }
                if current.name.hasPrefix(SurveyPhotoMarkers.prefix),let id = UUID(uuidString:String(current.name.dropFirst(SurveyPhotoMarkers.prefix.count))) { onPhoto?(id); return }
                entity = current.parent
            }
            }
        }
        private var previousHouse: House?
        private var previousRadiators: [HouseRadiator] = []
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
        private weak var cameraView: ARView?
        private var lastStatus = ""
        var report: ((String, Bool) -> Void)?
        var watchdog: Task<Void, Never>?

        func stop() {
            active = false
            running = false
            watchdog?.cancel()
            report = nil; onNote = nil; onPhoto = nil
        }

        func updateSession(_ view: ARView) {
            cameraView = view
            guard !failedSession else { return }
            guard active, view.window != nil,view.bounds.width > 0,view.bounds.height > 0 else {
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

        func update(_ view: ARView, house: House, radiators: [HouseRadiator], dimensions: Bool, objects: Bool, scale: ARScale, resetToken: Int, active: Bool) {
            let reset = self.resetToken != resetToken
            self.active = active
            if reset { needsReset = true; failedSession = false }
            updateSession(view)
            guard previousHouse != house || previousRadiators != radiators || self.dimensions != dimensions || self.objects != objects || self.scale != scale || reset else { return }
            var builder = PlanSceneBuilder()
            builder.radiators = radiators
            builder.options.showDimensions = dimensions
            builder.options.showObjects = objects
            let model = builder.makeScene(for: house)
            displayedModel = model
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
            previousRadiators = radiators
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
                self?.running = false; self?.watchdog?.cancel()
                self?.report?("AR camera interrupted. Waiting to resume…",false)
            }
        }
        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            Task { @MainActor [weak self] in
                guard let self,let view = self.cameraView else { return }
                self.failedSession = false; self.needsReset = true; self.running = false
                self.updateSession(view)
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
    override func layoutSubviews() {
        super.layoutSubviews()
        onWindowChanged?()
    }
}
#endif
