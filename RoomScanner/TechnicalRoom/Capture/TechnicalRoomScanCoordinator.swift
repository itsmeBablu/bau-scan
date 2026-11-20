#if os(iOS)
import ARKit
import AVFoundation
import Observation
import RealityKit
import simd

/// Dedicated technical capture. Never owns or runs a RoomCaptureSession.
/// Device validation pending.
@Observable
@MainActor
final class TechnicalRoomScanCoordinator: NSObject, ARSessionDelegate {
    let session = ARSession()
    private(set) var state = TechnicalCaptureState()
    private(set) var errorMessage: String?
    private(set) var frameCount = 0
    private(set) var meshAnchorCount = 0
    private(set) var lastTimestamp: TimeInterval?
    private(set) var referenceFrame: TechnicalTransform?
    private(set) var fps = 0.0
    private(set) var recoveryAvailable = false
    private(set) var recovering = false
    private(set) var worldMapData: Data?
    private(set) var frameHistory = TechnicalFrameHistory()
    private(set) var meshSnapshot: TechnicalMeshSnapshot?
    private(set) var depthSnapshot: TechnicalDepthSnapshot?
    private(set) var residentMemoryBytes: UInt64?
    private var lastRecordedTimestamp = -Double.infinity
    private var worldMap: ARWorldMap?
    private var previousTimestamp: TimeInterval?
    private var active = false
    private var generation = 0

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }

    func start() {
        guard !active else { return }
        generation += 1
        let requestGeneration = generation
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self, self.generation == requestGeneration else { return }
                guard granted else { self.errorMessage = "Camera permission required"; return }
                self.run()
            }
        }
    }

    func interrupt() { guard active else { return }; state.interrupt(); session.pause() }

    func captureMeshSnapshot() {
        guard active, let frame = session.currentFrame else { return }
        meshSnapshot = TechnicalRoomMeshCollector.snapshot(frame: frame, alignmentVerified: state.canAnnotate)
    }

    func captureDepthSnapshot() {
        guard active, let frame = session.currentFrame else { return }
        depthSnapshot = TechnicalRoomFrameProcessor.depthSnapshot(frame: frame, alignmentVerified: state.canAnnotate)
        if depthSnapshot == nil { errorMessage = "Raw scene depth unavailable for this frame." }
    }

    func saveRecoveryMap() {
        guard active, state.trackingNormal else { return }
        let requestGeneration = generation
        session.getCurrentWorldMap { [weak self] map, error in
            Task { @MainActor in
                guard let self, self.active, self.generation == requestGeneration else { return }
                guard let map else { self.errorMessage = error?.localizedDescription ?? "World map unavailable"; return }
                do {
                    self.worldMapData = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                    self.worldMap = map
                    self.recoveryAvailable = true
                } catch { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func resume() {
        guard active, let worldMap else { errorMessage = "Save a recovery map before an interruption."; return }
        recovering = true
        run(recoveryMap: worldMap)
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
        guard ARWorldTrackingConfiguration.isSupported else { errorMessage = "World tracking unavailable"; return }
        let configuration = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { configuration.frameSemantics.insert(.sceneDepth) }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) { configuration.frameSemantics.insert(.smoothedSceneDepth) }
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.initialWorldMap = recoveryMap
        active = true
        state.start()
        previousTimestamp = nil
        if recoveryMap != nil { session.run(configuration, options: [.resetTracking, .removeExistingAnchors]) }
        else { session.run(configuration) }
    }

    func stop() {
        generation += 1
        active = false
        session.pause()
        state.stop()
    }

    func setReference(origin: TechnicalPoint3, xCorner: TechnicalPoint3) throws {
        referenceFrame = try TechnicalReferenceFrame.transform(origin: origin, xCorner: xCorner)
        state.interrupt()
        state.tracking(normal: session.currentFrame?.camera.trackingState == .normal)
    }

    func verifyCheckpoint(observed: TechnicalPoint3, expected: TechnicalPoint3, thresholdMm: Double) {
        guard let referenceFrame else { return }
        let transformed = TechnicalReferenceFrame.apply(referenceFrame, to: observed)
        state.verify(residualMm: transformed.distance(to: expected) * 1000, thresholdMm: thresholdMm)
        if state.canAnnotate { recovering = false }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard active else { return }
        frameCount += 1
        if let previousTimestamp, frame.timestamp > previousTimestamp { fps = 1 / (frame.timestamp - previousTimestamp) }
        previousTimestamp = frame.timestamp
        lastTimestamp = frame.timestamp
        meshAnchorCount = frame.anchors.compactMap { $0 as? ARMeshAnchor }.count
        state.tracking(normal: frame.camera.trackingState == .normal)
        if frame.timestamp - lastRecordedTimestamp >= 1 {
            lastRecordedTimestamp = frame.timestamp
            residentMemoryBytes = TechnicalRoomFrameProcessor.residentMemoryBytes()
            let matrix = frame.camera.transform
            let intrinsics = frame.camera.intrinsics
            frameHistory.append(TechnicalFrameRecord(timestamp: frame.timestamp,
                cameraTransform: (0..<4).flatMap { column in (0..<4).map { Double(matrix[column][$0]) } },
                intrinsics: (0..<3).flatMap { column in (0..<3).map { Double(intrinsics[column][$0]) } },
                imageWidth: Int(frame.camera.imageResolution.width), imageHeight: Int(frame.camera.imageResolution.height),
                tracking: String(describing: frame.camera.trackingState),
                hasSceneDepth: frame.sceneDepth != nil, hasSmoothedSceneDepth: frame.smoothedSceneDepth != nil,
                alignmentVerified: state.canAnnotate))
        }
    }

    func sessionWasInterrupted(_ session: ARSession) { guard active else { return }; state.interrupt() }
    func sessionInterruptionEnded(_ session: ARSession) { guard active else { return }; state.interrupt() }
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard active else { return }
        errorMessage = error.localizedDescription
        state.interrupt()
    }
}
#endif
