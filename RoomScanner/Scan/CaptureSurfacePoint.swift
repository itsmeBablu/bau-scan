#if os(iOS)
import ARKit
import UIKit

enum CaptureSurfacePoint {
    static func center(session: ARSession) -> TechnicalPoint3? {
        guard let frame = session.currentFrame else { return nil }
        return hit(frame: frame, session: session, image: CGPoint(x: 0.5, y: 0.5), scan: nil)?.point
    }

    static func tapped(_ location: CGPoint, size: CGSize, orientation: UIInterfaceOrientation,
                       session: ARSession, scan: ScanInput?) -> ScanSurfaceTarget? {
        guard let frame = session.currentFrame, size.width > 0, size.height > 0 else { return nil }
        let normalized = CGPoint(x: location.x / size.width, y: location.y / size.height)
        let image = normalized.applying(frame.displayTransform(for: orientation, viewportSize: size).inverted())
        return hit(frame: frame, session: session, image: image, scan: scan)
    }

    private static func hit(frame: ARFrame, session: ARSession, image: CGPoint, scan: ScanInput?) -> ScanSurfaceTarget? {
        guard frame.camera.trackingState == .normal, (0..<1).contains(image.x), (0..<1).contains(image.y) else { return nil }
        let camera = frame.camera, k = camera.intrinsics
        let local = SIMD4<Float>((Float(image.x * camera.imageResolution.width) - k[2][0]) / k[0][0],
                                 -(Float(image.y * camera.imageResolution.height) - k[2][1]) / k[1][1], -1, 0)
        let vector = camera.transform * local, translation = camera.transform.columns.3
        let direction = SIMD3(vector.x, vector.y, vector.z), origin = SIMD3(translation.x, translation.y, translation.z)
        var observed: SIMD3<Float>?
        if let depth = frame.sceneDepth ?? frame.smoothedSceneDepth,
           let meters = sample(depth.depthMap, at: image, as: Float32.self), meters.isFinite, meters > 0.1, meters < 8 {
            let confidence = depth.confidenceMap.flatMap { sample($0, at: image, as: UInt8.self) }
            if confidence != 0 { observed = origin + direction * meters }
        }
        if observed == nil {
            let query = ARRaycastQuery(origin: origin, direction: simd_normalize(direction), allowing: .existingPlaneGeometry, alignment: .any)
            if let hit = session.raycast(query).first {
                let translation = hit.worldTransform.columns.3
                let p = SIMD3(translation.x, translation.y, translation.z)
                if (0.1...8).contains(simd_distance(origin, p)) { observed = p }
            }
        }
        return ScanSurfaceTarget.resolve(origin: origin, direction: direction, observed: observed, scan: scan)
    }

    private static func sample<T>(_ buffer: CVPixelBuffer, at image: CGPoint, as type: T.Type) -> T? {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0, CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let x = min(width - 1, Int(image.x * CGFloat(width))), y = min(height - 1, Int(image.y * CGFloat(height)))
        return base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer) + x * MemoryLayout<T>.stride).load(as: type)
    }
}
#endif
