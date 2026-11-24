#if os(iOS)
import ARKit
import CoreImage
import UIKit

enum TechnicalRoomKeyframeCollector {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// Called on a worker; AR buffers are retained only for this bounded image encoding.
    static func capture(frame: ARFrame, depth: TechnicalDepthSnapshot, maximumDimension: CGFloat = 1280) -> TechnicalCaptureKeyframe? {
        guard let encoded = jpeg(frame:frame,maximumDimension:maximumDimension) else { return nil }
        return .init(id: UUID(),jpegData:encoded.data,jpegWidth:encoded.width,jpegHeight:encoded.height,depth:depth)
    }
    static func jpeg(frame: ARFrame, maximumDimension: CGFloat = 1600) -> (data:Data,width:Int,height:Int)? {
        let source = CIImage(cvPixelBuffer: frame.capturedImage)
        let scale = min(1,maximumDimension/max(source.extent.width,source.extent.height))
        let image = source.transformed(by: CGAffineTransform(scaleX: scale,y: scale))
        guard let cg = context.createCGImage(image, from: image.extent),
              let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85), jpeg.count <= 4 * 1_048_576 else { return nil }
        return (jpeg,cg.width,cg.height)
    }
}
#endif
