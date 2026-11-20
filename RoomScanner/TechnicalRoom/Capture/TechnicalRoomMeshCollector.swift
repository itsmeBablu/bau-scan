#if os(iOS)
import ARKit

/// Copies one bounded snapshot on request, never retains Metal buffer pointers.
enum TechnicalRoomMeshCollector {
    static func snapshot(frame: ARFrame, alignmentVerified: Bool, maximumVertices: Int = 250_000) -> TechnicalMeshSnapshot {
        var patches: [TechnicalMeshSnapshot.Patch] = []
        var count = 0
        var truncated = false
        for anchor in frame.anchors.compactMap({ $0 as? ARMeshAnchor }) {
            let geometry = anchor.geometry
            guard count + geometry.vertices.count <= maximumVertices else { truncated = true; continue }
            let source = geometry.vertices
            var vertices: [TechnicalPoint3] = []
            vertices.reserveCapacity(source.count)
            for index in 0..<source.count {
                let address = source.buffer.contents().advanced(by: source.offset + index * source.stride)
                let x = address.load(as: Float.self)
                let y = address.advanced(by: 4).load(as: Float.self)
                let z = address.advanced(by: 8).load(as: Float.self)
                let world = anchor.transform * SIMD4<Float>(x, y, z, 1)
                vertices.append(.init(x: Double(world.x), y: Double(world.y), z: Double(world.z)))
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
            patches.append(.init(anchorID: anchor.identifier, vertices: vertices, triangleIndices: indices))
            count += vertices.count
        }
        return TechnicalMeshSnapshot(timestamp: frame.timestamp, patches: patches,
                                     alignmentVerified: alignmentVerified, truncated: truncated)
    }
}
#endif
