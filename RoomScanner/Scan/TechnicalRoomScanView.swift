#if os(iOS)
import SwiftUI
import RealityKit

/// Independent technical capture preview. Device validation pending.
/// Saving is introduced with the independent technical package milestone.
struct TechnicalRoomScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var scanner = TechnicalRoomScanCoordinator()
    @State private var viewport: ARView?
    @State private var origin: TechnicalPoint3?
    @State private var frameDefined = false
    @State private var checkpointX = ""
    @State private var checkpointY = ""
    @State private var checkpointZ = ""
    @State private var threshold = "30"
    @State private var message = "Aim at the first known floor corner."
    @State private var pipeHits: [TechnicalSurfaceHit] = []
    @State private var history = TechnicalAnnotationHistory(room: .capturedShell(id: UUID(), notes: ""))
    private var pipes: [TechnicalPipeRun] { history.room.pipeRuns }
    private var equipment: [TechnicalEquipment] { history.room.equipment }
    @State private var showingAnnotations = false
    @State private var selectedPoints: TechnicalAnnotationTarget?
    @State private var pointAxis = TechnicalPointEditing.Axis.free
    @State private var pointGrid = 0.01
    @State private var diameter = ""
    @State private var nominalDN = ""
    @State private var insulation = "0"
    @State private var medium = TechnicalMedium.heatingSupply
    @State private var showingPipeTool = false
    @State private var showingPipeReview = false
    @State private var material = ""
    @State private var showingEquipmentTool = false
    @State private var equipmentType = TechnicalEquipmentType.boiler
    @State private var equipmentName = ""
    @State private var equipmentWidth = ""
    @State private var equipmentDepth = ""
    @State private var equipmentHeight = ""
    @State private var equipmentYaw = "0"
    @State private var equipmentError: String?
    let onSaved: (LibraryItem) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TechnicalCaptureCamera(scanner: scanner, viewport: $viewport)
                    .overlay { Image(systemName: "plus").font(.title).foregroundStyle(.yellow).allowsHitTesting(false) }
                    .overlay {
                        if let selectedPoints, let viewport, scanner.state.canAnnotate, let reference = scanner.referenceFrame {
                            TechnicalControlPointOverlay(points: history.document.points(for: selectedPoints), reference: reference, viewport: viewport) { index, location in
                                movePoint(target: selectedPoints, index: index, screen: location)
                            }
                        }
                    }
                    .coordinateSpace(name: "technicalCapture")
                    .frame(minHeight: 180, maxHeight: .infinity)
                ScrollView {
                VStack(spacing: 12) {
                Text(message).font(.callout)
                Text("Device validation pending · Unsaved capture preview").font(.caption).foregroundStyle(.secondary)
                ForEach(scanner.healthWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                Text("Journal: \(scanner.journal.frames.count) frames · \(scanner.journal.depths.count) depth · \(scanner.journal.meshes.count) mesh snapshots")
                    .font(.caption)
                if scanner.journal.retentionLimited {
                    Text("Retention limit reached: \(scanner.journal.droppedFrames) old frames and \(scanner.journal.droppedSnapshots) snapshots were discarded.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if scanner.alignment.referenceLocked { Label("Reference frame locked", systemImage: "lock.fill").font(.caption) }
                HStack {
                    Button("Save recovery map") { scanner.saveRecoveryMap() }
                        .disabled(!scanner.state.canAnnotate)
                    Button("Resume from map") { scanner.resume() }
                        .disabled(!scanner.recoveryAvailable)
                }
                if scanner.recovering {
                    Text(scanner.recoveryTrackingReady ? "Map tracking recovered — verify the independent checkpoint" : "Relocalising — annotations remain locked")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button("Pipe annotation") { showingPipeTool = true }
                    .disabled(!scanner.state.canAnnotate)
                Text("Unsaved pipe runs: \(pipes.count)").font(.caption)
                Button("Review pipe runs") { showingPipeReview = true }.disabled(pipes.isEmpty)
                Button("Place equipment") { showingEquipmentTool = true }.disabled(!scanner.state.canAnnotate)
                Button("Annotation tools") { showingAnnotations = true }.disabled(!scanner.state.canAnnotate)
                HStack {
                    Button("Undo") { history.undo() }.disabled(!history.canUndo || !scanner.state.canAnnotate)
                    Button("Redo") { history.redo() }.disabled(!history.canRedo || !scanner.state.canAnnotate)
                }
                if selectedPoints != nil {
                    Text("Drag numbered surface control points in the camera view.").font(.caption)
                    Picker("Axis lock", selection: $pointAxis) { ForEach(TechnicalPointEditing.Axis.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    TextField("Snap grid (m; 0 disables)", value: $pointGrid, format: .number)
                    Button("Finish point editing") { selectedPoints = nil }
                }
                Text("Unsaved equipment: \(equipment.count)").font(.caption)
                Button("Capture mesh snapshot") { scanner.captureMeshSnapshot() }
                    .disabled(!scanner.state.trackingNormal)
                Button("Capture depth snapshot") { scanner.captureDepthSnapshot() }
                    .disabled(!scanner.state.trackingNormal)
                if let bytes = scanner.residentMemoryBytes {
                    Text("Resident memory \(Double(bytes) / 1_048_576, specifier: "%.1f") MiB").font(.caption)
                }
                if let depth = scanner.depthSnapshot {
                    Text("Depth snapshot \(depth.width) × \(depth.height)").font(.caption)
                }
                if let snapshot = scanner.meshSnapshot {
                    Text("Snapshot: \(snapshot.patches.count) patches\(snapshot.truncated ? " — size limit reached" : "")")
                        .font(.caption)
                }
                HStack {
                    Text("FPS \(scanner.fps, specifier: "%.0f")")
                    Text("Mesh anchors \(scanner.meshAnchorCount)")
                    Text(scanner.state.phase.rawValue)
                }.font(.caption)
                if !frameDefined {
                    Button(origin == nil ? "Set origin at crosshair" : "Set +X floor corner at crosshair") { setCorner() }
                        .disabled(!scanner.state.trackingNormal)
                } else {
                    Text("Third checkpoint: use independently measured coordinates away from the origin–X baseline.").font(.caption)
                    HStack {
                        TextField("Checkpoint X (m)", text: $checkpointX)
                        TextField("Y (m)", text: $checkpointY)
                        TextField("Z (m)", text: $checkpointZ)
                    }
                    HStack {
                        TextField("Tolerance (mm)", text: $threshold)
                        Button("Check point at crosshair") { verify() }
                    }
                    if let residual = scanner.state.checkpointResidualMm {
                        Text("Checkpoint residual \(residual, specifier: "%.1f") mm")
                    }
                    Text(scanner.state.canAnnotate ? "Alignment checkpoint accepted" : "Alignment verification required")
                    Text("\(scanner.alignment.checkpoints.count) checkpoint observations recorded").font(.caption)
                }
                if let error = scanner.errorMessage { Text(error).foregroundStyle(.red) }
                }
                .textFieldStyle(.roundedBorder)
                }
                .frame(maxHeight: 300)
            }
            .padding()
            .navigationTitle("Technical Room")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { scanner.stop(); dismiss() }
                }
            }
        }
        .onDisappear { scanner.stop() }
        .sheet(isPresented: $showingPipeTool) { pipeTool }
        .sheet(isPresented: $showingPipeReview) { pipeReview }
        .sheet(isPresented: $showingEquipmentTool) { equipmentTool }
        .sheet(isPresented: $showingAnnotations) {
            TechnicalAnnotationEditor(history: $history, scanner: scanner, hit: crosshairHit) { selectedPoints = $0 }
        }
        .onChange(of: history.document) { _, document in
            if let viewport { scanner.syncAnnotations(document, in: viewport) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scanner.interrupt() }
            // Resumption is explicit and always invalidates the alignment checkpoint.
        }
        .onChange(of: scanner.state.canAnnotate) { _, verified in
            if !verified, !pipeHits.isEmpty {
                pipeHits = []
                message = "Alignment was lost. Uncommitted pipe points were cleared; verify the checkpoint before tracing again."
            }
        }
    }

    private var pipeTool: some View {
        NavigationStack {
            Form {
                Text("Aim the camera crosshair at the visible pipe surface. Close this sheet to adjust the camera view between points.")
                Text("Points: \(pipeHits.count)")
                Button("Add crosshair point") {
                    guard let viewport,
                          let hit = scanner.surfaceHit(at: CGPoint(x: viewport.bounds.midX, y: viewport.bounds.midY), viewport: viewport) else {
                        message = "Alignment or surface hit unavailable."; return
                    }
                    pipeHits.append(hit)
                }.disabled(!scanner.state.canAnnotate)
                Button("Undo point") { if !pipeHits.isEmpty { pipeHits.removeLast() } }
                Picker("Medium", selection: $medium) {
                    ForEach(TechnicalMedium.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Measured outside diameter (mm)", text: $diameter)
                TextField("DN designation (optional)", text: $nominalDN)
                TextField("Material", text: $material)
                TextField("Insulation thickness (mm)", text: $insulation)
                Button("Keep pipe run in preview") { keepPipe() }
                    .disabled(!scanner.state.canAnnotate || pipeHits.count < 2)
                Text("Accuracy unknown. This does not save a survey package.").font(.caption)
            }
            .navigationTitle("Pipe route")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Back to camera") { showingPipeTool = false } } }
        }
    }

    private func keepPipe() {
        guard scanner.state.canAnnotate, let outside = Double(diameter), outside.isFinite, outside > 0,
              let insulationValue = Double(insulation), insulationValue.isFinite, insulationValue >= 0 else {
            message = "Enter a positive outside diameter and nonnegative insulation thickness."; return
        }
        let pipe = TechnicalPipeRun(id: UUID(), medium: .init(value: medium, unit: "category", source: .entered, method: "userSelection", accuracyMm: nil),
            systemLabel: .init(value: medium.rawValue, unit: "text", source: .entered, method: "userSelection", accuracyMm: nil),
            material: .init(value: material.isEmpty ? "unspecified" : material, unit: "text", source: .entered, method: material.isEmpty ? "notSpecified" : "manualEntry", accuracyMm: nil),
            nominalDN: nominalDN.isEmpty ? nil : .init(value: nominalDN, unit: "text", source: .entered, method: "manualEntry", accuracyMm: nil),
            outerDiameterMm: .init(value: outside, unit: "mm", source: .entered, method: "manualEntryRequiresVerification", accuracyMm: nil),
            insulationThicknessMm: .init(value: insulationValue, unit: "mm", source: .entered, method: "manualEntry", accuracyMm: nil),
            surfaceHits: pipeHits, connectedPorts: [])
        do { try history.addPipe(pipe, capture: scanner.state) }
        catch { message = error.localizedDescription; return }
        scanner.lockReference()
        if let viewport { scanner.showPipe(pipe, in: viewport) }
        pipeHits = []
        showingPipeTool = false
        message = "Pipe retained in memory. Length \(pipe.length.value) m."
    }

    private var pipeReview: some View {
        NavigationStack {
            List {
                Text("Unsaved annotations · accuracy unknown").font(.caption)
                ForEach(pipes, id: \.id) { pipe in
                    VStack(alignment: .leading) {
                        Text(pipe.medium.value.rawValue)
                        Text("\(pipe.length.value, specifier: "%.3f") m · OD \(pipe.outerDiameterMm.value, specifier: "%.1f") mm")
                        Text(pipe.nominalDN?.value ?? "DN unspecified").font(.caption)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { pipes[$0].id }
                    for id in ids { do { try history.deletePipe(id, capture: scanner.state) } catch { message = error.localizedDescription } }
                }
            }
            .navigationTitle("Pipe review")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingPipeReview = false } } }
        }
    }

    private var equipmentTool: some View {
        NavigationStack {
            Form {
                Text("The crosshair hit sets the equipment base centre. Enter verified dimensions in metres.")
                Picker("Type", selection: $equipmentType) {
                    ForEach(TechnicalEquipmentType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Name", text: $equipmentName)
                TextField("Width (m)", text: $equipmentWidth)
                TextField("Depth (m)", text: $equipmentDepth)
                TextField("Height (m)", text: $equipmentHeight)
                TextField("Rotation around +Y (degrees)", text: $equipmentYaw)
                Button("Place at crosshair") { placeEquipment() }.disabled(!scanner.state.canAnnotate)
                if let equipmentError { Text(equipmentError).foregroundStyle(.red) }
                Section("Unsaved equipment") {
                    ForEach(equipment, id: \.id) { item in Text(item.name.value) }
                        .onDelete { offsets in
                            let ids = offsets.map { equipment[$0].id }
                            for id in ids { do { try history.deleteEquipment(id, capture: scanner.state) } catch { message = error.localizedDescription } }
                        }
                }
            }
            .navigationTitle("Manual equipment")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Back to camera") { showingEquipmentTool = false } } }
        }
    }

    private func placeEquipment() {
        guard let width = Double(equipmentWidth), let depth = Double(equipmentDepth), let height = Double(equipmentHeight),
              let yaw = Double(equipmentYaw), [width, depth, height, yaw].allSatisfy({ $0.isFinite }),
              width > 0, depth > 0, height > 0, width < 100, depth < 100, height < 100,
              let viewport, let hit = scanner.surfaceHit(at: CGPoint(x: viewport.bounds.midX, y: viewport.bounds.midY), viewport: viewport) else {
            equipmentError = "Enter positive dimensions and aim at a tracked base position with verified alignment."; return
        }
        let base = hit.position.value
        let item = TechnicalEquipment(id: UUID(),
            type: .init(value: equipmentType, unit: "category", source: .entered, method: "manualSelection", accuracyMm: nil),
            name: .init(value: equipmentName.isEmpty ? equipmentType.rawValue : equipmentName, unit: "text", source: .entered, method: "manualEntry", accuracyMm: nil),
            center: .init(value: .init(x: base.x, y: base.y + height / 2, z: base.z), unit: "m", source: .estimated, method: "surfaceBasePlusEnteredHalfHeight", accuracyMm: nil),
            size: .init(value: .init(x: width, y: height, z: depth), unit: "m", source: .entered, method: "manualDimensionsRequireVerification", accuracyMm: nil),
            rotation: .init(value: yaw * .pi / 180, unit: "rad", source: .entered, method: "manualYaw", accuracyMm: nil), ports: [], photoRefs: [])
        do { try history.edit(capture: scanner.state) { $0.room.equipment.append(item) } }
        catch { equipmentError = error.localizedDescription; return }
        scanner.lockReference()
        scanner.showEquipment(item, in: viewport)
        equipmentError = nil
        showingEquipmentTool = false
    }

    private func setCorner() {
        guard let viewport, let hit = scanner.hit(at: CGPoint(x: viewport.bounds.midX, y: viewport.bounds.midY), viewport: viewport) else {
            message = "No reliable surface hit. Move slowly and try again."; return
        }
        if let origin {
            do {
                try scanner.setReference(origin: origin, xCorner: hit)
                var room = TechnicalRoom.capturedShell(id: scanner.captureID, notes: "")
                if let reference = scanner.referenceFrame { room.shellToRoom.value = reference; room.shellToRoom.method = "twoFloorCornersAndGravity" }
                history = TechnicalAnnotationHistory(room: room)
                frameDefined = true
                message = "Enter the independently measured coordinates of a third checkpoint, then aim at it."
            } catch { message = "Choose two distinct floor corners more than 10 cm apart." }
        } else {
            origin = hit
            message = "Aim at the second known floor corner along the intended +X axis."
        }
    }

    private func verify() {
        guard let x = Double(checkpointX), let y = Double(checkpointY), let z = Double(checkpointZ),
              let tolerance = Double(threshold), tolerance > 0,
              let viewport,
              let point = scanner.hit(at: CGPoint(x: viewport.bounds.midX, y: viewport.bounds.midY), viewport: viewport) else {
            message = "Enter valid coordinates and tolerance, and aim at a tracked surface."; return
        }
        scanner.verifyCheckpoint(observed: point, expected: .init(x: x, y: y, z: z), thresholdMm: tolerance)
    }

    private func crosshairHit() -> TechnicalSurfaceHit? {
        guard let viewport else { return nil }
        return scanner.surfaceHit(at: CGPoint(x: viewport.bounds.midX, y: viewport.bounds.midY), viewport: viewport)
    }
    private func movePoint(target: TechnicalAnnotationTarget, index: Int, screen: CGPoint) {
        guard let viewport, let hit = scanner.surfaceHit(at: screen, viewport: viewport) else { message = "No tracked surface at the dropped point."; return }
        let points = history.document.points(for: target)
        do {
            let point = try TechnicalPointEditing.adjust(hit.position.value, origin: index > 0 ? points[index - 1] : nil,
                axis: pointAxis, gridMetres: pointGrid, snapPoints: points.enumerated().filter { $0.offset != index }.map(\.element))
            try history.move(target: target, index: index, to: point, observation: hit, capture: scanner.state)
        } catch { message = error.localizedDescription }
    }
}

private struct TechnicalCaptureCamera: UIViewControllerRepresentable {
    let scanner: TechnicalRoomScanCoordinator
    @Binding var viewport: ARView?

    func makeUIViewController(context: Context) -> TechnicalCameraHost {
        let host = TechnicalCameraHost(scanner: scanner)
        DispatchQueue.main.async { viewport = host.camera }
        return host
    }
    func updateUIViewController(_ controller: TechnicalCameraHost, context: Context) {}
    static func dismantleUIViewController(_ controller: TechnicalCameraHost, coordinator: ()) {
        controller.scanner.stop()
    }
}

private final class TechnicalCameraHost: UIViewController {
    let scanner: TechnicalRoomScanCoordinator
    let camera = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    init(scanner: TechnicalRoomScanCoordinator) {
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
        camera.session = scanner.session
        camera.environment.background = .cameraFeed()
        camera.debugOptions.insert(.showSceneUnderstanding)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = camera }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scanner.start()
    }
    // Modal annotation sheets must not destroy the capture. The representable's
    // dismantle hook owns final teardown; scenePhase handles real interruptions.
}
#endif
