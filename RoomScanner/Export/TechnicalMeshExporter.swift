import Foundation
import SceneKit

/// Exports captured triangles, never substitutes a room bounding box for scan evidence.
enum TechnicalMeshExporter {
    enum Format: String, CaseIterable { case json, obj, usdz, dxf }
    enum Failure: LocalizedError {
        case writeFailed
        var errorDescription: String? { "The mesh could not be exported." }
    }

    static func write(_ package: TechnicalRoomPackage, format: Format, to url: URL, acceptedMEPOnly: Bool = false) throws {
        if format == .json {
            // Keep the established schema, provenance and MEP sidecar together.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            struct Survey: Encodable {
                let schemaVersion = 1
                let units = "m"
                let coordinateSystem = "rightHandedYUp"
                let meshCoordinates = "originalARSession; apply alignment.referenceFrame for survey coordinates"
                let document: TechnicalAnnotationDocument
                let meshes: [TechnicalMeshSnapshot]
                let alignment: TechnicalAlignmentSurvey
                let recognition: TechnicalMEPReview
            }
            var document = package.document
            document.photoAssets = [] // Photos remain in the full survey package.
            var review = package.recognition
            if acceptedMEPOnly { review.suggestions.removeAll { $0.status != .accepted } }
            try encoder.encode(Survey(document: document, meshes: acceptedMEPOnly ? [] : package.journal.meshes,
                                      alignment: package.alignment,recognition: review)).write(to: url, options: .atomic)
            return
        }
        let selectedSnapshot = acceptedMEPOnly ? try TechnicalMEPMeshBuilder.snapshot(package.recognition) : TechnicalSavedMeshGeometry.latest(in: package.journal.meshes)
        guard let snapshot = selectedSnapshot else {
            throw TechnicalSavedMeshGeometry.MeshError.empty
        }
        let mesh = try TechnicalSavedMeshGeometry(snapshot: snapshot, reference: package.alignment.referenceFrame)
        switch format {
        case .json: break
        case .obj: try obj(mesh).write(to: url, options: .atomic)
        case .dxf: try dxf(mesh).write(to: url, options: .atomic)
        case .usdz:
            let atlas = TechnicalMeshAppearance.faceAtlas(mesh)
            let positions = atlas == nil ? mesh.vertices : mesh.triangleIndices.map { mesh.vertices[Int($0)] }
            let indices = atlas == nil ? mesh.triangleIndices : (0..<positions.count).map { UInt32($0) }
            let source = SCNGeometrySource(vertices: positions.map { SCNVector3(Float($0.x), Float($0.y), Float($0.z)) })
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            var sources = [source]
            if let atlas {
                sources.append(SCNGeometrySource(textureCoordinates: atlas.uv.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }))
            }
            let geometry = SCNGeometry(sources: sources, elements: [element])
            let material = SCNMaterial()
            if let atlas { material.diffuse.contents = atlas.image }
            else { material.diffuse.contents = CGColor(gray: 0.72, alpha: 1) }
            material.isDoubleSided = true
            geometry.materials = [material]
            let scene = SCNScene()
            let surveyMesh = SCNNode(geometry: geometry)
            surveyMesh.name = "Survey_" + package.document.room.id.uuidString.replacingOccurrences(of: "-", with: "_")
            scene.rootNode.addChildNode(surveyMesh)
            guard scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) else { throw Failure.writeFailed }
        }
    }

    static func obj(_ mesh: TechnicalSavedMeshGeometry) -> Data {
        var lines = ["# dWalkScan captured LiDAR mesh; metres; Y up; accuracy unverified", "o TechnicalRoom"]
        for (i, p) in mesh.vertices.enumerated() {
            // Widely supported OBJ vertex-colour extension; no external texture files required.
            let c = mesh.colors[i] ?? .init(x: 0.72, y: 0.72, z: 0.72)
            lines.append("v \(p.x) \(p.y) \(p.z) \(c.x) \(c.y) \(c.z)")
        }
        for i in stride(from: 0, to: mesh.triangleIndices.count, by: 3) {
            lines.append("f \(mesh.triangleIndices[i] + 1) \(mesh.triangleIndices[i + 1] + 1) \(mesh.triangleIndices[i + 2] + 1)")
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    /// DXF 3DFACE entities. CAD convention Z up: (x, y, z) becomes (x, -z, y).
    static func dxf(_ mesh: TechnicalSavedMeshGeometry) -> Data {
        var lines = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1015",
                     "9", "$INSUNITS", "70", "6", "0", "ENDSEC", "0", "SECTION", "2", "ENTITIES"]
        for i in stride(from: 0, to: mesh.triangleIndices.count, by: 3) {
            lines += ["0", "3DFACE", "8", "CAPTURED_MESH"]
            let samples = (0..<3).compactMap { mesh.colors[Int(mesh.triangleIndices[i + $0])] }
            if samples.count == 3 {
                let r = Int((samples.reduce(0) { $0 + $1.x } / 3 * 255).rounded())
                let g = Int((samples.reduce(0) { $0 + $1.y } / 3 * 255).rounded())
                let b = Int((samples.reduce(0) { $0 + $1.z } / 3 * 255).rounded())
                lines += ["420", String((r << 16) | (g << 8) | b)]
            } else { lines += ["420", String(0xb8b8b8)] }
            for corner in 0..<4 {
                let p = mesh.vertices[Int(mesh.triangleIndices[i + min(corner, 2)])]
                lines += [String(10 + corner), String(p.x), String(20 + corner), String(-p.z), String(30 + corner), String(p.y)]
            }
        }
        lines += ["0", "ENDSEC", "0", "EOF"]
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
