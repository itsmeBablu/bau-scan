import Foundation

/// Display geometry derived from a saved snapshot. The original evidence is never modified.
struct TechnicalSavedMeshGeometry {
    enum MeshError: LocalizedError {
        case empty, invalid
        var errorDescription: String? {
            switch self {
            case .empty: "No triangle mesh was saved in this survey. The survey details and photos are still available."
            case .invalid: "The saved mesh contains invalid geometry and cannot be displayed."
            }
        }
    }
    let vertices: [TechnicalPoint3]
    let triangleIndices: [UInt32]
    let center: TechnicalPoint3
    let extent: TechnicalPoint3
    let colors: [TechnicalPoint3?]

    init(snapshot: TechnicalMeshSnapshot, reference: TechnicalTransform?) throws {
        var vertices: [TechnicalPoint3] = [], indices: [UInt32] = []
        var colors: [TechnicalPoint3?] = []
        for patch in snapshot.patches {
            guard patch.triangleIndices.count % 3 == 0,
                  patch.triangleIndices.allSatisfy({ Int($0) < patch.vertices.count }),
                  vertices.count + patch.vertices.count <= 250_000 else { throw MeshError.invalid }
            let offset = UInt32(vertices.count)
            guard patch.colors == nil || (patch.colors!.count == patch.vertices.count && patch.colors!.allSatisfy({
                $0 == nil || [$0!.x, $0!.y, $0!.z].allSatisfy { $0.isFinite && (0...1).contains($0) }
            })) else { throw MeshError.invalid }
            colors.append(contentsOf: patch.colors ?? Array(repeating: nil, count: patch.vertices.count))
            for point in patch.vertices {
                let p = reference.map { TechnicalReferenceFrame.apply($0, to: point) } ?? point
                guard TechnicalPointEditing.valid(p) else { throw MeshError.invalid }
                vertices.append(p)
            }
            indices.append(contentsOf: patch.triangleIndices.map { $0 + offset })
        }
        guard !vertices.isEmpty, !indices.isEmpty else { throw MeshError.empty }
        let xs = vertices.map(\.x), ys = vertices.map(\.y), zs = vertices.map(\.z)
        let low = TechnicalPoint3(x: xs.min()!, y: ys.min()!, z: zs.min()!)
        let high = TechnicalPoint3(x: xs.max()!, y: ys.max()!, z: zs.max()!)
        self.center = .init(x: (low.x + high.x) / 2, y: (low.y + high.y) / 2, z: (low.z + high.z) / 2)
        self.extent = .init(x: high.x - low.x, y: high.y - low.y, z: high.z - low.z)
        self.vertices = vertices; triangleIndices = indices
        self.colors = colors
    }
    static func latest(in snapshots: [TechnicalMeshSnapshot]) -> TechnicalMeshSnapshot? {
        snapshots.last { $0.patches.contains { !$0.triangleIndices.isEmpty } }
    }
}
