import CoreGraphics
import Foundation
import simd

/// One texel per vertex, shared by the offline viewer and portable mesh exports.
enum TechnicalMeshAppearance {
    /// Each triangle samples one texel. Sharing UVs across unrelated atlas texels would
    /// interpolate through other faces' colours and produce false stripes.
    static func faceAtlas(_ mesh: TechnicalSavedMeshGeometry) -> (image: CGImage, uv: [SIMD2<Float>])? {
        var colors: [TechnicalPoint3?] = []
        for i in stride(from: 0, to: mesh.triangleIndices.count, by: 3) {
            let samples = (0..<3).compactMap { mesh.colors[Int(mesh.triangleIndices[i + $0])] }
            if samples.count == 3 {
                colors.append(.init(x: samples.reduce(0) { $0 + $1.x } / 3,
                                    y: samples.reduce(0) { $0 + $1.y } / 3,
                                    z: samples.reduce(0) { $0 + $1.z } / 3))
            } else { colors.append(nil) }
        }
        guard let atlas = atlas(colors) else { return nil }
        return (atlas.image, atlas.uv.flatMap { [$0, $0, $0] })
    }
    static func atlas(_ colors: [TechnicalPoint3?]) -> (image: CGImage, uv: [SIMD2<Float>])? {
        guard !colors.isEmpty, colors.contains(where: { $0 != nil }) else { return nil }
        let width = min(512, colors.count), height = (colors.count + width - 1) / width
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var uv: [SIMD2<Float>] = []
        for (i, color) in colors.enumerated() {
            let c = color ?? .init(x: 0.72, y: 0.72, z: 0.72)
            bytes[i * 4] = UInt8((c.x * 255).rounded())
            bytes[i * 4 + 1] = UInt8((c.y * 255).rounded())
            bytes[i * 4 + 2] = UInt8((c.z * 255).rounded())
            uv.append(SIMD2((Float(i % width) + 0.5) / Float(width), 1 - (Float(i / width) + 0.5) / Float(height)))
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return (image, uv)
    }
}
