#if os(iOS)
import ARKit
import Darwin

enum TechnicalRoomFrameProcessor {
    /// Copies one raw scene-depth frame. No temporal smoothing is presented as raw depth.
    static func depthSnapshot(frame: ARFrame, alignmentVerified: Bool) -> TechnicalDepthSnapshot? {
        guard let depth = frame.sceneDepth else { return nil }
        let buffer = depth.depthMap
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0, width <= 1024, height <= 1024 else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var values: [Float?] = []
        values.reserveCapacity(width * height)
        for row in 0..<height {
            let pixels = base.advanced(by: row * stride).assumingMemoryBound(to: Float.self)
            for column in 0..<width {
                let value = pixels[column]
                values.append(value.isFinite && value > 0 ? value : nil)
            }
        }
        var confidence: [UInt8]?
        if let map = depth.confidenceMap,
           CVPixelBufferGetWidth(map) == width, CVPixelBufferGetHeight(map) == height {
            CVPixelBufferLockBaseAddress(map, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
            if let address = CVPixelBufferGetBaseAddress(map) {
                let rowStride = CVPixelBufferGetBytesPerRow(map)
                var copied: [UInt8] = []
                copied.reserveCapacity(width * height)
                for row in 0..<height {
                    let pixels = address.advanced(by: row * rowStride).assumingMemoryBound(to: UInt8.self)
                    copied.append(contentsOf: UnsafeBufferPointer(start: pixels, count: width))
                }
                confidence = copied
            }
        }
        let transform = frame.camera.transform, intrinsics = frame.camera.intrinsics
        return .init(timestamp: frame.timestamp, width: width, height: height,
            imageWidth: Int(frame.camera.imageResolution.width), imageHeight: Int(frame.camera.imageResolution.height),
            cameraTransform: (0..<4).flatMap { column in (0..<4).map { Double(transform[column][$0]) } },
            intrinsics: (0..<3).flatMap { column in (0..<3).map { Double(intrinsics[column][$0]) } },
            depthMetres: values, confidence: confidence, alignmentVerified: alignmentVerified)
    }

    static func residentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
    }
}
#endif
