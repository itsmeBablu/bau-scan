import SwiftUI
import RealityKit
import simd
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Offline viewing does not require a world map, camera permissions or live alignment.
struct TechnicalSavedScanView: View {
    let package: TechnicalRoomPackage
    @State private var resetID = UUID()
    @State private var renderError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = TechnicalSavedMeshGeometry.latest(in: package.journal.meshes) {
                RealityView { content in
                    do {
                        let geometry = try TechnicalSavedMeshGeometry(snapshot: snapshot, reference: package.alignment.referenceFrame)
                        let model = try makeModel(geometry)
                        content.add(model)
                        let camera = PerspectiveCamera()
                        let radius = Float(max(geometry.extent.x, geometry.extent.y, geometry.extent.z, 0.5))
                        camera.look(at: .zero, from: SIMD3(radius * 0.9, radius * 0.65, radius * 1.1), relativeTo: nil)
                        content.add(camera)
                        content.camera = .virtual
                        let light = DirectionalLight()
                        light.light.intensity = 2500
                        light.look(at: .zero, from: SIMD3(radius, radius * 2, radius), relativeTo: nil)
                        content.add(light)
                    } catch { renderError = error.localizedDescription }
                }
                .realityViewCameraControls(.orbit)
                .id(resetID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.12))
                .overlay {
                    if let renderError { ContentUnavailableView(renderError, systemImage: "exclamationmark.triangle") }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Saved LiDAR mesh").font(.caption.bold())
                        Text("Drag to rotate · pinch to zoom").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { renderError = nil; resetID = UUID() } label: { Label("Reset view", systemImage: "scope") }
                        .labelStyle(.iconOnly).buttonStyle(.bordered)
                }.padding(12).background(.regularMaterial)
                Text(snapshot.patches.contains(where: { $0.colors?.contains(where: { $0 != nil }) == true }) ? "Camera-sampled colours; unseen surfaces are grey. Accuracy unverified." : "No camera colours saved; showing grey geometry. Accuracy unverified.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 6)
                if snapshot.truncated { Text("Partial mesh: capture limit reached.").font(.caption).foregroundStyle(.secondary) }
            } else {
                ContentUnavailableView("No saved 3D mesh", systemImage: "cube.transparent", description: Text("Open Survey details to inspect the saved evidence and photos. A recovery map is only needed to resume aligned AR capture."))
            }
        }
        .accessibilityIdentifier("technical.savedScanViewer")
    }

    private func makeModel(_ geometry: TechnicalSavedMeshGeometry) throws -> ModelEntity {
        let center = geometry.center
        let vertices = geometry.vertices.map { SIMD3<Float>(Float($0.x - center.x), Float($0.y - center.y), Float($0.z - center.z)) }
        var normals = Array(repeating: SIMD3<Float>.zero, count: vertices.count)
        for i in stride(from: 0, to: geometry.triangleIndices.count, by: 3) {
            let a = Int(geometry.triangleIndices[i]), b = Int(geometry.triangleIndices[i + 1]), c = Int(geometry.triangleIndices[i + 2])
            let n = simd_cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
            normals[a] += n; normals[b] += n; normals[c] += n
        }
        normals = normals.map { simd_length_squared($0) > 1e-12 ? simd_normalize($0) : SIMD3(0, 1, 0) }
        var descriptor = MeshDescriptor(name: "saved-technical-mesh")
        descriptor.positions = .init(vertices)
        descriptor.normals = .init(normals)
        descriptor.primitives = .triangles(geometry.triangleIndices)
        var material = PhysicallyBasedMaterial()
        #if os(iOS)
        material.baseColor = .init(tint: UIColor(white: 0.72, alpha: 1))
        #else
        material.baseColor = .init(tint: NSColor(white: 0.72, alpha: 1))
        #endif
        material.roughness = .init(floatLiteral: 0.8)
        material.faceCulling = .none
        if let atlas = TechnicalMeshAppearance.faceAtlas(geometry) {
            descriptor.positions = .init(geometry.triangleIndices.map { vertices[Int($0)] })
            descriptor.normals = .init(geometry.triangleIndices.map { normals[Int($0)] })
            descriptor.primitives = .triangles((0..<geometry.triangleIndices.count).map { UInt32($0) })
            descriptor.textureCoordinates = .init(atlas.uv)
            let texture = try TextureResource.generate(from: atlas.image, options: .init(semantic: .color))
            material.baseColor = .init(texture: .init(texture))
        }
        let mesh = try MeshResource.generate(from: [descriptor])
        return ModelEntity(mesh: mesh, materials: [material])
    }
}
