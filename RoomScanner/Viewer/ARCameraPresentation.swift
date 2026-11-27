#if os(iOS)
import RealityKit
import UIKit

enum ARCameraRunPolicy {
    static func shouldRun(visible:Bool,attached:Bool,width:CGFloat,height:CGFloat,applicationActive:Bool) -> Bool {
        visible && attached && width > 0 && height > 0 && applicationActive
    }
}

@MainActor enum ARCameraPresentation {
    static func configure(_ view:ARView,manualMesh:Bool = false) {
        if view.cameraMode != .ar { view.cameraMode = .ar }
        view.environment.background = .cameraFeed()
        // The technical scanner owns its wireframe. An automatic reconstruction
        // layer must not replace or occlude the actual camera background.
        if manualMesh { view.environment.sceneUnderstanding.options = [] }
        view.renderOptions.formUnion([.disableMotionBlur,.disableCameraGrain])
    }
}
#endif
