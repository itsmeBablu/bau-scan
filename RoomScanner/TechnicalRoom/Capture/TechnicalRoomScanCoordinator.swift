#if os(iOS)
import ARKit
import AVFoundation
import Observation
import RealityKit
import simd
import UIKit

/// Dedicated technical capture. Never owns or runs a RoomCaptureSession.
/// Device validation pending.
@Observable
@MainActor
final class TechnicalRoomScanCoordinator: NSObject, @preconcurrency ARSessionDelegate {
    private(set) var captureID = UUID()
    var persistence: CapturePersistence?
    private let deltaWriter = TechnicalSessionDeltaWriter()
    private var persistenceTask: Task<Void,Never>?
    private var lastPersistence = -Double.infinity
    private var persistableSnapshot: TechnicalMeshSnapshot?
    var persistedDocument: TechnicalAnnotationDocument?
    func flushIncremental(force:Bool = false) {
        guard persistenceTask == nil,let persistence,let snapshot = persistableSnapshot,
              force || (lastTimestamp ?? 0)-lastPersistence >= 15 else { return }
        let activeIDs = Set(session.currentFrame?.anchors.compactMap { ($0 as? ARMeshAnchor)?.identifier } ?? [])
        let journal = journal,alignment = alignment,document = persistedDocument
        persistenceTask = Task { @MainActor [weak self] in
            defer { self?.persistenceTask = nil }
            do {
                try await persistence.prepare()
                guard let store = persistence.store else { throw CocoaError(.fileWriteUnknown) }
                let start = Date()
                let bytes = try await self?.deltaWriter.append(snapshot:snapshot,active:activeIDs,journal:journal,store:store,id:persistence.id) ?? 0
                if let document { try await persistence.write(TechnicalSessionState(document:document,alignment:alignment),key:"technical-state") }
                self?.lastPersistence = snapshot.timestamp
                persistence.recordSaved(bytes:bytes,milliseconds:Date().timeIntervalSince(start)*1000)
            } catch { persistence.recordFailure(error) }
        }
    }
    func flushAndWait() async { await persistenceTask?.value; flushIncremental(force:true); await persistenceTask?.value }

    let session = ARSession()
    private(set) var state = TechnicalCaptureState()
    private(set) var errorMessage: String?
    private(set) var frameCount = 0
    private(set) var meshAnchorCount = 0
    private(set) var lastTimestamp: TimeInterval?
    private(set) var alignment = TechnicalAlignmentSurvey()
    var referenceFrame: TechnicalTransform? { alignment.referenceFrame }
    private(set) var fps = 0.0
    private(set) var recoveryAvailable = false
    private(set) var recovering = false
    private(set) var worldMapData: Data?
    private(set) var frameHistory = TechnicalFrameHistory()
    private(set) var meshSnapshot: TechnicalMeshSnapshot?
    private(set) var liveMeshSnapshot: TechnicalMeshSnapshot?
    private var lastLiveMeshTimestamp = -Double.infinity
    private var meshTask: Task<Void,Never>?
    private var copyingSnapshot = false
    private var cameraWatchdog: Task<Void,Never>?
    private(set) var meshProcessingMs = 0.0
    private(set) var previewVertexCount = 0
    private(set) var processingSkipped = 0
    private(set) var photoCompleted = 0
    private(set) var depthSnapshot: TechnicalDepthSnapshot?
    private(set) var residentMemoryBytes: UInt64?
    private(set) var journal = TechnicalCaptureJournal()
    private(set) var evidence = TechnicalCaptureEvidence()
    private(set) var evidenceMessage = "Move slowly around equipment to capture different viewpoints."
    private var evidenceTask: Task<Void, Never>?
    private(set) var takingPhoto = false
    private var photoTask: Task<Void,Never>?
    private var collectingEvidence = true
    var aiEvidenceEnabled = false
    private var lastEvidenceTimestamp = -Double.infinity
    private var lastEvidencePose: [Double]?
    private(set) var healthWarnings: [String] = []
    private(set) var recoveryTrackingReady = false
    private var lastRecordedTimestamp = -Double.infinity
    private var firstTimestamp: Double?
    var hasLiveFrames: Bool { firstTimestamp != nil }
    private var previousTracking = ""
    private var requestingPermission = false
    private var restorationFailed = false
    private var previousTimestamp: TimeInterval?
    private var minimumFrameTimestamp = -Double.infinity
    private var active = false
    private var generation = 0
    private var sceneColors = TechnicalSceneColorCache()
    private var sceneMesh = TechnicalSceneMeshCache()
    private var lastColorSampleTimestamp = -Double.infinity
    private var pipeAnchors: [UUID: AnchorEntity] = [:]
    private var equipmentAnchors: [UUID: AnchorEntity] = [:]
    private var auxiliaryAnchor: AnchorEntity?

    func syncAnnotations(_ document: TechnicalAnnotationDocument, in viewport: ARView) {
        guard state.canAnnotate, let referenceFrame else { return }
        for anchor in pipeAnchors.values { anchor.removeFromParent() }; pipeAnchors.removeAll()
        for anchor in equipmentAnchors.values { anchor.removeFromParent() }; equipmentAnchors.removeAll()
        auxiliaryAnchor?.removeFromParent()
        for pipe in document.effectiveRoom.pipeRuns { showPipe(pipe, in: viewport) }
        for equipment in document.room.equipment { showEquipment(equipment, in: viewport) }
        let root = AnchorEntity(world: .zero)
        func world(_ point: TechnicalPoint3) -> SIMD3<Float> {
            let p = TechnicalReferenceFrame.inverseApply(referenceFrame, to: point)
            return SIMD3(Float(p.x), Float(p.y), Float(p.z))
        }
        func segment(_ start: TechnicalPoint3, _ end: TechnicalPoint3, width: Float, depth: Float, color: UIColor) {
            let a = world(start), b = world(end), length = simd_distance(a, b)
            guard length.isFinite, length > 0.0001 else { return }
            let entity = ModelEntity(mesh: .generateBox(width: width, height: length, depth: depth), materials: [SimpleMaterial(color: color, isMetallic: false)])
            entity.position = (a + b) / 2; entity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: (b - a) / length)
            root.addChild(entity)
        }
        for duct in document.ducts {
            let points = document.points(for: .duct(duct.id))
            for (a, b) in zip(points, points.dropFirst()) { segment(a, b, width: Float(duct.width.value), depth: Float(duct.height.value), color: .systemGray) }
        }
        for measurement in document.measurements { segment(measurement.start.value, measurement.end.value, width: 0.004, depth: 0.004, color: .darkGray) }
        for point in document.room.fittings.map({ $0.position.value }) + document.room.equipment.flatMap({ $0.ports.map { $0.position.value } }) {
            let marker = ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)])
            marker.position = world(point); root.addChild(marker)
        }
        viewport.scene.addAnchor(root); auxiliaryAnchor = root
        if !document.ducts.isEmpty || !document.measurements.isEmpty { lockReference() }
    }

    func showEquipment(_ equipment: TechnicalEquipment, in viewport: ARView) {
        guard state.canAnnotate, let referenceFrame else { return }
        lockReference()
        removeEquipment(id: equipment.id)
        let center = TechnicalReferenceFrame.inverseApply(referenceFrame, to: equipment.center.value)
        let size = equipment.size.value
        let yaw = equipment.rotation.value
        let roomX = TechnicalPoint3(x: equipment.center.value.x + cos(yaw), y: equipment.center.value.y,
                                    z: equipment.center.value.z - sin(yaw))
        let axis = TechnicalReferenceFrame.inverseApply(referenceFrame, to: roomX)
        let worldYaw = atan2(-(axis.z - center.z), axis.x - center.x)
        let model = ModelEntity(mesh: .generateBox(width: Float(size.x), height: Float(size.y), depth: Float(size.z)),
                                materials: [SimpleMaterial(color: .cyan.withAlphaComponent(0.5), isMetallic: false)])
        model.position = SIMD3(Float(center.x), Float(center.y), Float(center.z))
        model.orientation = simd_quatf(angle: Float(worldYaw), axis: SIMD3(0, 1, 0))
        let anchor = AnchorEntity(world: SIMD3<Float>.zero)
        anchor.addChild(model)
        viewport.scene.addAnchor(anchor)
        equipmentAnchors[equipment.id] = anchor
    }

    func removeEquipment(id: UUID) { equipmentAnchors.removeValue(forKey: id)?.removeFromParent() }

    func showPipe(_ pipe: TechnicalPipeRun, in viewport: ARView) {
        guard state.canAnnotate, let referenceFrame else { return }
        lockReference()
        removePipe(id: pipe.id)
        let anchor = AnchorEntity(world: SIMD3<Float>.zero)
        let points = pipe.centerline.value.map { TechnicalReferenceFrame.inverseApply(referenceFrame, to: $0) }
        let diameter = Float((pipe.outerDiameterMm.value + 2 * (pipe.insulationThicknessMm?.value ?? 0)) / 1000)
        guard diameter.isFinite, diameter > 0 else { return }
        for (first, last) in zip(points, points.dropFirst()) {
            let a = SIMD3<Float>(Float(first.x), Float(first.y), Float(first.z))
            let b = SIMD3<Float>(Float(last.x), Float(last.y), Float(last.z))
            let direction = b - a
            let length = simd_length(direction)
            guard length.isFinite, length > 0.0001 else { continue }
            let entity = ModelEntity(mesh: .generateBox(width: diameter, height: length, depth: diameter),
                materials: [UnlitMaterial(color: .yellow)])
            entity.position = (a + b) / 2
            entity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction / length)
            anchor.addChild(entity)
        }
        viewport.scene.addAnchor(anchor)
        pipeAnchors[pipe.id] = anchor
    }

    func removePipe(id: UUID) { pipeAnchors.removeValue(forKey: id)?.removeFromParent() }

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }

    func restoreSurvey(_ package: TechnicalRoomPackage) throws {
        guard !active, !requestingPermission, package.worldMapData != nil else {
            restorationFailed = true
            throw TechnicalAnnotationHistory.EditError.alignmentRequired
        }
        do { try package.validate() } catch { restorationFailed = true; errorMessage = error.localizedDescription; throw error }
        captureID = package.document.room.shellID
        alignment = package.alignment; journal = package.journal; evidence = package.evidence
        worldMapData = package.worldMapData; recoveryAvailable = true
        recovering = true; recoveryTrackingReady = false
    }

    func start() {
        guard !restorationFailed else { errorMessage = "This stored survey cannot start a fresh AR world. Use stored-property editing or restore a valid map."; return }
        guard !active, !requestingPermission else { return }
        // A stopped survey retains its coordinate frame and annotations. Never restart it in a fresh AR world.
        guard state.phase != .stopped else {
            errorMessage = "This survey is stopped. Open a new survey rather than replacing its reference frame."; return
        }
        requestingPermission = true
        generation += 1
        let requestGeneration = generation
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self, self.generation == requestGeneration else { return }
                self.requestingPermission = false
                guard granted else { self.errorMessage = "Camera permission required"; return }
                if let data = self.worldMapData { self.startRecovery(data) } else { self.run() }
            }
        }
    }

    func interrupt() {
        guard active,!state.cameraSuspended else { return }
        state.suspendCamera()
        invalidateAlignment()
        record(.interrupted, "Capture interrupted; checkpoint revalidation required")
        session.pause()
    }

    func resumeCameraAfterInterruption() {
        guard state.phase != .stopped else { return }
        // Also handle returning from Settings after camera access was initially denied.
        if !active { start(); return }
        guard active,collectingEvidence,state.cameraSuspended,
              let configuration = session.configuration?.copy() as? ARWorldTrackingConfiguration,
              state.resumeCamera() else { return }
        // Same session/configuration type, no reset flags: preserve the existing world and mesh.
        // An archived map is used only by explicit recovery, never reapplied on foregrounding.
        configuration.initialWorldMap = nil
        previousTimestamp = nil
        minimumFrameTimestamp = session.currentFrame?.timestamp ?? minimumFrameTimestamp
        lastRecordedTimestamp = -Double.infinity
        record(.started,"Camera resumed in existing AR session; alignment verification required")
        session.run(configuration,options: [])
    }

    @discardableResult func captureMeshSnapshot() async -> Bool {
        guard !copyingSnapshot else { return false }
        copyingSnapshot = true
        defer { copyingSnapshot = false }
        await meshTask?.value
        guard active, let frame = session.currentFrame else { return false }
        let requestGeneration = generation
        let verified = state.canAnnotate
        let copied = await Task.detached(priority:.userInitiated) {
            TechnicalRoomMeshCollector.snapshot(frame:frame,alignmentVerified:verified)
        }.value
        guard active,generation == requestGeneration else { return false }
        let snapshot = sceneMesh.merge(sceneColors.merge(copied))
        guard TechnicalSavedMeshGeometry.latest(in: [snapshot]) != nil else {
            errorMessage = "No 3D surfaces captured yet. Move around the room before saving."
            return false
        }
        guard journal.append(snapshot) else {
            errorMessage = "The mesh exceeds the current capture budget. Keep scanning a smaller area, then retry."
            return false
        }
        meshSnapshot = snapshot
        errorMessage = nil
        return true
    }

    func captureDepthSnapshot() {
        guard active, let frame = session.currentFrame else { return }
        depthSnapshot = TechnicalRoomFrameProcessor.depthSnapshot(frame: frame, alignmentVerified: state.canAnnotate)
        if let depthSnapshot { journal.append(depthSnapshot) }
        if depthSnapshot == nil { errorMessage = "Raw scene depth unavailable for this frame." }
    }

    func finishEvidenceCapture() async {
        collectingEvidence = false
        await evidenceTask?.value
        await photoTask?.value
        await meshTask?.value
    }

    func takeSurveyPhoto() {
        guard active,!takingPhoto,let frame = session.currentFrame,state.trackingNormal,
              let depth = TechnicalRoomFrameProcessor.depthSnapshot(frame: frame,alignmentVerified: state.canAnnotate) else {
            errorMessage = "Wait for camera tracking and LiDAR depth, then take the photo."; return
        }
        takingPhoto = true
        let requestGeneration = generation
        photoTask = Task { @MainActor [weak self] in
            let copied = await Task.detached(priority: .userInitiated) { TechnicalRoomKeyframeCollector.capture(frame: frame,depth: depth,maximumDimension: 1600) }.value
            guard let self else { return }
            defer { self.takingPhoto = false; self.photoTask = nil }
            guard self.generation == requestGeneration else { return }
            do {
                guard var photo = copied else { throw TechnicalCaptureJournal.JournalError.invalidEvidence }
                photo.userPhoto = true
                guard let persistence = self.persistence else { throw CocoaError(.fileWriteUnknown) }
                try await persistence.write(photo,key:"technical-photo-"+photo.id.uuidString,latest:false,media:true)
                try self.evidence.append(photo)
                self.photoCompleted += 1
                self.evidenceMessage = "Photo saved locally at this camera position. Save the survey to keep it."
            } catch { self.errorMessage = "Photo could not be retained. The photo budget may be full; save this survey before continuing." }
        }
    }

    private func collectEvidence(_ frame: ARFrame) {
        guard aiEvidenceEnabled, collectingEvidence, evidenceTask == nil, state.trackingNormal,
              frame.timestamp-lastEvidenceTimestamp >= 3, (residentMemoryBytes ?? 0) < 800 * 1_048_576 else { return }
        let matrix = frame.camera.transform
        let pose = (0..<4).flatMap { c in (0..<4).map { Double(matrix[c][$0]) } }
        if let previous = lastEvidencePose {
            let distance = sqrt((12...14).reduce(0.0) { $0 + pow(pose[$1]-previous[$1],2) })
            let direction = (8...10).reduce(0.0) { $0 + pose[$1]*previous[$1] }
            guard distance >= 0.2 || direction < cos(Double.pi/9) else { return }
        }
        lastEvidenceTimestamp = frame.timestamp
        guard let depth = TechnicalRoomFrameProcessor.depthSnapshot(frame: frame, alignmentVerified: state.canAnnotate) else {
            evidenceMessage = "Waiting for LiDAR depth."; return
        }
        let requestGeneration = generation
        evidenceTask = Task { @MainActor [weak self] in
            let keyframe = await Task.detached(priority: .utility) { TechnicalRoomKeyframeCollector.capture(frame: frame, depth: depth) }.value
            guard let self else { return }
            defer { self.evidenceTask = nil }
            guard self.generation == requestGeneration, let keyframe else { return }
            guard keyframe.confidentDepthFraction >= 0.2 else {
                self.evidenceMessage = "Low depth confidence. Try another angle on reflective surfaces."; return
            }
            do {
                if let persistence = self.persistence { try await persistence.write(keyframe,key:"keyframe-"+keyframe.id.uuidString,latest:false,media:true) }
                try self.evidence.append(keyframe)
                self.lastEvidencePose = pose
                self.evidenceMessage = "\(self.evidence.keyframes.count) colour/depth viewpoints retained. Include the sides and backs of visible equipment."
            } catch { self.evidenceMessage = "A capture image could not be retained. Try another viewpoint." }
        }
    }

    func saveRecoveryMap() {
        guard active, state.canAnnotate else { return }
        let requestGeneration = generation
        session.getCurrentWorldMap { [weak self] map, error in
            Task { @MainActor in
                guard let self, self.active, self.generation == requestGeneration else { return }
                guard self.state.canAnnotate else { self.errorMessage = "Alignment changed while saving the map. Verify the checkpoint and save again."; return }
                guard let map else { self.errorMessage = error?.localizedDescription ?? "World map unavailable"; return }
                do {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                    guard data.count <= 64 * 1_048_576 else { self.errorMessage = "Recovery map exceeds the 64 MiB retention limit."; return }
                    self.worldMapData = data
                    if let persistence = self.persistence { Task { try? await persistence.write(data,key:"world-map") } }
                    self.recoveryAvailable = true
                    self.record(.recoverySaved, "Secure world map archived")
                } catch { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func resume() {
        guard active, let worldMapData else { errorMessage = "Save a recovery map before an interruption."; return }
        startRecovery(worldMapData)
    }

    private func startRecovery(_ worldMapData: Data) {
        do {
            guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: worldMapData) else {
                errorMessage = "The recovery map cannot be restored."; return
            }
            generation += 1
            recovering = true
            recoveryTrackingReady = false
            invalidateAlignment()
            record(.recoveryStarted, "Restored world map; waiting for relocalisation and checkpoint")
            run(recoveryMap: map)
        } catch { errorMessage = error.localizedDescription }
    }

    func hit(at point: CGPoint, viewport: ARView) -> TechnicalPoint3? {
        guard active, state.trackingNormal,
              let query = viewport.makeRaycastQuery(from: point, allowing: .estimatedPlane, alignment: .any),
              let result = session.raycast(query).first else { return nil }
        let p = result.worldTransform.columns.3
        return .init(x: Double(p.x), y: Double(p.y), z: Double(p.z))
    }

    func surfaceHit(at point: CGPoint, viewport: ARView) -> TechnicalSurfaceHit? {
        guard state.canAnnotate, let referenceFrame,
              let query = viewport.makeRaycastQuery(from: point, allowing: .estimatedPlane, alignment: .any),
              let result = session.raycast(query).first,
              let camera = session.currentFrame?.camera else { return nil }
        let p = result.worldTransform.columns.3
        var n = SIMD3<Float>(result.worldTransform.columns.1.x, result.worldTransform.columns.1.y, result.worldTransform.columns.1.z)
        let cameraPosition = camera.transform.columns.3
        let towardCamera = SIMD3<Float>(cameraPosition.x - p.x, cameraPosition.y - p.y, cameraPosition.z - p.z)
        if simd_dot(n, towardCamera) < 0 { n = -n }
        let position = TechnicalReferenceFrame.apply(referenceFrame, to: .init(x: Double(p.x), y: Double(p.y), z: Double(p.z)))
        var rotation = referenceFrame
        rotation.translation = .init(x: 0, y: 0, z: 0)
        let normal = TechnicalReferenceFrame.apply(rotation, to: .init(x: Double(n.x), y: Double(n.y), z: Double(n.z)))
        return TechnicalSurfaceHit(position: .init(value: position, unit: "m", source: .measured, method: "estimatedPlaneOrMeshRaycast", accuracyMm: nil),
            normal: .init(value: normal, unit: "unitless", source: .estimated, method: "raycastSurfaceNormalTowardCamera", accuracyMm: nil))
    }

    private func run(recoveryMap: ARWorldMap? = nil) {
        cameraWatchdog?.cancel()
        let framesBeforeStart = frameCount
        cameraWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for:.seconds(8))
            guard !Task.isCancelled,let self,self.active,self.frameCount == framesBeforeStart else { return }
            self.errorMessage = "No camera frames received. Check camera permission, close other camera views, then reopen this scan."
        }
        guard ARWorldTrackingConfiguration.isSupported else { errorMessage = "World tracking unavailable"; return }
        // ARKit's delegate protocol predates actor isolation. Its callbacks are
        // deliberately delivered on the main queue for the MainActor conformance.
        session.delegate = self
        session.delegateQueue = .main
        let configuration = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { configuration.frameSemantics.insert(.sceneDepth) }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) { configuration.frameSemantics.insert(.smoothedSceneDepth) }
        // Plane detection flattens reconstructed surfaces around walls and can erase
        // shallow pipes and equipment. Keep the technical mesh unflattened.
        configuration.planeDetection = []
        configuration.initialWorldMap = recoveryMap
        active = true
        collectingEvidence = true
        lastEvidenceTimestamp = -Double.infinity
        lastEvidencePose = nil
        state.start()
        errorMessage = nil
        previousTimestamp = nil
        lastRecordedTimestamp = -Double.infinity
        firstTimestamp = nil
        record(.started, recoveryMap == nil ? "New AR capture" : "AR recovery capture")
        // Ignore frames queued before this run/recovery request.
        minimumFrameTimestamp = session.currentFrame?.timestamp ?? -Double.infinity
        if recoveryMap != nil { session.run(configuration, options: [.resetTracking, .removeExistingAnchors]) }
        else { session.run(configuration) }
    }

    func stop() {
        cameraWatchdog?.cancel(); cameraWatchdog = nil
        guard active || requestingPermission else { return }
        generation += 1
        requestingPermission = false
        record(.stopped, "Capture stopped; retained evidence remains in memory")
        active = false
        session.pause()
        state.stop()
        for anchor in pipeAnchors.values { anchor.removeFromParent() }
        pipeAnchors.removeAll()
        for anchor in equipmentAnchors.values { anchor.removeFromParent() }
        equipmentAnchors.removeAll()
        auxiliaryAnchor?.removeFromParent(); auxiliaryAnchor = nil
    }

    func setReference(origin: TechnicalPoint3, xCorner: TechnicalPoint3) throws {
        try alignment.define(origin: origin, xCorner: xCorner)
        invalidateAlignment()
        record(.referenceDefined, "Two floor corners defined the reference frame")
        state.tracking(normal: session.currentFrame?.camera.trackingState == .normal)
    }

    func verifyCheckpoint(observed: TechnicalPoint3, expected: TechnicalPoint3, thresholdMm: Double) {
        guard active, state.trackingNormal else { errorMessage = "Normal tracking is required before checking alignment."; return }
        guard !recovering || recoveryTrackingReady else { errorMessage = "Wait for world-map relocalisation before checking the point."; return }
        do {
            let checkpoint = try alignment.check(observed: observed, expected: expected, thresholdMm: thresholdMm, timestamp: lastTimestamp ?? 0)
            state.verify(residualMm: checkpoint.residualMm, thresholdMm: checkpoint.thresholdMm)
            record(.checkpoint, "Residual \(checkpoint.residualMm) mm; tolerance \(thresholdMm) mm; accepted: \(checkpoint.accepted)")
            errorMessage = nil
            if state.canAnnotate { recovering = false }
            updateAnnotationVisibility()
        } catch { errorMessage = error.localizedDescription }
    }

    func lockReference() {
        if !alignment.referenceLocked {
            alignment.lockReference()
            record(.referenceLocked, "First annotation locked the reference frame")
        }
    }

    private func invalidateAlignment() {
        state.interrupt()
        recoveryTrackingReady = false
        updateAnnotationVisibility()
    }

    private func updateAnnotationVisibility() {
        for anchor in pipeAnchors.values { anchor.isEnabled = state.canAnnotate }
        for anchor in equipmentAnchors.values { anchor.isEnabled = state.canAnnotate }
        auxiliaryAnchor?.isEnabled = state.canAnnotate
    }

    private func record(_ kind: TechnicalCaptureJournal.Event.Kind, _ message: String) {
        journal.append(.init(timestamp: lastTimestamp ?? 0, kind: kind, message: message, alignmentVerified: state.canAnnotate,
                             referenceFrame: referenceFrame, checkpoint: kind == .checkpoint ? alignment.checkpoints.last : nil))
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard active, frame.timestamp > minimumFrameTimestamp else { return }
        frameCount += 1
        if firstTimestamp == nil { firstTimestamp = frame.timestamp }
        if let previousTimestamp, frame.timestamp > previousTimestamp {
            let instantaneous = 1 / (frame.timestamp - previousTimestamp)
            fps = fps == 0 ? instantaneous : fps * 0.9 + instantaneous * 0.1
        }
        previousTimestamp = frame.timestamp
        lastTimestamp = frame.timestamp
        meshAnchorCount = frame.anchors.compactMap { $0 as? ARMeshAnchor }.count
        state.tracking(normal: frame.camera.trackingState == .normal)
        if recovering {
            recoveryTrackingReady = frame.camera.trackingState == .normal &&
                (frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending)
        }
        updateAnnotationVisibility()
        let tracking = String(describing: frame.camera.trackingState)
        if tracking != previousTracking {
            previousTracking = tracking
            record(.trackingChanged, tracking)
        }
        processMesh(frame)
        if frame.timestamp - lastRecordedTimestamp >= 1 {
            lastRecordedTimestamp = frame.timestamp
            residentMemoryBytes = TechnicalRoomFrameProcessor.residentMemoryBytes()
            let matrix = frame.camera.transform
            let intrinsics = frame.camera.intrinsics
            let record = TechnicalFrameRecord(timestamp: frame.timestamp,
                cameraTransform: (0..<4).flatMap { column in (0..<4).map { Double(matrix[column][$0]) } },
                intrinsics: (0..<3).flatMap { column in (0..<3).map { Double(intrinsics[column][$0]) } },
                imageWidth: Int(frame.camera.imageResolution.width), imageHeight: Int(frame.camera.imageResolution.height),
                tracking: String(describing: frame.camera.trackingState),
                hasSceneDepth: frame.sceneDepth != nil, hasSmoothedSceneDepth: frame.smoothedSceneDepth != nil,
                alignmentVerified: state.canAnnotate)
            frameHistory.append(record)
            journal.append(record)
            collectEvidence(frame)
            healthWarnings = TechnicalCaptureHealth.warnings(for: .init(trackingNormal: state.trackingNormal, fps: fps,
                residentMemoryBytes: residentMemoryBytes, ambientIntensity: frame.lightEstimate.map { Double($0.ambientIntensity) },
                depthCoverage: TechnicalRoomFrameProcessor.depthCoverage(frame: frame), elapsedSeconds: frame.timestamp - (firstTimestamp ?? frame.timestamp)))
        }
    }

    private func processMesh(_ frame: ARFrame) {
        let mode = ScanPerformance(rawValue:UserDefaults.standard.string(forKey:ScanPerformance.preferenceKey) ?? "") ?? .balanced
        guard !copyingSnapshot,state.trackingNormal,frame.timestamp-lastLiveMeshTimestamp >= mode.previewInterval,
              (residentMemoryBytes ?? 0) < 800*1_048_576 else { return }
        guard meshTask == nil else { processingSkipped += 1; return }
        lastLiveMeshTimestamp = frame.timestamp
        let colorsDue = frame.timestamp-lastColorSampleTimestamp >= 3
        if colorsDue { lastColorSampleTimestamp = frame.timestamp }
        let requestGeneration = generation
        let verified = state.canAnnotate
        // Value caches move into one bounded worker, then return with their results.
        let colors = sceneColors, meshes = sceneMesh
        meshTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority:.utility) {
                let start = Date()
                let preview = TechnicalRoomMeshCollector.snapshot(frame:frame,alignmentVerified:false,
                    maximumVertices:mode.previewVertices,includeColors:false,maximumTriangles:mode.previewTriangles)
                var colors = colors,meshes = meshes
                let persisted = colorsDue ? meshes.merge(colors.merge(TechnicalRoomMeshCollector.snapshot(frame:frame,alignmentVerified:verified))) : nil
                return (preview,colors,meshes,Date().timeIntervalSince(start)*1000,persisted)
            }.value
            guard let self else { return }
            defer { self.meshTask = nil }
            guard self.generation == requestGeneration,self.active else { return }
            self.liveMeshSnapshot = result.0
            if let snapshot = result.4 { self.persistableSnapshot = snapshot }
            self.flushIncremental()
            self.previewVertexCount = result.0.patches.reduce(0){ $0+$1.vertices.count }
            self.sceneColors = result.1; self.sceneMesh = result.2
            self.meshProcessingMs = result.3
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        guard active else { return }; flushIncremental(force:true); invalidateAlignment(); record(.interrupted, "AR session interruption")
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        guard active else { return }; invalidateAlignment(); record(.interrupted, "Interruption ended; restore map and verify checkpoint")
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard active else { return }
        errorMessage = error.localizedDescription
        invalidateAlignment()
        record(.failure, error.localizedDescription)
    }
}
#endif
