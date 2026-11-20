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
    let onSaved: (LibraryItem) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TechnicalCaptureCamera(scanner: scanner, viewport: $viewport)
                    .overlay { Image(systemName: "plus").font(.title).foregroundStyle(.yellow).allowsHitTesting(false) }
                Text(message).font(.callout)
                Text("Device validation pending · Unsaved capture preview").font(.caption).foregroundStyle(.secondary)
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scanner.interrupt() }
            // A new preview is required after backgrounding until world-map recovery is implemented.
        }
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

private struct TechnicalCaptureCamera: UIViewRepresentable {
    let scanner: TechnicalRoomScanCoordinator
    @Binding var viewport: ARView?

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = scanner.session
        view.debugOptions.insert(.showSceneUnderstanding)
        DispatchQueue.main.async {
            viewport = view
            scanner.start()
        }
        return view
    }
    func updateUIView(_ view: ARView, context: Context) {}
}
#endif
