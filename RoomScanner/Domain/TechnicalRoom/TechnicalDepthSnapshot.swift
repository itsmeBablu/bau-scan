import Foundation

struct TechnicalDepthSnapshot: Codable, Equatable {
    let timestamp: Double
    let width: Int
    let height: Int
    let imageWidth: Int
    let imageHeight: Int
    let cameraTransform: [Double]
    let intrinsics: [Double]
    /// Row-major metres. Invalid depth stays nil.
    let depthMetres: [Float?]
    let confidence: [UInt8]?
    let alignmentVerified: Bool
}

enum TechnicalDepthProjection {
    /// ARKit image pixels use X right/Y down; camera space is X right/Y up/-Z forward.
    static func cameraPoint(pixelX: Double, pixelY: Double, depthMetres: Double,
                            fx: Double, fy: Double, cx: Double, cy: Double) -> TechnicalPoint3? {
        guard [pixelX, pixelY, depthMetres, fx, fy, cx, cy].allSatisfy({ $0.isFinite }),
              depthMetres > 0, fx > 0, fy > 0 else { return nil }
        return .init(x: (pixelX - cx) * depthMetres / fx,
                     y: -(pixelY - cy) * depthMetres / fy, z: -depthMetres)
    }
}
