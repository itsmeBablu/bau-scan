import Foundation
import simd

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

/// Project onto observed triangles, including in concave or incomplete meshes.
struct TechnicalMarkerSurface {
    private let mesh: TechnicalSavedMeshGeometry
    private struct Chunk {
        let range: Range<Int>
        let low: SIMD3<Double>
        let high: SIMD3<Double>
    }
    private let chunks: [Chunk]

    init(_ mesh: TechnicalSavedMeshGeometry) {
        self.mesh = mesh
        chunks = stride(from: 0, to: mesh.triangleIndices.count, by: 192).map { start in
            let range = start..<min(start + 192, mesh.triangleIndices.count)
            var low = SIMD3<Double>(repeating: .infinity)
            var high = SIMD3<Double>(repeating: -.infinity)
            for index in mesh.triangleIndices[range] {
                let p = Self.vector(mesh.vertices[Int(index)])
                low = simd_min(low, p)
                high = simd_max(high, p)
            }
            return Chunk(range: range, low: low, high: high)
        }
    }

    private static func vector(_ p: TechnicalPoint3) -> SIMD3<Double> { .init(p.x, p.y, p.z) }

    func closest(to point: TechnicalPoint3) -> TechnicalPoint3? {
        let p = Self.vector(point)
        var bestDistance = Double.infinity
        var best: SIMD3<Double>?
        for chunk in chunks {
            let bound = simd_max(chunk.low, simd_min(chunk.high, p))
            guard simd_distance_squared(p, bound) < bestDistance else { continue }
            for i in stride(from: chunk.range.lowerBound, to: chunk.range.upperBound, by: 3) {
                func vertex(_ offset: Int) -> SIMD3<Double> {
                    Self.vector(mesh.vertices[Int(mesh.triangleIndices[i + offset])])
                }
                let a = vertex(0), b = vertex(1), c = vertex(2)
                let normal = simd_cross(b - a, c - a)
                let norm = simd_length_squared(normal)
                guard norm > 1e-16 else { continue }
                let projected = p - normal * (simd_dot(p - a, normal) / norm)
                func segment(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
                    let d = b - a
                    return a + d * min(1, max(0, simd_dot(p - a, d) / simd_length_squared(d)))
                }
                let candidate: SIMD3<Double>
                if simd_dot(simd_cross(b-a, projected-a), normal) >= 0,
                   simd_dot(simd_cross(c-b, projected-b), normal) >= 0,
                   simd_dot(simd_cross(a-c, projected-c), normal) >= 0 {
                    candidate = projected
                } else {
                    let ab = segment(a,b), bc = segment(b,c), ca = segment(c,a)
                    let side = simd_distance_squared(p, ab) < simd_distance_squared(p, bc) ? ab : bc
                    candidate = simd_distance_squared(p, side) < simd_distance_squared(p, ca) ? side : ca
                }
                let distance = simd_distance_squared(p, candidate)
                if distance < bestDistance { best = candidate; bestDistance = distance }
            }
        }
        return best.map { .init(x: $0.x, y: $0.y, z: $0.z) }
    }

    static func registered(_ notes: [ARNote], package: TechnicalRoomPackage, studio: Bool) -> [ARNote] {
        guard !notes.isEmpty else { return [] }
        let reference = package.alignment.referenceFrame
        let mesh = TechnicalSavedMeshGeometry.latest(in: package.journal.meshes)
            .flatMap { try? TechnicalSavedMeshGeometry(snapshot: $0, reference: reference) }
        let surface = mesh.map(Self.init)
        let floor = studio ? (mesh.map { $0.center.y - $0.extent.y / 2 } ?? 0) : 0
        return notes.map { original in
            var note = original
            note.displayPosition = nil
            note.markerIconPosition = nil
            guard let raw = original.position.map({ point in reference.map { TechnicalReferenceFrame.apply($0, to: point) } ?? point }) ?? original.displayPosition,
                  let anchor = surface?.closest(to: raw) else { return note }
            let displayAnchor = TechnicalPoint3(x: anchor.x, y: anchor.y - floor, z: anchor.z)
            let offset = original.audioFileName == nil ? 0.12 : 0.28
            note.displayPosition = displayAnchor
            note.markerIconPosition = .init(x: displayAnchor.x, y: displayAnchor.y + offset, z: displayAnchor.z)
            return note
        }
    }
}
