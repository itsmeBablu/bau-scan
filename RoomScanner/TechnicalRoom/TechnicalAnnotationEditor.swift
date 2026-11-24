#if os(iOS)
import SwiftUI
import PhotosUI
import ImageIO
import RealityKit
import UIKit

struct TechnicalAnnotationEditor: View {
    @AppStorage("renovation.proDetails") private var proDetails = false
    @Binding var history: TechnicalAnnotationHistory
    @Bindable var scanner: TechnicalRoomScanCoordinator
    let hit: () -> TechnicalSurfaceHit?
    let editPoints: (TechnicalAnnotationTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var pipeID: UUID?
    @State private var equipmentID: UUID?
    @State private var portID: UUID?
    @State private var endpoint = TechnicalPipeConnection.Endpoint.start
    @State private var diameter = 22.0
    @State private var insulation = 0.0
    @State private var equipmentSize = TechnicalPoint3(x: 1, y: 1, z: 1)
    @State private var equipmentName = ""
    @State private var equipmentYaw = 0.0
    @State private var pipeMaterial = ""
    @State private var pipeDN = ""
    @State private var ductID: UUID?
    @State private var fittingType = TechnicalFittingType.valve
    @State private var direction = TechnicalPoint3(x: 1, y: 0, z: 0)
    @State private var portMedium = TechnicalMedium.other
    @State private var portDN = ""
    @State private var ductPoints: [TechnicalValue<TechnicalPoint3>] = []
    @State private var ductWidth = 0.2
    @State private var ductHeight = 0.1
    @State private var measurementStart: TechnicalValue<TechnicalPoint3>?
    @State private var measurementID: UUID?
    @State private var referenceLength = 1.0
    @State private var note = ""
    @State private var photo: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Text("Manual survey annotations · accuracy unknown · not yet saved")
                    .font(.caption).foregroundStyle(.secondary)
                if !scanner.state.canAnnotate { Text("Alignment verification required before editing.").foregroundStyle(.orange) }
                if let error { Text(error).foregroundStyle(.red) }
                HStack {
                    Button("Undo") { history.undo() }.disabled(!history.canUndo)
                    Button("Redo") { history.redo() }.disabled(!history.canRedo)
                }.disabled(!scanner.state.canAnnotate)
                Group {
                    pipeSection
                    equipmentSection
                    ductSection
                    measurementSection
                    notesSection
                }.disabled(!scanner.state.canAnnotate)
                Section("Connection review") {
                    ForEach(history.document.connectionWarnings, id: \.self) { Text($0).font(.caption) }
                    ForEach(history.document.connections) { connection in
                        HStack {
                            Text("\(connection.endpoint.rawValue) → \(connection.portID.uuidString.prefix(8))")
                            Button("Disconnect", role: .destructive) { change { doc in
                                doc.connections.removeAll { $0.id == connection.id }
                                if let i = doc.room.pipeRuns.firstIndex(where: { $0.id == connection.pipeID }) {
                                    doc.room.pipeRuns[i].connectedPorts.removeAll { $0 == connection.portID }
                                }
                            } }.disabled(!scanner.state.canAnnotate)
                        }
                    }
                }
            }
            .navigationTitle("Annotations")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onChange(of: pipeID) { _, id in
            if let pipe = history.room.pipeRuns.first(where: { $0.id == id }) {
                diameter = pipe.outerDiameterMm.value; insulation = pipe.insulationThicknessMm?.value ?? 0
                pipeMaterial = pipe.material.value; pipeDN = pipe.nominalDN?.value ?? ""
            }
        }
        .onChange(of: equipmentID) { _, id in
            if let item = history.room.equipment.first(where: { $0.id == id }) {
                equipmentSize = item.size.value; equipmentName = item.name.value; equipmentYaw = item.rotation.value * 180 / .pi
            }
        }
        .onChange(of: ductID) { _, id in
            if let item = history.document.ducts.first(where: { $0.id == id }) { ductWidth = item.width.value; ductHeight = item.height.value }
        }
        .onChange(of: portID) { _, id in
            if let port = history.room.equipment.flatMap(\.ports).first(where: { $0.id == id }) {
                direction = port.direction.value; portMedium = port.medium.value; portDN = port.nominalDN?.value ?? ""
            }
        }
        .onChange(of: scanner.state.canAnnotate) { _, verified in
            if !verified { ductPoints = []; measurementStart = nil }
        }
        .onChange(of: photo) { _, item in
            Task { @MainActor in
                do {
                    guard let raw = try await item?.loadTransferable(type: Data.self), raw.count <= 20 * 1_048_576,
                          let source = CGImageSourceCreateWithData(raw as CFData, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                              kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
                          let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { error = "Choose an image smaller than 20 MiB."; return }
                    let id = UUID()
                    change {
                        $0.photoAssets.append(.init(id: id, jpegData: jpeg))
                        $0.room.photos.append(.init(id: id, reference: .init(value: "photos/\(id.uuidString).jpg", unit: "text", source: .entered, method: "userSelectedSurveyPhoto", accuracyMm: nil)))
                    }
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    private var pipeSection: some View {
        Section("Pipes and fittings") {
            Picker("Pipe", selection: $pipeID) {
                Text("Choose pipe").tag(UUID?.none)
                ForEach(history.room.pipeRuns, id: \.id) { Text($0.id.uuidString.prefix(8)).tag(Optional($0.id)) }
            }
            TextField("Outside diameter (mm)", value: $diameter, format: .number)
            TextField("Insulation (mm)", value: $insulation, format: .number)
            TextField("Material", text: $pipeMaterial)
            if proDetails { TextField("DN (optional)", text: $pipeDN) }
            Button("Update dimensions") { change { doc in
                guard let i = doc.room.pipeRuns.firstIndex(where: { $0.id == pipeID }) else { throw TechnicalAnnotationHistory.EditError.missingReference }
                doc.room.pipeRuns[i].outerDiameterMm = entered(diameter, "mm")
                doc.room.pipeRuns[i].insulationThicknessMm = entered(insulation, "mm")
                doc.room.pipeRuns[i].material = entered(pipeMaterial, "text")
                doc.room.pipeRuns[i].nominalDN = pipeDN.isEmpty ? nil : entered(pipeDN, "text")
            } }
            Button("Edit pipe points in camera") { if let pipeID { editPoints(.pipe(pipeID)); dismiss() } }.disabled(pipeID == nil)
            Button("Delete pipe", role: .destructive) { perform { if let pipeID { try history.deletePipe(pipeID, capture: scanner.state) } } }
            Picker("Fitting", selection: $fittingType) {
                ForEach([TechnicalFittingType.valve, .elbow, .tee, .reducer, .flange, .cross, .cap, .other], id: \.self) { Text($0.rawValue).tag($0) }
            }
            Button("Add fitting at crosshair") { withHit { value in
                guard let pipeID else { throw TechnicalAnnotationHistory.EditError.missingReference }
                change { $0.room.fittings.append(.init(id: UUID(), type: entered(fittingType, "category"), position: value.position, hostPipeRunId: pipeID)) }
            } }
            ForEach(history.room.fittings, id: \.id) { fitting in
                HStack {
                    Text(fitting.type.value.rawValue)
                    Button("Move to crosshair") { withHit { value in change { doc in
                        if let i = doc.room.fittings.firstIndex(where: { $0.id == fitting.id }) { doc.room.fittings[i].position = value.position }
                    } } }
                    Button("Delete", role: .destructive) { change { $0.room.fittings.removeAll { $0.id == fitting.id } } }
                }
            }
        }
    }
    private var equipmentSection: some View {
        Section("Equipment ports") {
            Picker("Equipment", selection: $equipmentID) {
                Text("Choose equipment").tag(UUID?.none)
                ForEach(history.room.equipment, id: \.id) { Text($0.name.value).tag(Optional($0.id)) }
            }
            TextField("Width (m)", value: $equipmentSize.x, format: .number)
            TextField("Height (m)", value: $equipmentSize.y, format: .number)
            TextField("Depth (m)", value: $equipmentSize.z, format: .number)
            TextField("Name", text: $equipmentName)
            TextField("Yaw (degrees)", value: $equipmentYaw, format: .number)
            Button("Update equipment dimensions") { change { doc in
                guard let i = doc.room.equipment.firstIndex(where: { $0.id == equipmentID }) else { throw TechnicalAnnotationHistory.EditError.missingReference }
                doc.room.equipment[i].size = entered(equipmentSize, "m")
                doc.room.equipment[i].name = entered(equipmentName, "text")
                // Ports are room-space observations; rotating a housing does not invent new port observations.
                doc.room.equipment[i].rotation = entered(equipmentYaw * .pi / 180, "rad")
            } }
            Button("Move equipment base to crosshair") { withHit { value in change { doc in
                guard let i = doc.room.equipment.firstIndex(where: { $0.id == equipmentID }) else { throw TechnicalAnnotationHistory.EditError.missingReference }
                var center = value.position; center.value.y += doc.room.equipment[i].size.value.y / 2
                center.source = .estimated; center.method = "surfaceBasePlusEnteredHalfHeight"
                let old = doc.room.equipment[i].center.value
                let delta = TechnicalPoint3(x: center.value.x - old.x, y: center.value.y - old.y, z: center.value.z - old.z)
                for j in doc.room.equipment[i].ports.indices {
                    let p = doc.room.equipment[i].ports[j].position.value
                    doc.room.equipment[i].ports[j].position = entered(.init(x: p.x + delta.x, y: p.y + delta.y, z: p.z + delta.z), "m")
                }
                doc.room.equipment[i].center = center
            } } }
            Button("Delete equipment", role: .destructive) { perform { if let equipmentID { try history.deleteEquipment(equipmentID, capture: scanner.state) } } }
            TextField("Port direction X", value: $direction.x, format: .number)
            TextField("Port direction Y", value: $direction.y, format: .number)
            TextField("Port direction Z", value: $direction.z, format: .number)
            Picker("Port medium", selection: $portMedium) {
                ForEach(TechnicalMedium.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if proDetails { TextField("Port DN (optional)", text: $portDN) }
            Button("Add port at crosshair") { withHit { value in change { doc in
                guard let i = doc.room.equipment.firstIndex(where: { $0.id == equipmentID }) else { throw TechnicalAnnotationHistory.EditError.missingReference }
                let length = direction.distance(to: .init(x: 0, y: 0, z: 0))
                guard length.isFinite, length > 1e-9 else { throw TechnicalAnnotationHistory.EditError.invalidGeometry }
                doc.room.equipment[i].ports.append(.init(id: UUID(), position: value.position,
                    direction: entered(.init(x: direction.x / length, y: direction.y / length, z: direction.z / length), "unitless"),
                    nominalDN: portDN.isEmpty ? nil : entered(portDN, "text"), medium: entered(portMedium, "category")))
            } } }
            Picker("Port", selection: $portID) {
                Text("Choose port").tag(UUID?.none)
                ForEach(history.room.equipment.flatMap(\.ports), id: \.id) { Text($0.id.uuidString.prefix(8)).tag(Optional($0.id)) }
            }
            Picker("Pipe end", selection: $endpoint) { ForEach(TechnicalPipeConnection.Endpoint.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Button("Connect selected pipe and port") { perform {
                guard let pipeID, let portID else { throw TechnicalAnnotationHistory.EditError.missingReference }
                try history.connect(pipeID: pipeID, endpoint: endpoint, portID: portID, capture: scanner.state)
            } }
            Button("Delete selected port", role: .destructive) { perform { if let portID { try history.deletePort(portID, capture: scanner.state) } } }
            Button("Update selected port properties") { change { doc in
                let length = direction.distance(to: .init(x: 0, y: 0, z: 0))
                guard length.isFinite, length > 1e-9 else { throw TechnicalAnnotationHistory.EditError.invalidGeometry }
                guard let i = doc.room.equipment.firstIndex(where: { $0.ports.contains(where: { $0.id == portID }) }),
                      let j = doc.room.equipment[i].ports.firstIndex(where: { $0.id == portID }) else { throw TechnicalAnnotationHistory.EditError.missingReference }
                doc.room.equipment[i].ports[j].direction = entered(.init(x: direction.x / length, y: direction.y / length, z: direction.z / length), "unitless")
                doc.room.equipment[i].ports[j].medium = entered(portMedium, "category")
                doc.room.equipment[i].ports[j].nominalDN = portDN.isEmpty ? nil : entered(portDN, "text")
            } }
        }
    }
    private var ductSection: some View {
        Section("Rectangular duct routes") {
            Text("Place the intended duct centreline manually; surface hits are not automatically converted into a duct centre.").font(.caption)
            TextField("Width (m)", value: $ductWidth, format: .number)
            TextField("Height (m)", value: $ductHeight, format: .number)
            Picker("Existing duct", selection: $ductID) {
                Text("Choose duct").tag(UUID?.none)
                ForEach(history.document.ducts) { Text($0.id.uuidString.prefix(8)).tag(Optional($0.id)) }
            }
            Button("Update duct dimensions") { change { doc in
                guard let i = doc.ducts.firstIndex(where: { $0.id == ductID }) else { throw TechnicalAnnotationHistory.EditError.missingReference }
                doc.ducts[i].width = entered(ductWidth, "m"); doc.ducts[i].height = entered(ductHeight, "m")
            } }
            Button("Add centreline point at crosshair (\(ductPoints.count))") { withHit { value in
                var p = value.position; p.source = .estimated; p.method = "userConfirmedCentrelineFromRaycast"; ductPoints.append(p)
            } }
            Button("Undo draft point") { if !ductPoints.isEmpty { ductPoints.removeLast() } }
            Button("Keep duct") {
                change { $0.ducts.append(.init(id: UUID(), width: entered(ductWidth, "m"), height: entered(ductHeight, "m"), points: ductPoints)) }
                if error == nil { ductPoints = [] }
            }.disabled(ductPoints.count < 2)
            ForEach(history.document.ducts) { duct in
                HStack {
                    Text("\(duct.width.value, specifier: "%.2f") × \(duct.height.value, specifier: "%.2f") m")
                    Button("Points") { editPoints(.duct(duct.id)); dismiss() }
                    Button("Delete", role: .destructive) { change {
                        $0.ducts.removeAll { $0.id == duct.id }; $0.pointOverrides.removeAll { $0.objectID == duct.id }
                    } }
                }
            }
        }
    }
    private var measurementSection: some View {
        Section("Point measurements and length calibration") {
            Button(measurementStart == nil ? "Set measurement start at crosshair" : "Set measurement end at crosshair") { withHit { value in
                if let start = measurementStart {
                    change { $0.measurements.append(.init(id: UUID(), name: "Point measurement", start: start, end: value.position)) }
                    if error == nil { measurementStart = nil }
                } else { measurementStart = value.position }
            } }
            Button("Clear measurement draft") { measurementStart = nil }
            ForEach(history.document.measurements) { measurement in
                HStack {
                    Text("\(history.document.correctedLength(measurement.length), specifier: "%.3f") m")
                    Button("Delete", role: .destructive) { change {
                        $0.measurements.removeAll { $0.id == measurement.id }
                        if $0.calibration?.measurementID == measurement.id { $0.calibration = nil }
                    } }
                }
            }
            Picker("Calibration baseline", selection: $measurementID) {
                Text("Choose measurement").tag(UUID?.none)
                ForEach(history.document.measurements) { Text("\($0.length, specifier: "%.3f") m").tag(Optional($0.id)) }
            }
            TextField("Independently measured reference (m)", value: $referenceLength, format: .number)
            Button("Apply length correction") { change { doc in
                guard let measurement = doc.measurements.first(where: { $0.id == measurementID }) else { throw TechnicalAnnotationHistory.EditError.missingReference }
                doc.calibration = .init(measurementID: measurement.id, referenceLength: entered(referenceLength, "m"),
                                       observedLength: .init(value: measurement.length, unit: "m", source: .estimated, method: "distanceBetweenRaycastPoints", accuracyMm: nil))
            } }
            Button("Remove length correction") { change { $0.calibration = nil } }
            Text("Length correction is derived from the entered reference. Raw observations and AR geometry stay unchanged; accuracy remains unknown.").font(.caption)
        }
    }
    private var notesSection: some View {
        Section("Photos and notes") {
            TextField("Survey note", text: $note, axis: .vertical)
            Button("Add note") { change { $0.room.notes.append(entered(note, "text")) }; if error == nil { note = "" } }.disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(Array(history.room.notes.enumerated()), id: \.offset) { index, value in
                HStack { Text(value.value); Button("Delete", role: .destructive) { change { if $0.room.notes.indices.contains(index) { $0.room.notes.remove(at: index) } } } }
            }
            PhotosPicker("Add survey photo", selection: $photo, matching: .images)
            ForEach(history.room.photos, id: \.id) { value in
                HStack {
                    Text("Photo \(value.id.uuidString.prefix(8))")
                    Button("Link to equipment") { change { doc in
                        guard let i = doc.room.equipment.firstIndex(where: { $0.id == equipmentID }) else { throw TechnicalAnnotationHistory.EditError.missingReference }
                        if !doc.room.equipment[i].photoRefs.contains(value.id) { doc.room.equipment[i].photoRefs.append(value.id) }
                    } }
                    Button("Delete", role: .destructive) { change { doc in
                        doc.room.photos.removeAll { $0.id == value.id }; doc.photoAssets.removeAll { $0.id == value.id }
                        for i in doc.room.equipment.indices { doc.room.equipment[i].photoRefs.removeAll { $0 == value.id } }
                    } }
                }
            }
        }
    }
    private func entered<T: Codable & Equatable>(_ value: T, _ unit: String) -> TechnicalValue<T> { .init(value: value, unit: unit, source: .entered, method: "manualEntryRequiresVerification", accuracyMm: nil) }
    private func change(_ mutation: (inout TechnicalAnnotationDocument) throws -> Void) {
        perform { try history.edit(capture: scanner.state, mutation) }
    }
    private func perform(_ operation: () throws -> Void) {
        let before = history.document
        do {
            try operation()
            if history.document != before { scanner.lockReference() }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func withHit(_ operation: (TechnicalSurfaceHit) throws -> Void) {
        do {
            guard scanner.state.canAnnotate, let value = hit() else { error = "Aim at a tracked surface with verified alignment."; return }
            try operation(value)
        } catch { self.error = error.localizedDescription }
    }
}

struct TechnicalControlPointOverlay: View {
    let points: [TechnicalPoint3]
    let reference: TechnicalTransform
    let viewport: ARView
    let move: (Int, CGPoint) -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            ZStack(alignment: .topLeading) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    let p = TechnicalReferenceFrame.inverseApply(reference, to: point)
                    if let screen = viewport.project(SIMD3(Float(p.x), Float(p.y), Float(p.z))), viewport.bounds.contains(screen) {
                        TechnicalPointHandle(index: index, screen: screen) { move(index, $0) }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
private struct TechnicalPointHandle: View {
    let index: Int
    let screen: CGPoint
    let dropped: (CGPoint) -> Void
    @GestureState private var translation: CGSize = .zero
    var body: some View {
        Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
            .frame(width: 36, height: 36).background(.blue, in: Circle())
            .position(screen).offset(translation)
            .accessibilityLabel("Control point \(index + 1)")
            .gesture(DragGesture(coordinateSpace: .named("technicalCapture"))
                .updating($translation) { value, state, _ in state = value.translation }
                .onEnded { dropped($0.location) })
    }
}
#endif
