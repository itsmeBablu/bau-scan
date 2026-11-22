import Foundation

/// Bounded, transient multi-view colour samples in AR-session coordinates.
/// The final snapshot bakes samples into vertices; no camera buffers are retained.
struct TechnicalSceneColorCache {
    private struct Key: Hashable { let x: Int; let y: Int; let z: Int }
    private var samples: [Key: TechnicalPoint3] = [:]
    private let capacity: Int
    init(capacity: Int = 150_000) { self.capacity = max(1, capacity) }
    var count: Int { samples.count }
    private func key(_ p: TechnicalPoint3) -> Key {
        .init(x: Int((p.x * 200).rounded()), y: Int((p.y * 200).rounded()), z: Int((p.z * 200).rounded()))
    }
    mutating func merge(_ snapshot: TechnicalMeshSnapshot) -> TechnicalMeshSnapshot {
        let patches = snapshot.patches.map { patch in
            var result = patch
            result.colors = patch.vertices.enumerated().map { i, point in
                guard TechnicalPointEditing.valid(point) else { return nil }
                let location = key(point)
                if let colors = patch.colors, i < colors.count, let color = colors[i] {
                    if samples[location] != nil || samples.count < capacity { samples[location] = color }
                    return color
                }
                return samples[location]
            }
            return result
        }
        return .init(timestamp: snapshot.timestamp, patches: patches, alignmentVerified: snapshot.alignmentVerified, truncated: snapshot.truncated)
    }
}

/// Retains the latest copy of each observed anchor when a later frame has fewer anchors.
/// Updates replace geometry, rather than layering duplicate triangles over old surfaces.
struct TechnicalSceneMeshCache {
    private var patches: [UUID: TechnicalMeshSnapshot.Patch] = [:]
    private var order: [UUID] = []
    private let maximumVertices: Int
    init(maximumVertices: Int = 250_000) { self.maximumVertices = maximumVertices }
    mutating func merge(_ snapshot: TechnicalMeshSnapshot) -> TechnicalMeshSnapshot {
        for patch in snapshot.patches where !patch.triangleIndices.isEmpty {
            if patches[patch.anchorID] == nil { order.append(patch.anchorID) }
            patches[patch.anchorID] = patch
        }
        var count = 0
        var truncated = snapshot.truncated
        // Prefer recently observed geometry under memory pressure.
        var retained: [TechnicalMeshSnapshot.Patch] = []
        for id in order.reversed() {
            guard let patch = patches[id] else { continue }
            if count + patch.vertices.count <= maximumVertices {
                retained.append(patch); count += patch.vertices.count
            } else { patches.removeValue(forKey: id); truncated = true }
        }
        order.removeAll { patches[$0] == nil }
        return .init(timestamp: snapshot.timestamp, patches: retained.reversed(),
                     alignmentVerified: snapshot.alignmentVerified, truncated: truncated)
    }
}
