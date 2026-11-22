#if os(iOS)
import ARKit

/// Copies one bounded snapshot on request, never retains Metal buffer pointers.
enum TechnicalRoomMeshCollector {
    static func snapshot(frame: ARFrame, alignmentVerified: Bool, maximumVertices: Int = 250_000,includeColors: Bool = true) -> TechnicalMeshSnapshot {
        let image = frame.capturedImage
        let depth = includeColors ? (frame.sceneDepth ?? frame.smoothedSceneDepth)?.depthMap : nil
        if includeColors { CVPixelBufferLockBaseAddress(image, .readOnly) }
        if let depth { CVPixelBufferLockBaseAddress(depth, .readOnly) }
        defer {
            if includeColors { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
            if let depth { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        }
        let cameraInverse = frame.camera.transform.inverse
        let k = frame.camera.intrinsics
        let width = CVPixelBufferGetWidth(image), height = CVPixelBufferGetHeight(image)
        let pixelFormat = CVPixelBufferGetPixelFormatType(image)
        let supported = pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let matrix = CVBufferCopyAttachment(image, kCVImageBufferYCbCrMatrixKey, nil) as? String
        let kr = matrix == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) ? 0.2126 : 0.299
        let kb = matrix == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) ? 0.0722 : 0.114
        func sample(_ world: SIMD4<Float>) -> TechnicalPoint3? {
            // Only colour points visible in this frame, checked against LiDAR depth.
            guard supported, let depth,
                  let yPlane = CVPixelBufferGetBaseAddressOfPlane(image, 0),
                  let uvPlane = CVPixelBufferGetBaseAddressOfPlane(image, 1),
                  let depthBase = CVPixelBufferGetBaseAddress(depth) else { return nil }
            let p = cameraInverse * world
            let distance = -p.z
            guard distance > 0.1 else { return nil }
            let u = k[0][0] * p.x / distance + k[2][0]
            let v = k[2][1] - k[1][1] * p.y / distance
            guard u >= 0, v >= 0, u < Float(width), v < Float(height) else { return nil }
            let dw = CVPixelBufferGetWidth(depth), dh = CVPixelBufferGetHeight(depth)
            let dx = min(dw - 1, Int(u * Float(dw) / Float(width)))
            let dy = min(dh - 1, Int(v * Float(dh) / Float(height)))
            let measured = depthBase.advanced(by: dy * CVPixelBufferGetBytesPerRow(depth) + dx * 4).load(as: Float.self)
            guard measured.isFinite, measured > 0, abs(measured - distance) < 0.08 else { return nil }
            let x = Int(u), y = Int(v)
            let rawY = Double(yPlane.load(fromByteOffset: y * CVPixelBufferGetBytesPerRowOfPlane(image, 0) + x, as: UInt8.self))
            let uvOffset = (y / 2) * CVPixelBufferGetBytesPerRowOfPlane(image, 1) + (x / 2) * 2
            let video = pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            let luma = video ? (rawY - 16) / 219 : rawY / 255
            let cb = (Double(uvPlane.load(fromByteOffset: uvOffset, as: UInt8.self)) - 128) / (video ? 224 : 255)
            let cr = (Double(uvPlane.load(fromByteOffset: uvOffset + 1, as: UInt8.self)) - 128) / (video ? 224 : 255)
            let r = luma + 2 * (1 - kr) * cr
            let b = luma + 2 * (1 - kb) * cb
            let g = (luma - kr * r - kb * b) / (1 - kr - kb)
            return .init(x: min(1, max(0, r)), y: min(1, max(0, g)), z: min(1, max(0, b)))
        }
        var patches: [TechnicalMeshSnapshot.Patch] = []
        var count = 0
        var truncated = false
        for anchor in frame.anchors.compactMap({ $0 as? ARMeshAnchor }) {
            let geometry = anchor.geometry
            guard count + geometry.vertices.count <= maximumVertices else { truncated = true; continue }
            let source = geometry.vertices
            var vertices: [TechnicalPoint3] = []
            var colors: [TechnicalPoint3?] = []
            vertices.reserveCapacity(source.count)
            for index in 0..<source.count {
                let address = source.buffer.contents().advanced(by: source.offset + index * source.stride)
                let x = address.load(as: Float.self)
                let y = address.advanced(by: 4).load(as: Float.self)
                let z = address.advanced(by: 8).load(as: Float.self)
                let world = anchor.transform * SIMD4<Float>(x, y, z, 1)
                vertices.append(.init(x: Double(world.x), y: Double(world.y), z: Double(world.z)))
                if includeColors { colors.append(sample(world)) }
            }
            let faces = geometry.faces
            guard faces.indexCountPerPrimitive == 3 else { continue }
            var indices: [UInt32] = []
            indices.reserveCapacity(faces.count * 3)
            for index in 0..<(faces.count * 3) {
                let address = faces.buffer.contents().advanced(by: index * faces.bytesPerIndex)
                let value: UInt32
                if faces.bytesPerIndex == 2 { value = UInt32(address.load(as: UInt16.self)) }
                else if faces.bytesPerIndex == 4 { value = address.load(as: UInt32.self) }
                else { continue }
                indices.append(value)
            }
            guard indices.allSatisfy({ Int($0) < vertices.count }) else { continue }
            let classes: [UInt8]? = geometry.classification.flatMap { source in
                guard source.count == faces.count, source.stride > 0 else { return nil }
                return (0..<source.count).map { index in
                    source.buffer.contents().advanced(by: source.offset + index * source.stride).load(as: UInt8.self)
                }
            }
            patches.append(.init(anchorID: anchor.identifier, vertices: vertices, triangleIndices: indices, colors: includeColors ? colors : nil, faceClasses: classes))
            count += vertices.count
        }
        return TechnicalMeshSnapshot(timestamp: frame.timestamp, patches: patches,
                                     alignmentVerified: alignmentVerified, truncated: truncated)
    }
}
#endif
