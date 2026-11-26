import SwiftUI
import RealityKit
import ImageIO
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct HouseRadiatorListView: View {
    let house: House
    let packageURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var survey: HouseRadiatorSurvey?
    @State private var roomID: UUID?
    @State private var wallID: UUID?
    @State private var scanning = false
    @State private var error: String?
    @State private var busy = false
    @State private var editing: HouseRadiator?
    @State private var exportData: RadiatorExportDocument?
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            List {
                Section("House radiator surveys") {
                    Text("Scan each radiator body and the adjacent finished wall. Scan results are estimates; use confirmed instrument or manufacturer values where installation requires precise sizes.").font(.caption).foregroundStyle(.secondary)
                    Picker("Room",selection: $roomID) {
                        ForEach(house.allRooms) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Wall reference",selection: $wallID) {
                        Text("Not assigned").tag(UUID?.none)
                        if let room = house.allRooms.first(where: { $0.id == roomID }) {
                            ForEach(Array(room.walls.enumerated()),id: \.element.id) { i, wall in
                                Text("Wall \(i+1) · \(wall.length,specifier: "%.2f") m").tag(Optional(wall.id))
                            }
                        }
                    }
                    #if os(iOS)
                    Button { scanning = true } label: { Label("Scan radiator",systemImage: "heater.vertical") }
                        .disabled(survey == nil || busy || roomID == nil)
                    #else
                    Text("Use a LiDAR-equipped iPhone or iPad for radiator close-up capture.").font(.caption)
                    #endif
                }
                if let survey {
                    ForEach(survey.radiators) { radiator in
                        Section {
                            DisclosureGroup {
                                HouseRadiatorPreview(radiator: radiator).frame(height: 280)
                                RadiatorDimensionRows(radiator: radiator)
                                if radiator.identification == .automaticCandidate {
                                    Label("Automatically detected · equipment type unverified",systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
                                    Button("Confirm this is a radiator") { confirmIdentity(radiator) }
                                }
                                Text("\(radiator.viewpointCount) viewpoints · \(radiator.samples.count) retained surface samples").font(.caption).foregroundStyle(.secondary)
                                if let photo = radiator.photoJPEG { RadiatorPhoto(data: photo).frame(maxHeight: 220) }
                                if !radiator.notes.isEmpty { Text(radiator.notes).font(.caption) }
                                Button("Edit and confirm measurements") { editing = radiator }
                            } label: {
                                VStack(alignment: .leading,spacing: 4) {
                                    Text(radiator.name).font(.headline)
                                    Text(house.allRooms.first { $0.id == radiator.roomID }?.name ?? "Room").font(.subheadline).foregroundStyle(.secondary)
                                    Text("\(radiator.width.metres,specifier: "%.3f") × \(radiator.height.metres,specifier: "%.3f") m").font(.caption).monospacedDigit()
                                }
                            }
                        }
                    }
                    if survey.radiators.isEmpty { Text("No radiator surveys yet.").foregroundStyle(.secondary) }
                } else if busy { ProgressView() }
            }
            .navigationTitle("Radiators · Heizkörper")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .primaryAction) {
                    Button { prepareExport() } label: { Label("Export radiator measurements",systemImage: "square.and.arrow.up") }
                        .disabled(survey?.radiators.isEmpty != false || busy)
                }
            }
        }

        #if os(macOS)
        .frame(minWidth: 500,minHeight: 500)
        #endif
        .task {
            busy = true
            defer { busy = false }
            do {
                survey = try await Task.detached { try HousePackage.readRadiators(from: packageURL) }.value ?? .init(houseID: house.id)
                roomID = house.allRooms.first?.id
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: roomID) { _,_ in wallID = nil }
        #if os(iOS)
        .fullScreenCover(isPresented: $scanning) {
            if let roomID { HouseRadiatorScanView(roomID: roomID,wallID: wallID) { item in
                guard var next = survey else { throw HouseRadiatorSurvey.Failure.invalid }
                var named = item; named.name = "Radiator \(next.radiators.count+1)"
                next.radiators.append(named)
                try await persist(next)
            } }
        }
        #endif
        .sheet(item: $editing) { item in HouseRadiatorEditor(radiator: item) { updated in
            guard var next = survey,let index = next.radiators.firstIndex(where: { $0.id == updated.id }) else { throw HouseRadiatorSurvey.Failure.invalid }
            next.radiators[index] = updated
            try await persist(next)
        } }
        .fileExporter(isPresented: $exporting,document: exportData,contentType: .json,defaultFilename: "\(house.name)-radiators.json") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
        .alert("Radiator survey",isPresented: Binding(get: { error != nil },set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func confirmIdentity(_ radiator: HouseRadiator) {
        guard var next = survey,let index = next.radiators.firstIndex(where: { $0.id == radiator.id }) else { return }
        next.radiators[index].identification = .userConfirmed
        next.radiators[index].name = radiator.name.replacingOccurrences(of: "Possible radiator",with: "Radiator")
        next.radiators[index].notes = "Equipment type subsequently confirmed by user. Dimensions remain scan estimates."
        Task { @MainActor in
            do { try await persist(next) } catch { self.error = error.localizedDescription }
        }
    }
    private func persist(_ next: HouseRadiatorSurvey) async throws {
        guard !busy else { throw HouseRadiatorSurvey.Failure.invalid }
        busy = true
        defer { busy = false }
        try next.validate(for: house)
        try await Task.detached { try HousePackage.writeRadiators(next,house: house,in: packageURL) }.value
        survey = next
    }
    private func prepareExport() {
        guard let survey else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            exportData = .init(data: try encoder.encode(survey)); exporting = true
        } catch { self.error = error.localizedDescription }
    }
}

struct RadiatorDimensionRows: View {
    let radiator: HouseRadiator
    var body: some View {
        row("Body width",radiator.width)
        row("Body height",radiator.height)
        row("Body thickness / depth",radiator.depth)
        row("Wall → radiator back",radiator.wallGap)
        row("Wall → radiator front",radiator.wallToFront)
        if radiator.depth == nil || radiator.wallGap == nil {
            Text("Rear surface not sufficiently observed. Unknown values are not replaced with a generic German standard.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func row(_ name: String,_ value: RadiatorDimension?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name); Spacer()
            VStack(alignment: .trailing) {
                if let value {
                    Text("\(value.metres,specifier: "%.3f") m").monospacedDigit()
                    Text(value.label).font(.caption2).foregroundStyle(value.source == .mountingAssumption ? Color.orange : Color.secondary)
                } else { Text("Unknown").foregroundStyle(.secondary) }
            }
        }
    }
}

struct HouseRadiatorPreview: View {
    let radiator: HouseRadiator
    @State private var points = false
    @State private var reset = UUID()
    var body: some View {
        VStack(spacing: 4) {
            RealityView { content in
                let w = Float(radiator.width.metres),h = Float(radiator.height.metres),d = Float(radiator.depth?.metres ?? 0)
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: platformColor(CGColor(gray: 0.85,alpha: 1)))
                material.roughness = .init(floatLiteral: 0.7); material.faceCulling = .none
                let body = ModelEntity(mesh: d > 0 ? .generateBox(width: w,height: h,depth: d) : .generatePlane(width: w,height: h),materials: [material])
                if !points { content.add(body) }
                let wall = ModelEntity(mesh: .generatePlane(width: w*1.3,height: h*1.3),materials: [SimpleMaterial(color: platformColor(CGColor(gray: 0.4,alpha: 1)),isMetallic: false)])
                wall.position.z = d/2-Float(radiator.wallToFront.metres); content.add(wall)
                if points,let observed = try? observedModel(frontZ: d/2) { content.add(observed) }
                let camera = PerspectiveCamera(),radius = max(w,h,0.5)
                camera.look(at: .zero,from: SIMD3(radius*0.7,radius*0.4,radius*1.5),relativeTo: nil)
                content.add(camera); content.camera = .virtual
                let light = DirectionalLight(); light.light.intensity = 2000
                light.look(at: .zero,from: SIMD3(1,2,2),relativeTo: nil); content.add(light)
            }
            .realityViewCameraControls(.orbit)
            .accessibilityElement(children: .ignore).accessibilityLabel("Radiator survey preview")
            .id(reset).background(Color(white: 0.12))
            HStack {
                Toggle("Observed surfaces",isOn: $points).toggleStyle(.button).disabled(radiator.samples.isEmpty)
                Spacer()
                Button { reset = UUID() } label: { Label("Reset view",systemImage: "scope") }.labelStyle(.iconOnly)
            }.font(.caption)
            Text("Survey envelope, not an engineering CAD model. Unknown depth is displayed flat.").font(.caption2).foregroundStyle(.secondary)
        }
        .onChange(of: points) { _,_ in reset = UUID() }
        .onChange(of: radiator) { _,_ in reset = UUID() }
    }
    private func observedModel(frontZ: Float) throws -> ModelEntity {
        let frame = try RadiatorScanGeometry(frontCorners: radiator.frontCorners,wall: radiator.wallSample)
        var positions: [SIMD3<Float>] = [],indices: [UInt32] = []
        for sample in radiator.samples {
            let p = frame.local(sample.point)
            let center = SIMD3(Float(p.x-radiator.width.metres/2),Float(p.y-radiator.height.metres/2),Float(p.z)+frontZ)
            let n = SIMD3<Float>(Float(sample.normal.dot(frame.right)),Float(sample.normal.y),Float(sample.normal.dot(frame.frontNormal)))
            let tangent = simd_normalize(simd_cross(n,abs(n.y) < 0.9 ? SIMD3(0,1,0) : SIMD3(1,0,0)))*0.003
            let second = simd_normalize(simd_cross(n,tangent))*0.003
            let offset = UInt32(positions.count)
            positions += [center-tangent-second,center+tangent-second,center+second]
            indices += [offset,offset+1,offset+2]
        }
        var descriptor = MeshDescriptor(name: "observed-radiator-surfaces")
        descriptor.positions = .init(positions); descriptor.primitives = .triangles(indices)
        var material = PhysicallyBasedMaterial(); material.baseColor = .init(tint: platformColor(CGColor(gray: 0.8,alpha: 1))); material.faceCulling = .none
        return ModelEntity(mesh: try .generate(from: [descriptor]),materials: [material])
    }
}

private struct RadiatorPhoto: View {
    let data: Data
    @State private var image: CGImage?
    var body: some View {
        Group { if let image { Image(decorative: image,scale: 1).resizable().scaledToFit() } }
            .task { if let source = CGImageSourceCreateWithData(data as CFData,nil) { image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways: true,kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary) } }
    }
}
private struct RadiatorExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { .init(regularFileWithContents: data) }
}

private struct HouseRadiatorEditor: View {
    let radiator: HouseRadiator
    let save: (HouseRadiator) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var width = 0.0
    @State private var height = 0.0
    @State private var depth: Double?
    @State private var gap: Double?
    @State private var source = RadiatorDimension.Source.tapeMeasure
    @State private var reference = ""
    @State private var notes = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Radiator") { TextField("Name",text: $name); TextField("Notes",text: $notes,axis: .vertical) }
                Section("Confirm dimensions") {
                    Picker("Source for changed values",selection: $source) {
                        Text("Tape measurement").tag(RadiatorDimension.Source.tapeMeasure)
                        Text("Laser measurement").tag(RadiatorDimension.Source.laserMeasure)
                        Text("Manufacturer data").tag(RadiatorDimension.Source.manufacturer)
                    }
                    if source == .manufacturer { TextField("Manufacturer/model/document reference",text: $reference) }
                    TextField("Body width (m)",value: $width,format: .number)
                    TextField("Body height (m)",value: $height,format: .number)
                    TextField("Depth (m), blank if unknown",value: $depth,format: .number)
                    TextField("Wall → back gap (m), blank if unknown",value: $gap,format: .number)
                    Text("Unchanged values retain their original source. Changing a value records your selected source and preserves the raw scan. No millimetre accuracy is certified.").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(DS.ColorToken.error.color) }
                if busy { ProgressView("Saving…") }
            }.formStyle(.grouped).disabled(busy)
            .navigationTitle("Radiator measurements")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { persist() }.disabled(busy) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 450,minHeight: 500)
        #endif
        .interactiveDismissDisabled(busy)
        .onAppear { name = radiator.name; width = radiator.width.metres; height = radiator.height.metres; depth = radiator.depth?.metres; gap = radiator.wallGap?.metres; notes = radiator.notes }
    }
    private func persist() {
        func changed(_ old: RadiatorDimension?,_ value: Double?) -> RadiatorDimension? {
            guard old?.metres != value else { return old }
            return value.map { .init(metres: $0,source: source,method: "userConfirmedRadiatorDimension",reference: source == .manufacturer ? reference : nil) }
        }
        var updated = radiator; updated.name = name; updated.notes = notes
        updated.width = changed(radiator.width,width) ?? radiator.width
        updated.height = changed(radiator.height,height) ?? radiator.height
        updated.depth = changed(radiator.depth,depth); updated.wallGap = changed(radiator.wallGap,gap)
        do { try updated.validate() } catch { self.error = error.localizedDescription; return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await save(updated); dismiss() } catch { self.error = error.localizedDescription }
        }
    }
}
