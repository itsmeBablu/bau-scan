import Foundation
import RealityKit
import simd

enum SurveyPhotoMarkers {
    static let prefix = "survey-photo:"
    @MainActor static func entity(_ photo: SurveyPhoto) -> Entity {
        let root = Entity()
        root.name = prefix+photo.id.uuidString
        let m = photo.viewingPose
        guard m.count == 16 else { return root }
        let matrix = simd_float4x4(columns:(
            SIMD4(Float(m[0]),Float(m[1]),Float(m[2]),Float(m[3])),
            SIMD4(Float(m[4]),Float(m[5]),Float(m[6]),Float(m[7])),
            SIMD4(Float(m[8]),Float(m[9]),Float(m[10]),Float(m[11])),
            SIMD4(Float(m[12]),Float(m[13]),Float(m[14]),Float(m[15]))))
        root.transform = Transform(matrix:matrix)
        let body = AnnotationIcon.entity(symbol:"camera.fill",name:root.name)
        root.addChild(body)
        // Pose is measured; the legacy photo format has no lens calibration,
        // so this is a camera-direction guide, not a measured viewing volume.
        let corners:[TechnicalPoint3] = [.init(x:-0.25,y:-0.17,z:-0.45),.init(x:0.25,y:-0.17,z:-0.45),.init(x:0.25,y:0.17,z:-0.45),.init(x:-0.25,y:0.17,z:-0.45)]
        for i in corners.indices {
            if let ray = AnnotationIcon.line(from:.init(x:0,y:0,z:0),to:corners[i]) { ray.name = "photo-frustum-ray"; root.addChild(ray) }
            if let edge = AnnotationIcon.line(from:corners[i],to:corners[(i+1)%4]) { edge.name = "photo-frustum-edge"; root.addChild(edge) }
        }
        return root
    }
}
