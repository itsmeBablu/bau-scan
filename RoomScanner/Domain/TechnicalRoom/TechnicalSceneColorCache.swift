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
