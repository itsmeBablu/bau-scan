import Foundation

struct TechnicalFrameRecord: Codable, Equatable {
    let timestamp: Double
    /// Column-major 4x4 camera-to-session transform.
    let cameraTransform: [Double]
    /// Column-major 3x3 camera intrinsics, in image pixel coordinates.
    let intrinsics: [Double]
    let imageWidth: Int
    let imageHeight: Int
    let tracking: String
    let hasSceneDepth: Bool
    let hasSmoothedSceneDepth: Bool
    let alignmentVerified: Bool
}

struct TechnicalMeshSnapshot: Codable, Equatable {
    struct Patch: Codable, Equatable {
        let anchorID: UUID
        /// Vertices transformed into the original ARSession coordinates.
        let vertices: [TechnicalPoint3]
        let triangleIndices: [UInt32]
    }
    let timestamp: Double
    let patches: [Patch]
    let alignmentVerified: Bool
    let truncated: Bool
}

/// Rolling diagnostics only. Raw depth pixels are not represented by these flags.
struct TechnicalFrameHistory {
    let capacity: Int
    private(set) var records: [TechnicalFrameRecord] = []
    private(set) var droppedCount = 0
    init(capacity: Int = 600) { self.capacity = max(1, capacity) }
    mutating func append(_ record: TechnicalFrameRecord) {
        if records.count == capacity { records.removeFirst(); droppedCount += 1 }
        records.append(record)
    }
}
