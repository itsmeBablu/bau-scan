#if os(iOS)
import Foundation
import RealityKit
import Observation

/// AR mode (iOS): spatial tracking, horizontal plane anchor for model,
/// scale 1:20 / 1:50 / 1:1, reset.
@Observable
@MainActor
final class ARPlacementController {
    private var session: SpatialTrackingSession?
    private(set) var anchor: AnchorEntity?

    func start(root: Entity, scale: ARScale) {
        let session = SpatialTrackingSession()
        let config = SpatialTrackingSession.Configuration(tracking: [.plane])
        Task { _ = await session.run(config) }
        self.session = session
        attach(root, scale: scale)
    }

    func stop() {
        guard let session else { return }
        self.session = nil
        Task { await session.stop() }
    }

    /// Detaches scene from AR anchor (returning to 3D / 2D modes).
    func detach(_ root: Entity) {
        guard let anchor else { return }
        root.removeFromParent()
        anchor.removeFromParent()
        self.anchor = nil
        root.scale = .one
        root.position = .zero
    }

    func reset(root: Entity, scale: ARScale) {
        detach(root)
        attach(root, scale: scale)
    }

    func apply(scale: ARScale, to root: Entity) {
        guard anchor != nil else { return }
        root.scale = SIMD3(repeating: Float(scale.rawValue))
    }

    private func attach(_ root: Entity, scale: ARScale) {
        // Table for tabletop AR, floor for 1:1 scale overlay.
        let classification: AnchoringComponent.Target.Classification = scale == .real ? .floor : .any
        let anchor = AnchorEntity(.plane(.horizontal, classification: classification, minimumBounds: SIMD2(0.3, 0.3)))
        let parent = root.parent
        root.removeFromParent()
        root.scale = SIMD3(repeating: Float(scale.rawValue))
        root.position = .zero
        anchor.addChild(root)
        parent?.addChild(anchor)
        self.anchor = anchor
    }
}
#endif
