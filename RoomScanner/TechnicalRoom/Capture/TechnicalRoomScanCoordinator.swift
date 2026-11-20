#if os(iOS)
import ARKit
import AVFoundation
import Observation
import RealityKit

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

    func hit(at point: CGPoint, viewport: ARView) -> TechnicalPoint3? {
        guard active, state.trackingNormal,
              let query = viewport.makeRaycastQuery(from: point, allowing: .estimatedPlane, alignment: .any),
              let result = session.raycast(query).first else { return nil }
        let p = result.worldTransform.columns.3
        return .init(x: Double(p.x), y: Double(p.y), z: Double(p.z))
    }

    private func run() {
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
        active = true
        state.start()
        session.run(configuration)
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
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard active else { return }
        frameCount += 1
        if let previousTimestamp, frame.timestamp > previousTimestamp { fps = 1 / (frame.timestamp - previousTimestamp) }
        previousTimestamp = frame.timestamp
        lastTimestamp = frame.timestamp
        meshAnchorCount = frame.anchors.compactMap { $0 as? ARMeshAnchor }.count
        state.tracking(normal: frame.camera.trackingState == .normal)
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
