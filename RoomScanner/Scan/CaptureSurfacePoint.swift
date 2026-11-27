#if os(iOS)
import ARKit

enum CaptureSurfacePoint {
    static func center(session:ARSession) -> TechnicalPoint3? {
        guard let frame = session.currentFrame,frame.camera.trackingState == .normal else { return nil }
        if let depth = frame.smoothedSceneDepth ?? frame.sceneDepth {
            let map = depth.depthMap
            CVPixelBufferLockBaseAddress(map,.readOnly)
            defer { CVPixelBufferUnlockBaseAddress(map,.readOnly) }
            let w = CVPixelBufferGetWidth(map),h = CVPixelBufferGetHeight(map)
            if let base = CVPixelBufferGetBaseAddress(map),w > 0,h > 0 {
                let value = base.advanced(by:(h/2)*CVPixelBufferGetBytesPerRow(map)+(w/2)*4).load(as:Float.self)
                if value.isFinite,value > 0.1,value < 8 {
                    let size = frame.camera.imageResolution,k = frame.camera.intrinsics
                    let u = Float(size.width/2),v = Float(size.height/2)
                    let p = frame.camera.transform * SIMD4<Float>((u-k[2][0])*value/k[0][0],-(v-k[2][1])*value/k[1][1],-value,1)
                    return .init(x:Double(p.x),y:Double(p.y),z:Double(p.z))
                }
            }
        }
        let m = frame.camera.transform
        let query = ARRaycastQuery(origin:SIMD3(m[3].x,m[3].y,m[3].z),direction:-SIMD3(m[2].x,m[2].y,m[2].z),allowing:.existingPlaneGeometry,alignment:.any)
        guard let hit = session.raycast(query).first else { return nil }
        let p = hit.worldTransform.columns.3
        return .init(x:Double(p.x),y:Double(p.y),z:Double(p.z))
    }
}
#endif
