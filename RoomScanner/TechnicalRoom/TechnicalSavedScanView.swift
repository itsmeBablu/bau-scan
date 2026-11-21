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
    var selectedSuggestion: UUID? = nil
    var onPhotoLink: ((UUID,URL) async throws -> Void)? = nil
    @State private var showPhotos = false
    @State private var selectedPhoto: TechnicalCaptureKeyframe?
    @State private var appearance = Appearance.both
    private enum Appearance: Hashable { case scan, mep, both }
    @State private var resetID = UUID()
    @State private var renderError: String?

    var body: some View {
        VStack(spacing: 0) {
            if package.evidence.keyframes.contains(where: { $0.userPhoto == true }) {
                Toggle(isOn: $showPhotos) { Label("Photos",systemImage: "camera") }.padding(.horizontal).padding(.vertical,6)
            }
            if !package.recognition.suggestions.isEmpty {
                Picker("Display",selection: $appearance) {
                    Text("Scan").tag(Appearance.scan)
                    Text("MEP").tag(Appearance.mep)
                    Text("Both").tag(Appearance.both)
                }.pickerStyle(.segmented).padding(8)
            }
            if let snapshot = TechnicalSavedMeshGeometry.latest(in: package.journal.meshes) {
                RealityView { content in
                    do {
                        let geometry = try TechnicalSavedMeshGeometry(snapshot: snapshot, reference: package.alignment.referenceFrame)
                        let model = try makeModel(geometry)
                        if appearance != .mep { content.add(model) }
                        if appearance != .scan {
                            for item in package.recognition.suggestions where item.status == .accepted || item.id == selectedSuggestion {
                                content.add(makeMEPModel(item,center: geometry.center,reference: package.alignment.referenceFrame))
                            }
                        }
                        let camera = PerspectiveCamera()
                        let radius = Float(max(geometry.extent.x, geometry.extent.y, geometry.extent.z, 0.5))
                        camera.look(at: .zero, from: SIMD3(radius * 0.9, radius * 0.65, radius * 1.1), relativeTo: nil)
                        content.add(camera)
                        content.camera = .virtual
                        let light = DirectionalLight()
                        light.light.intensity = 2500
                        light.look(at: .zero, from: SIMD3(radius, radius * 2, radius), relativeTo: nil)
                        content.add(light)
                        if showPhotos {
                            let markerTexture = try TextureResource.generate(from: photoMarkerImage(),options: .init(semantic: .color))
                            for photo in package.evidence.keyframes where photo.userPhoto == true {
                                var markerMaterial = UnlitMaterial()
                                markerMaterial.color = .init(texture: .init(markerTexture))
                                let size = max(0.08,min(0.2,radius*0.035))
                                let marker = ModelEntity(mesh: .generatePlane(width: size,height: size),materials: [markerMaterial])
                                marker.name = "technicalPhoto:\(photo.id.uuidString)"
                                    let m = photo.depth.cameraTransform
                                    let p = TechnicalPoint3(x: m[12],y: m[13],z: m[14])
                                    let transformed = package.alignment.referenceFrame.map { TechnicalReferenceFrame.apply($0,to: p) } ?? p
                                    marker.position = SIMD3(Float(transformed.x-geometry.center.x),Float(transformed.y-geometry.center.y),Float(transformed.z-geometry.center.z))
                                    marker.components.set(BillboardComponent())
                                    marker.components.set(InputTargetComponent())
                                    marker.generateCollisionShapes(recursive: false)
                                    content.add(marker)
                            }
                        }
                    } catch { renderError = error.localizedDescription }
                }
                .realityViewCameraControls(.orbit)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Saved 3D survey")
                .accessibilityHint("Drag to rotate. Use Reset view or the numbered photo buttons below.")
                .gesture(TapGesture().targetedToAnyEntity().onEnded { value in
                    let prefix = "technicalPhoto:"
                    guard value.entity.name.hasPrefix(prefix),let id = UUID(uuidString: String(value.entity.name.dropFirst(prefix.count))) else { return }
                    selectedPhoto = package.evidence.keyframes.first { $0.id == id }
                })
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
            if showPhotos {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(package.evidence.keyframes.filter { $0.userPhoto == true }.enumerated()),id: \.element.id) { i, photo in
                            Button { selectedPhoto = photo } label: { Label("Photo \(i+1)",systemImage: "camera") }.buttonStyle(.bordered)
                        }
                    }.padding(8)
                }
            }
        }
        .accessibilityIdentifier("technical.savedScanViewer")
        .onChange(of: package.recognition) { _,_ in resetID = UUID() }
        .onChange(of: selectedSuggestion) { _,_ in resetID = UUID() }
        .onChange(of: appearance) { _,_ in resetID = UUID() }
        .onChange(of: showPhotos) { _,_ in resetID = UUID() }
        .sheet(item: $selectedPhoto) { photo in TechnicalSurveyPhotoView(photo: photo,persistLink: onPhotoLink) }
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
    private func photoMarkerImage() -> CGImage {
        let context = CGContext(data: nil,width: 64,height: 64,bitsPerComponent: 8,bytesPerRow: 256,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.18,alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: 64,height: 64))
        context.setStrokeColor(CGColor(gray: 1,alpha: 1)); context.setLineWidth(3)
        context.stroke(CGRect(x: 12,y: 17,width: 40,height: 29))
        context.strokeEllipse(in: CGRect(x: 24,y: 23,width: 16,height: 16))
        context.setFillColor(CGColor(gray: 1,alpha: 1)); context.fill(CGRect(x: 20,y: 46,width: 12,height: 5))
        return context.makeImage()!
    }

    private func makeMEPModel(_ item: TechnicalMEPSuggestion,center: TechnicalPoint3,reference: TechnicalTransform?) -> ModelEntity {
        func position(_ p: TechnicalPoint3) -> SIMD3<Float> {
            let v = reference.map { TechnicalReferenceFrame.apply($0,to: p) } ?? p
            return SIMD3(Float(v.x-center.x),Float(v.y-center.y),Float(v.z-center.z))
        }
        let start = position(item.start), end = position(item.end)
        let axis = simd_normalize(end-start)
        let mesh: MeshResource
        if item.kind == .rectangularDuct { mesh = .generateBox(width: Float(item.width),height: simd_length(end-start),depth: Float(item.height)) }
        else { mesh = .generateCylinder(height: simd_length(end-start),radius: Float(item.width/2)) }
        let color = item.color ?? .init(x: 0.65,y: 0.65,z: 0.65)
        var material = PhysicallyBasedMaterial()
        #if os(iOS)
        material.baseColor = .init(tint: UIColor(red: color.x,green: color.y,blue: color.z,alpha: 1))
        #else
        material.baseColor = .init(tint: NSColor(srgbRed: color.x,green: color.y,blue: color.z,alpha: 1))
        #endif
        material.metallic = .init(floatLiteral: item.material == .bareMetal ? 1 : 0)
        let roughness: Float = switch item.material { case .captured, .insulation: 0.8; case .paintedMetal: 0.5; case .bareMetal: 0.35; case .plastic: 0.45 }
        material.roughness = .init(floatLiteral: roughness)
        let model = ModelEntity(mesh: mesh,materials: [material])
        model.position = (start+end)/2
        let crossPoint = MEPVector.add(item.start,item.crossAxis)
        let x = simd_normalize(position(crossPoint)-start)
        model.orientation = simd_quatf(simd_float3x3(columns: (x,axis,simd_normalize(simd_cross(x,axis)))))
        return model
    }
}
