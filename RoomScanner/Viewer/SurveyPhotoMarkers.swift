import Foundation
import RealityKit
import simd

enum SurveyPhotoMarkers {
    static let prefix = "survey-photo:"
    static func entity(_ photo: SurveyPhoto) -> Entity {
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
        let material = UnlitMaterial(color:.yellow)
        let body = ModelEntity(mesh:.generateBox(size:0.09),materials:[material])
        body.name = root.name
        body.components.set(InputTargetComponent()); body.generateCollisionShapes(recursive:false)
        root.addChild(body)
        let arrow = ModelEntity(mesh:.generateBox(width:0.018,height:0.018,depth:0.3),materials:[material])
        arrow.position.z = -0.18; root.addChild(arrow)
        let label = ModelEntity(mesh:.generateText(String(photo.number),extrusionDepth:0.001,font:.systemFont(ofSize:0.09),
                                                   containerFrame:.zero,alignment:.center,lineBreakMode:.byClipping),materials:[material])
        label.position.y = 0.1; label.components.set(BillboardComponent()); root.addChild(label)
        return root
    }
}
