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
        return root
    }
}
