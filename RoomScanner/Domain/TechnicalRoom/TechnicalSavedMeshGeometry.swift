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

// Filtering never changes the saved evidence. Unknown surfaces remain visible so
// unclassified pipes and ducts are not discarded along with architectural surfaces.
extension TechnicalMeshSnapshot {
    /// ARKit ceiling class only. Preserve overhead ducts and unknown surfaces.
    func hidingCeilings() -> TechnicalMeshSnapshot {
        let filtered = patches.map { patch -> Patch in
            guard let classes = patch.faceClasses,classes.count == patch.triangleIndices.count/3 else { return patch }
            let kept = classes.indices.filter { classes[$0] != 3 }
            return Patch(anchorID: patch.anchorID,vertices: patch.vertices,
                triangleIndices: kept.flatMap { Array(patch.triangleIndices[($0*3)..<($0*3+3)]) },colors: patch.colors,
                faceClasses: kept.map { classes[$0] })
        }
        return .init(timestamp: timestamp,patches: filtered,alignmentVerified: alignmentVerified,truncated: truncated)
    }
    var capturedFaceCount: Int { patches.reduce(0) { $0+$1.triangleIndices.count/3 } }
    var hasCapturedWall: Bool { patches.contains { $0.faceClasses?.contains(1) == true } }
    var hasCapturedFloor: Bool { patches.contains { $0.faceClasses?.contains(2) == true } }
    func hidingRoomSurfaces() -> TechnicalMeshSnapshot {
        let filtered = patches.map { patch -> Patch in
            guard let classes = patch.faceClasses, classes.count == patch.triangleIndices.count / 3 else { return patch }
            let indices = classes.indices.filter { ![UInt8(1), 2, 3, 6, 7].contains(classes[$0]) }
                .flatMap { Array(patch.triangleIndices[($0 * 3)..<($0 * 3 + 3)]) }
            return Patch(anchorID: patch.anchorID, vertices: patch.vertices, triangleIndices: indices, colors: patch.colors)
        }
        return .init(timestamp: timestamp, patches: filtered, alignmentVerified: alignmentVerified, truncated: truncated)
    }
}

// Display correction for legacy markers outside the captured mesh extents.
// Raw observations and mesh vertices remain unchanged.
extension TechnicalSavedMeshGeometry {
    func containedMarker(_ point:TechnicalPoint3) -> TechnicalPoint3 {
        let inside = abs(point.x-center.x) <= extent.x/2 && abs(point.y-center.y) <= extent.y/2 && abs(point.z-center.z) <= extent.z/2
        guard !inside else { return point }
        return vertices.min { $0.distance(to:point) < $1.distance(to:point) } ?? point
    }
}
