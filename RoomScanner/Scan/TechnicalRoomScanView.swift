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
    @State private var pipes: [TechnicalPipeRun] = []
    @State private var diameter = ""
    @State private var nominalDN = ""
    @State private var insulation = "0"
    @State private var medium = TechnicalMedium.heatingSupply
    @State private var showingPipeTool = false
    let onSaved: (LibraryItem) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TechnicalCaptureCamera(scanner: scanner, viewport: $viewport)
                    .overlay { Image(systemName: "plus").font(.title).foregroundStyle(.yellow).allowsHitTesting(false) }
                Text(message).font(.callout)
                Text("Device validation pending · Unsaved capture preview").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save recovery map") { scanner.saveRecoveryMap() }
                        .disabled(!scanner.state.trackingNormal)
                    Button("Resume from map") { scanner.resume() }
                        .disabled(!scanner.recoveryAvailable)
                }
                if scanner.recovering { Text("Relocalising — checkpoint verification required").font(.caption) }
                Button("Pipe annotation") { showingPipeTool = true }
                    .disabled(!scanner.state.canAnnotate)
                Text("Unsaved pipe runs: \(pipes.count)").font(.caption)
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
                }
                if let error = scanner.errorMessage { Text(error).foregroundStyle(.red) }
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scanner.interrupt() }
            // Resumption is explicit and always invalidates the alignment checkpoint.
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
            material: .init(value: "unspecified", unit: "text", source: .entered, method: "notSpecified", accuracyMm: nil),
            nominalDN: nominalDN.isEmpty ? nil : .init(value: nominalDN, unit: "text", source: .entered, method: "manualEntry", accuracyMm: nil),
            outerDiameterMm: .init(value: outside, unit: "mm", source: .entered, method: "manualEntryRequiresVerification", accuracyMm: nil),
            insulationThicknessMm: .init(value: insulationValue, unit: "mm", source: .entered, method: "manualEntry", accuracyMm: nil),
            surfaceHits: pipeHits, connectedPorts: [])
        pipes.append(pipe)
        pipeHits = []
        showingPipeTool = false
        message = "Pipe retained in memory. Length \(pipe.length.value) m."
    }

    private func setCorner() {
        guard let viewport, let hit = scanner.hit(at: CGPoint(x: viewport.bounds.midX, y: viewport.bounds.midY), viewport: viewport) else {
            message = "No reliable surface hit. Move slowly and try again."; return
        }
        if let origin {
            do {
                try scanner.setReference(origin: origin, xCorner: hit)
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
        camera.debugOptions.insert(.showSceneUnderstanding)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = camera }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scanner.start()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        scanner.stop()
    }
}
#endif
