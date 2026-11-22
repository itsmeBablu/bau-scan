#if os(iOS)
import SwiftUI
import RealityKit
import AVFoundation

/// Independent technical capture preview. Device validation pending.
/// Saving is introduced with the independent technical package milestone.
struct TechnicalRoomScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var scanner: TechnicalRoomScanCoordinator
    @AppStorage("technical.googleAI.enabled") private var googleAIEnabled = false
    @State private var viewport: ARView?
    @State private var showMesh = true
    @AppStorage("technical.showCeiling") private var showCeiling = false
    @State private var showingControls = false
    @State private var captureHeight: CGFloat = 852
    @State private var origin: TechnicalPoint3?
    @State private var frameDefined = false
    @State private var checkpointX = ""
    @State private var checkpointY = ""
    @State private var checkpointZ = ""
    @State private var threshold = "30"
    @State private var message = "Move slowly around the room. Capture pipes and ducts from several angles."
    @State private var showingAlignment = false
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
    @State private var saving = false
    @State private var awaitingThumbnail = false
    @State private var saveRequestID = UUID()
    @State private var confirmingClose = false
    @State private var saveThumbnail: Data?
    @State private var frozenCheckpointAccepted = false
    let onSaved: (UUID) -> Void
    private let previousManifest: TechnicalRoomManifest?
    private let previousRecognition: TechnicalMEPReview

    init(restoring package: TechnicalRoomPackage? = nil, onSaved: @escaping (UUID) -> Void) {
        let scanner = TechnicalRoomScanCoordinator()
        if let package {
            do { try scanner.restoreSurvey(package) }
            catch { _message = State(initialValue: error.localizedDescription) }
            _history = State(initialValue: TechnicalAnnotationHistory(document: package.document))
            _frameDefined = State(initialValue: package.alignment.referenceFrame != nil)
            _origin = State(initialValue: package.alignment.origin)
            if let checkpoint = package.alignment.checkpoints.last {
                _checkpointX = State(initialValue: String(checkpoint.expected.x))
                _checkpointY = State(initialValue: String(checkpoint.expected.y))
                _checkpointZ = State(initialValue: String(checkpoint.expected.z))
                _threshold = State(initialValue: String(checkpoint.thresholdMm))
            }
        }
        _scanner = State(initialValue: scanner)
        previousManifest = package?.manifest
        previousRecognition = package?.recognition ?? .init()
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TechnicalCaptureCamera(scanner: scanner, viewport: $viewport,showMesh: showMesh,showCeiling: showCeiling)
                    .overlay { Image(systemName: "plus").font(.title).foregroundStyle(.white).shadow(color: .black,radius: 1).allowsHitTesting(false) }
                    .overlay {
                        if let selectedPoints, let viewport, scanner.state.canAnnotate, let reference = scanner.referenceFrame {
                            TechnicalControlPointOverlay(points: history.document.points(for: selectedPoints), reference: reference, viewport: viewport) { index, location in
                                movePoint(target: selectedPoints, index: index, screen: location)
                            }
                        }
                    }
                    .coordinateSpace(name: "technicalCapture")
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    Spacer()
                    if let error = scanner.errorMessage {
                        Text(error).font(.callout).padding(12).background(.regularMaterial,in: RoundedRectangle(cornerRadius: 14))
                    }
                    if showingControls { surveyControls.frame(maxHeight: max(80,min(340,captureHeight-300))).clipShape(RoundedRectangle(cornerRadius: 24)) }
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            Label("\(scanner.liveMeshSnapshot?.capturedFaceCount ?? 0) preview faces",systemImage: "cube.transparent")
                            if scanner.liveMeshSnapshot?.hasCapturedWall == true { Label("Walls",systemImage: "square.split.2x2") }
                            if scanner.liveMeshSnapshot?.hasCapturedFloor == true { Label("Floor",systemImage: "square") }
                            Label("\(history.document.effectiveRoom.pipeRuns.count) pipe annotations",systemImage: "pipe.and.drop")
                            Label("\(history.document.ducts.count) duct annotations",systemImage: "wind")
                            Label("\(history.document.room.equipment.count) equipment annotations",systemImage: "shippingbox")
                            if scanner.liveMeshSnapshot?.truncated == true { Text("Partial live preview") }
                            Toggle("Ceiling",isOn: $showCeiling).toggleStyle(.button)
                        }.font(.caption.weight(.medium)).padding(10)
                    }.scrollIndicators(.hidden).fixedSize(horizontal: false,vertical: true)
                        .background(.regularMaterial,in: Capsule())
                    HStack(spacing: 28) {
                        Button { showingControls.toggle() } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 52,height: 52)
                        }.buttonStyle(.bordered).background(.regularMaterial,in: Circle())
                            .accessibilityLabel("Survey tools")
                        Button { scanner.takeSurveyPhoto() } label: {
                            ZStack {
                                Circle().stroke(.white,lineWidth: 4).frame(width: 76,height: 76)
                                Circle().fill(.white).frame(width: 62,height: 62)
                                if scanner.takingPhoto { ProgressView().tint(.black) }
                            }
                        }.buttonStyle(.plain).accessibilityLabel("Take survey photo")
                            .disabled(scanner.takingPhoto || !scanner.state.trackingNormal || saving)
                        Button { showMesh.toggle() } label: {
                            Image(systemName: showMesh ? "cube.fill" : "cube").frame(width: 52,height: 52)
                        }.buttonStyle(.bordered).background(.regularMaterial,in: Circle())
                            .accessibilityLabel(showMesh ? "Hide captured mesh" : "Show captured mesh")
                    }.padding(.bottom, 12)
                }.padding(.horizontal)

            }
            .disabled(saving)
            .navigationTitle("Technik Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden,for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if scanner.journal.frames.isEmpty { scanner.stop(); dismiss() } else { confirmingClose = true }
                    }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { saveSurvey() }
                        .disabled(saving || !pipeHits.isEmpty || (saveThumbnail == nil && !scanner.hasLiveFrames))
                }
            }
        }
        .tint(.blue)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captureHeight = $0 }
        .onDisappear { scanner.stop() }
        .interactiveDismissDisabled(saving || !scanner.journal.frames.isEmpty)
        .confirmationDialog("Close this unsaved technical survey?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Save survey") { saveSurvey() }.disabled(saveThumbnail == nil && !scanner.hasLiveFrames)
            Button("Discard unsaved capture", role: .destructive) { scanner.stop(); dismiss() }
        } message: { Text("Capture evidence and annotations are only retained after saving a .technicalroom package.") }
        .sheet(isPresented: $showingPipeTool) { pipeTool.presentationDetents([.medium, .large]).presentationBackgroundInteraction(.enabled(upThrough: .medium)) }
        .sheet(isPresented: $showingPipeReview) { pipeReview }
        .onAppear { scanner.aiEvidenceEnabled = googleAIEnabled }
        .onChange(of: googleAIEnabled) { _, enabled in
            scanner.aiEvidenceEnabled = enabled
        }
        .sheet(isPresented: $showingEquipmentTool) { equipmentTool }
        .sheet(isPresented: $showingAnnotations) {
            TechnicalAnnotationEditor(history: $history, scanner: scanner, hit: crosshairHit) { selectedPoints = $0 }
                .presentationDetents([.medium, .large]).presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .onChange(of: history.document) { _, document in
            if let viewport { scanner.syncAnnotations(document, in: viewport) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scanner.interrupt() }
            else if !saving { scanner.resumeCameraAfterInterruption() }
        }
        .onChange(of: scanner.state.canAnnotate) { _, verified in
            if verified, let viewport { scanner.syncAnnotations(history.document, in: viewport) }
            if !verified, !pipeHits.isEmpty {
                pipeHits = []
                message = "Alignment was lost. Uncommitted pipe points were cleared; verify the checkpoint before tracing again."
            }
        }
    }

    private var surveyControls: some View {
                Form {
                Section("Capture") {
                Text(message).font(.callout)
                if let error = scanner.errorMessage {
                    Label(error,systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
                    if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                        Button("Open camera settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
                Text("Unsaved scan · dimensions require verification").font(.caption).foregroundStyle(.secondary)
                Toggle("Google AI mode",isOn: $googleAIEnabled)
                Button { scanner.takeSurveyPhoto() } label: { Label(scanner.takingPhoto ? "Saving photo…" : "Take photo",systemImage: "camera") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(scanner.takingPhoto || !scanner.state.trackingNormal)
                Text("\(scanner.evidence.keyframes.filter { $0.userPhoto == true }.count) photos pinned to this scan. Photos are kept locally until you choose to copy them to Google Photos.")
                    .font(.caption).foregroundStyle(.secondary)
                if googleAIEnabled {
                    Label(scanner.evidenceMessage, systemImage: "camera.viewfinder").font(.caption)
                    Text("Colour/depth viewpoints stay on this device. After saving, choose images in MEP review and confirm before sending to Google AI.").font(.caption).foregroundStyle(.secondary)
                    TechnicalGoogleAIStatus()
                }
                if scanner.evidence.droppedKeyframes > 0 {
                    Text("Image budget reached: \(scanner.evidence.droppedKeyframes) older viewpoints replaced.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(scanner.healthWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                }
                DisclosureGroup("Manual survey tools") {
                if !scanner.state.canAnnotate {
                    Text("Set and verify survey alignment before placing manual annotations.").font(.caption).foregroundStyle(.secondary)
                    Button("Set survey alignment") { showingAlignment = true }
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
                }
                DisclosureGroup("Capture diagnostics") {
                Text("Journal: \(scanner.journal.frames.count) frames · \(scanner.journal.depths.count) depth · \(scanner.journal.meshes.count) mesh snapshots").font(.caption)
                Text("Saved viewpoints are coverage evidence, not a percentage of room completeness.").font(.caption).foregroundStyle(.secondary)
                if scanner.journal.retentionLimited {
                    Text("Retention limit reached: \(scanner.journal.droppedFrames) old frames and \(scanner.journal.droppedSnapshots) snapshots were discarded.").font(.caption).foregroundStyle(.orange)
                }
                Toggle("Show captured mesh", isOn: $showMesh)
                Toggle("Show ceiling mesh",isOn: $showCeiling)
                Text("Ceiling visibility affects the mesh display only. Original scan evidence is retained. Unclassified overhead pipes and ducts remain visible.").font(.caption).foregroundStyle(.secondary)

                Text("Pipes and ducts are captured as observed surfaces. Thin, reflective or hidden parts may need a close-up or manual annotation.").font(.caption).foregroundStyle(.secondary)
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
                }
                DisclosureGroup("Survey alignment",isExpanded: $showingAlignment) {
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
                }
                }
                .formStyle(.grouped)

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
    private func saveSurvey() {
        guard !saving, pipeHits.isEmpty else { message = "Keep or discard unfinished pipe points before saving."; return }
        guard saveThumbnail != nil || scanner.hasLiveFrames else { message = "Wait for live camera frames before saving this AR capture."; return }
        if let saveThumbnail { saving = true; persistSurvey(thumbnail: saveThumbnail); return }
        guard let viewport else { return }
        guard scanner.captureMeshSnapshot() else {
            message = scanner.errorMessage ?? "Capture some 3D surfaces before saving."
            return
        }
        saving = true; awaitingThumbnail = true
        let request = UUID(); saveRequestID = request
        scanner.captureDepthSnapshot()
        viewport.snapshot(saveToHDR: false) { image in
            Task { @MainActor in
                guard awaitingThumbnail, saveRequestID == request else { return }
                awaitingThumbnail = false
                guard let png = image?.pngData() else { saving = false; message = "Thumbnail capture failed. Please retry saving."; return }
                await scanner.finishEvidenceCapture()
                frozenCheckpointAccepted = scanner.state.canAnnotate
                saveThumbnail = png
                scanner.stop() // Freeze journal/evidence before writing, and release the camera promptly.
                persistSurvey(thumbnail: png)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if awaitingThumbnail, saveRequestID == request { awaitingThumbnail = false; saving = false; message = "Camera snapshot timed out. Retry when the camera is live." }
        }
    }
    private func persistSurvey(thumbnail: Data) {
        var manifest = previousManifest ?? TechnicalRoomManifest(id: history.room.id, name: "Technik Room")
        manifest.modifiedAt = Date(); manifest.checkpointAcceptedAtSave = frozenCheckpointAccepted
        let package = TechnicalRoomPackage(manifest: manifest, document: history.document, alignment: scanner.alignment,
            journal: scanner.journal, worldMapData: scanner.worldMapData, thumbnailPNG: thumbnail, evidence: scanner.evidence,
            recognition: previousRecognition)
        Task { @MainActor in
            do {
                try await TechnicalRoomLibraryStore().save(package)
                saving = false; onSaved(package.manifest.id); dismiss()
            } catch { saving = false; message = "Capture retained in memory; retry Save. \(error.localizedDescription)" }
        }
    }
}

private struct TechnicalCaptureCamera: UIViewControllerRepresentable {
    let scanner: TechnicalRoomScanCoordinator
    @Binding var viewport: ARView?
    let showMesh: Bool
    let showCeiling: Bool

    func makeUIViewController(context: Context) -> TechnicalCameraHost {
        let host = TechnicalCameraHost(scanner: scanner)
        updateMesh(host)
        DispatchQueue.main.async { viewport = host.camera }
        return host
    }
    func updateUIViewController(_ controller: TechnicalCameraHost, context: Context) { updateMesh(controller) }
    private func updateMesh(_ controller: TechnicalCameraHost) {
        controller.displayMesh(scanner.liveMeshSnapshot,visible: showMesh,showCeiling: showCeiling)
    }
    static func dismantleUIViewController(_ controller: TechnicalCameraHost, coordinator: ()) {
        controller.scanner.stop()
    }
}

private final class TechnicalCameraHost: UIViewController {
    let scanner: TechnicalRoomScanCoordinator
    let camera = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    private let meshOverlay = AnchorEntity(world: SIMD3<Float>.zero)
    private var meshTimestamp: Double?
    private var meshVisible = false
    private var ceilingVisible = false
    func displayMesh(_ snapshot: TechnicalMeshSnapshot?,visible: Bool,showCeiling: Bool) {
        guard meshTimestamp != snapshot?.timestamp || meshVisible != visible || ceilingVisible != showCeiling else { return }
        meshTimestamp = snapshot?.timestamp; meshVisible = visible; ceilingVisible = showCeiling
        meshOverlay.children.removeAll()
        guard visible,let snapshot,
              let geometry = try? TechnicalSavedMeshGeometry(snapshot: showCeiling ? snapshot : snapshot.hidingCeilings(),reference: nil) else { return }
        var descriptor = MeshDescriptor(name: "Live equipment mesh")
        descriptor.positions = MeshBuffers.Positions(geometry.vertices.map { SIMD3(Float($0.x),Float($0.y),Float($0.z)) })
        descriptor.primitives = .triangles(geometry.triangleIndices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return }
        var material = UnlitMaterial(color: UIColor.systemCyan)
        material.triangleFillMode = .lines; material.faceCulling = .none
        material.blending = .transparent(opacity: .init(floatLiteral: 0.65))
        material.writesDepth = false
        meshOverlay.addChild(ModelEntity(mesh: mesh,materials: [material]))
    }
    init(scanner: TechnicalRoomScanCoordinator) {
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
        camera.session = scanner.session
        camera.environment.background = .cameraFeed()
        camera.scene.addAnchor(meshOverlay)
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
